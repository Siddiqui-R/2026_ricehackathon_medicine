// Purpose: Implement RevaStore and AccountStore using PostgreSQL transactions and the bundled ordered schema migrations.
// Inputs: PostgreSQL configuration, authenticated owner IDs, snapshots, attachment bytes, revisions, and account records.
// Outputs: Stored aggregate/account data or typed conflict/missing/quota/account errors plus propagated database failures.
// Side effects: Opens database queries, migrates schema, and commits snapshot/attachment/audit/account mutations.
// Ownership: Runtime values are bound parameters. Each mutation commits separately, not as one full sync transaction.

import Foundation
import PostgresNIO
import Vapor

// MARK: - Database client ownership and health
public struct PostgresStore: RevaStore, AccountStore {
    public let client: PostgresClient
    private let logger = Logger(label: "reva.postgres")

    public init(configuration: PostgresClient.Configuration) {
        client = PostgresClient(configuration: configuration)
    }

    public func health() async throws {
        let rows = try await client.query("SELECT 1", logger: logger)
        for try await _ in rows {}
    }

    // MARK: - Ordered migrations under a database advisory lock
    /// Migration source contains only checked-in SQL, never request data. Every version above the recorded
    /// maximum runs in order inside one transaction; a recorded version above this list fails startup.
    static let migrations: [(version: Int, name: String)] = [(1, "001_snapshot"), (2, "002_accounts")]

    /// Bundled migrations use standalone SQL statements and full-line comments. Remove comments before
    /// splitting so punctuation in documentation can never become an executable statement fragment.
    static func migrationStatements(in sql: String) -> [String] {
        sql.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
            .joined(separator: "\n")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func migrate() async throws {
        var sources: [(version: Int, sql: String)] = []
        for migration in Self.migrations {
            guard
                let url = Bundle.module.url(
                    forResource: migration.name, withExtension: "sql", subdirectory: "Migrations")
            else {
                throw ConfigurationError("Missing embedded PostgreSQL migration.")
            }
            sources.append((migration.version, try String(contentsOf: url, encoding: .utf8)))
        }
        let latest = Self.migrations.map(\.version).max() ?? 0
        try await client.withConnection { connection in
            try await execute(connection, "BEGIN")
            do {
                try await execute(connection, "SELECT pg_advisory_xact_lock(727382019)")
                try await execute(
                    connection,
                    "CREATE TABLE IF NOT EXISTS reva_schema_migrations (version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
                )
                let rows = try await connection.query(
                    "SELECT COALESCE(MAX(version), 0) FROM reva_schema_migrations", logger: logger)
                var version = 0
                for try await value in rows.decode(Int.self) { version = value }
                guard version <= latest else {
                    throw ConfigurationError("Database schema is newer than this server.")
                }
                for source in sources where source.version > version {
                    for statement in Self.migrationStatements(in: source.sql) {
                        try await execute(connection, PostgresQuery(unsafeSQL: statement))
                    }
                    try await execute(
                        connection, "INSERT INTO reva_schema_migrations (version) VALUES (\(source.version))")
                }
                try await execute(connection, "COMMIT")
            } catch {
                try? await execute(connection, "ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - Owner snapshot reads, compare-and-swap writes, and tombstones
    public func getState(owner: String) async throws -> StateEnvelope {
        let rows = try await client.query(
            "SELECT revision, snapshot::text FROM reva_owner_state WHERE owner_id = \(owner)", logger: logger)
        for try await (revision, json) in rows.decode((Int, String?).self) {
            guard let json else { throw StoreError.missing(revision) }
            return StateEnvelope(
                revision: revision, snapshot: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        }
        throw StoreError.missing(0)
    }

    public func putState(owner: String, baseRevision: Int, snapshot: JSONValue) async throws -> Int {
        try Validation.snapshot(snapshot)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        return try await ownerTransaction(owner) { connection, current in
            guard current == baseRevision else { throw StoreError.conflict(current) }
            guard current < Int.max else { throw StoreError.corrupt }
            let next = current + 1
            try await execute(
                connection,
                "UPDATE reva_owner_state SET revision = \(next), snapshot = \(json)::jsonb, updated_at = now() WHERE owner_id = \(owner)"
            )
            try await audit(connection, owner: owner, action: "state.put", revision: next)
            return next
        }
    }

    public func deleteState(owner: String) async throws -> Int {
        try await ownerTransaction(owner) { connection, current in
            let rows = try await connection.query(
                "SELECT snapshot IS NOT NULL OR EXISTS (SELECT 1 FROM reva_attachments WHERE owner_id = \(owner)) FROM reva_owner_state WHERE owner_id = \(owner)",
                logger: logger)
            var hasContent = false
            for try await value in rows.decode(Bool.self) { hasContent = value }
            guard hasContent else { return current }
            guard current < Int.max else { throw StoreError.corrupt }
            let next = current + 1
            try await execute(connection, "DELETE FROM reva_attachments WHERE owner_id = \(owner)")
            try await execute(
                connection,
                "UPDATE reva_owner_state SET snapshot = NULL, revision = \(next), updated_at = now() WHERE owner_id = \(owner)"
            )
            try await audit(connection, owner: owner, action: "state.delete", revision: next)
            return next
        }
    }

    // MARK: - Original bytes and per-owner quota transactions
    public func putAttachment(owner: String, attachment: StoredAttachment) async throws {
        try Validation.attachment(attachment)
        try await ownerTransaction(owner) { connection, current in
            let rows = try await connection.query(
                "SELECT COALESCE(SUM(octet_length(bytes)), 0)::bigint, COUNT(*) FROM reva_attachments WHERE owner_id = \(owner) AND attachment_id != \(attachment.id)",
                logger: logger)
            for try await (size, count) in rows.decode((Int, Int).self) {
                guard size + attachment.data.count <= Validation.maxOwnerAttachmentBytes,
                    count < Validation.maxAttachmentCount
                else { throw StoreError.quota }
            }
            try await execute(
                connection,
                """
                INSERT INTO reva_attachments (owner_id, attachment_id, filename, content_type, bytes, updated_at)
                VALUES (\(owner), \(attachment.id), \(attachment.filename), \(attachment.contentType), \(attachment.data), \(attachment.updatedAt))
                ON CONFLICT (owner_id, attachment_id) DO UPDATE SET filename = EXCLUDED.filename,
                content_type = EXCLUDED.content_type, bytes = EXCLUDED.bytes, updated_at = EXCLUDED.updated_at
                """)
            try await audit(connection, owner: owner, action: "attachment.put", revision: current)
        }
    }

    public func getAttachment(owner: String, id: String) async throws -> StoredAttachment {
        let rows = try await client.query(
            "SELECT filename, content_type, bytes, updated_at FROM reva_attachments WHERE owner_id = \(owner) AND attachment_id = \(id)",
            logger: logger)
        for try await (filename, type, data, date) in rows.decode((String, String, Data, Date).self) {
            return StoredAttachment(
                id: id, filename: filename, contentType: type, data: data, updatedAt: date)
        }
        throw StoreError.attachmentMissing
    }

    public func deleteAttachment(owner: String, id: String) async throws {
        try await ownerTransaction(owner) { connection, current in
            let rows = try await connection.query(
                "DELETE FROM reva_attachments WHERE owner_id = \(owner) AND attachment_id = \(id) RETURNING attachment_id",
                logger: logger)
            var deleted = false
            for try await _ in rows { deleted = true }
            if deleted {
                try await audit(connection, owner: owner, action: "attachment.delete", revision: current)
            }
        }
    }

    // MARK: - Users
    /// Emails arrive normalized; the unique index plus DO NOTHING turns a duplicate into AccountError.emailTaken.
    public func createUser(_ user: UserRecord) async throws {
        guard Validation.safeID(user.id) else { throw StoreError.corrupt }
        let email = user.email.lowercased()
        let rows = try await client.query(
            """
            INSERT INTO reva_users (user_id, email, display_name, password_hash, password_updated_at, created_at)
            VALUES (\(user.id), \(email), \(user.name), \(user.passwordHash), \(user.passwordUpdatedAt), \(user.createdAt))
            ON CONFLICT (email) DO NOTHING RETURNING user_id
            """, logger: logger)
        var inserted = false
        for try await _ in rows { inserted = true }
        guard inserted else { throw AccountError.emailTaken }
    }

    public func user(email: String) async throws -> UserRecord? {
        let rows = try await client.query(
            "SELECT user_id, email, display_name, password_hash, created_at, password_updated_at FROM reva_users WHERE email = \(email.lowercased())",
            logger: logger)
        for try await row in rows.decode(UserRow.self) { return Self.user(from: row) }
        return nil
    }

    public func user(id: String) async throws -> UserRecord? {
        let rows = try await client.query(
            "SELECT user_id, email, display_name, password_hash, created_at, password_updated_at FROM reva_users WHERE user_id = \(id)",
            logger: logger)
        for try await row in rows.decode(UserRow.self) { return Self.user(from: row) }
        return nil
    }

    public func updatePassword(userID: String, hash: String, at date: Date) async throws {
        let rows = try await client.query(
            "UPDATE reva_users SET password_hash = \(hash), password_updated_at = \(date) WHERE user_id = \(userID) RETURNING user_id",
            logger: logger)
        var updated = false
        for try await _ in rows { updated = true }
        guard updated else { throw AccountError.userMissing }
    }

    /// Password verification, replacement and revocation share the user lock used to issue sessions.
    public func changePassword(
        userID: String, verifiedPasswordHash: String, newHash: String, keepingSessionID: UUID,
        at date: Date
    ) async throws -> Bool {
        try await transaction { connection in
            guard try await lockedPassword(userID: userID, connection: connection) == verifiedPasswordHash
            else { return false }
            let sessions = try await connection.query(
                """
                SELECT session_id FROM reva_sessions
                WHERE session_id = \(keepingSessionID) AND user_id = \(userID)
                  AND revoked_at IS NULL AND expires_at > clock_timestamp()
                FOR UPDATE
                """, logger: logger)
            var presentingSessionIsLive = false
            for try await _ in sessions { presentingSessionIsLive = true }
            guard presentingSessionIsLive else { return false }
            try await execute(
                connection,
                "UPDATE reva_users SET password_hash = \(newHash), password_updated_at = \(date) WHERE user_id = \(userID)"
            )
            try await execute(
                connection,
                "UPDATE reva_sessions SET revoked_at = \(date) WHERE user_id = \(userID) AND revoked_at IS NULL AND session_id != \(keepingSessionID)"
            )
            return true
        }
    }

    /// One transaction removes the owner aggregate (attachments and audit cascade) and the user (sessions cascade).
    public func deleteUser(id: String) async throws {
        guard Validation.safeID(id) else { throw StoreError.corrupt }
        try await transaction { connection in
            try await execute(connection, "DELETE FROM reva_owner_state WHERE owner_id = \(id)")
            let rows = try await connection.query(
                "DELETE FROM reva_users WHERE user_id = \(id) RETURNING user_id", logger: logger)
            var deleted = false
            for try await _ in rows { deleted = true }
            guard deleted else { throw AccountError.userMissing }
        }
    }

    // MARK: - Sessions
    /// The user row lock serializes concurrent log-ins so the 20-live-session cap holds.
    public func createSession(_ session: SessionRecord) async throws {
        guard try await insertSession(session, verifiedPasswordHash: nil) else {
            throw AccountError.userMissing
        }
    }

    public func createSession(_ session: SessionRecord, verifiedPasswordHash: String) async throws -> Bool {
        try await insertSession(session, verifiedPasswordHash: verifiedPasswordHash)
    }

    private func insertSession(_ session: SessionRecord, verifiedPasswordHash: String?) async throws -> Bool {
        try await transaction { connection in
            guard let currentHash = try await lockedPassword(userID: session.userID, connection: connection)
            else { return false }
            if let verifiedPasswordHash, currentHash != verifiedPasswordHash { return false }
            let keep = AccountPolicy.maximumLiveSessions - 1
            try await execute(
                connection,
                """
                UPDATE reva_sessions SET revoked_at = \(session.createdAt) WHERE session_id IN (
                    SELECT session_id FROM reva_sessions
                    WHERE user_id = \(session.userID) AND revoked_at IS NULL AND expires_at > \(session.createdAt)
                    ORDER BY created_at DESC, session_id DESC OFFSET \(keep))
                """)
            try await execute(
                connection,
                """
                INSERT INTO reva_sessions (session_id, token_hash, user_id, label, created_at, last_used_at, expires_at, revoked_at)
                VALUES (\(session.id), \(session.tokenHash), \(session.userID), \(session.label), \(session.createdAt), \(session.lastUsedAt), \(session.expiresAt), \(session.revokedAt))
                """)
            return true
        }
    }

    private func lockedPassword(userID: String, connection: PostgresConnection) async throws -> String? {
        let rows = try await connection.query(
            "SELECT password_hash FROM reva_users WHERE user_id = \(userID) FOR UPDATE", logger: logger)
        var passwordHash: String?
        for try await hash in rows.decode(String.self) { passwordHash = hash }
        return passwordHash
    }

    public func session(tokenHash: String) async throws -> (SessionRecord, UserRecord)? {
        let rows = try await client.query(
            """
            SELECT s.session_id, s.token_hash, s.user_id, s.label, s.created_at, s.last_used_at, s.expires_at, s.revoked_at,
                   u.user_id, u.email, u.display_name, u.password_hash, u.created_at, u.password_updated_at
            FROM reva_sessions s JOIN reva_users u ON u.user_id = s.user_id
            WHERE s.token_hash = \(tokenHash) AND s.revoked_at IS NULL AND s.expires_at > now()
            """, logger: logger)
        for try await (
            sessionID, hash, userID, label, created, used, expires, revoked, id, email, name, password,
            userCreated, passwordUpdated
        ) in rows.decode(
            (
                UUID, String, String, String, Date, Date, Date, Date?, String, String, String, String, Date,
                Date
            )
            .self)
        {
            return (
                SessionRecord(
                    id: sessionID, tokenHash: hash, userID: userID, label: label, createdAt: created,
                    lastUsedAt: used, expiresAt: expires, revokedAt: revoked),
                Self.user(from: (id, email, name, password, userCreated, passwordUpdated))
            )
        }
        return nil
    }

    public func touchSession(id: UUID, at date: Date) async throws {
        let rows = try await client.query(
            "UPDATE reva_sessions SET last_used_at = \(date) WHERE session_id = \(id) RETURNING session_id",
            logger: logger)
        var updated = false
        for try await _ in rows { updated = true }
        guard updated else { throw AccountError.sessionMissing }
    }

    public func revokeSession(id: UUID) async throws {
        let rows = try await client.query(
            "UPDATE reva_sessions SET revoked_at = COALESCE(revoked_at, now()) WHERE session_id = \(id) RETURNING session_id",
            logger: logger)
        var updated = false
        for try await _ in rows { updated = true }
        guard updated else { throw AccountError.sessionMissing }
    }

    public func revokeSessions(userID: String, except: UUID?) async throws {
        if let except {
            try await execute(
                client,
                "UPDATE reva_sessions SET revoked_at = now() WHERE user_id = \(userID) AND revoked_at IS NULL AND session_id != \(except)"
            )
        } else {
            try await execute(
                client,
                "UPDATE reva_sessions SET revoked_at = now() WHERE user_id = \(userID) AND revoked_at IS NULL"
            )
        }
    }

    // MARK: - Row decoding for users
    private typealias UserRow = (String, String, String, String, Date, Date)

    private static func user(from row: UserRow) -> UserRecord {
        UserRecord(
            id: row.0, email: row.1, name: row.2, passwordHash: row.3, createdAt: row.4,
            passwordUpdatedAt: row.5)
    }

    // MARK: - Generic transaction with rollback on failure
    private func transaction<T: Sendable>(_ operation: @Sendable (PostgresConnection) async throws -> T)
        async throws -> T
    {
        try await client.withConnection { connection in
            try await execute(connection, "BEGIN")
            do {
                try await execute(connection, "SET LOCAL statement_timeout = '15s'")
                let result = try await operation(connection)
                try await execute(connection, "COMMIT")
                return result
            } catch {
                try? await execute(connection, "ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - Serialize owner mutations with rollback on failure
    // The row lock covers revision/quota checks and their corresponding writes in the same transaction.
    private func ownerTransaction<T: Sendable>(
        _ owner: String, _ operation: @Sendable (PostgresConnection, Int) async throws -> T
    ) async throws -> T {
        guard Validation.safeID(owner) else { throw StoreError.corrupt }
        return try await client.withConnection { connection in
            try await execute(connection, "BEGIN")
            do {
                try await execute(connection, "SET LOCAL statement_timeout = '15s'")
                try await execute(
                    connection,
                    "INSERT INTO reva_owner_state (owner_id) VALUES (\(owner)) ON CONFLICT DO NOTHING")
                let rows = try await connection.query(
                    "SELECT revision FROM reva_owner_state WHERE owner_id = \(owner) FOR UPDATE",
                    logger: logger)
                var current: Int?
                for try await value in rows.decode(Int.self) { current = value }
                guard let current else { throw StoreError.corrupt }
                let result = try await operation(connection, current)
                try await execute(connection, "COMMIT")
                return result
            } catch {
                try? await execute(connection, "ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - Drain queries and retain bounded metadata-only audit history
    private func execute(_ connection: PostgresConnection, _ query: PostgresQuery) async throws {
        let rows = try await connection.query(query, logger: logger)
        for try await _ in rows {}
    }

    private func execute(_ client: PostgresClient, _ query: PostgresQuery) async throws {
        let rows = try await client.query(query, logger: logger)
        for try await _ in rows {}
    }

    private func audit(_ connection: PostgresConnection, owner: String, action: String, revision: Int)
        async throws
    {
        try await execute(
            connection,
            "INSERT INTO reva_mutations (owner_id, mutation_id, action, revision) VALUES (\(owner), \(UUID()), \(action), \(revision))"
        )
        // Bound metadata retention consistently with the file adapter; no patient text in audit rows.
        try await execute(
            connection,
            "DELETE FROM reva_mutations WHERE owner_id = \(owner) AND mutation_id NOT IN (SELECT mutation_id FROM reva_mutations WHERE owner_id = \(owner) ORDER BY created_at DESC, mutation_id DESC LIMIT 128)"
        )
    }
}
