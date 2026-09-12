import Foundation
import PostgresNIO
import Vapor

public struct PostgresStore: RevaStore {
    public let client: PostgresClient
    private let logger = Logger(label: "reva.postgres")

    public init(configuration: PostgresClient.Configuration) { client = PostgresClient(configuration: configuration) }

    public func health() async throws {
        let rows = try await client.query("SELECT 1", logger: logger)
        for try await _ in rows {}
    }

    /// Migration source contains only checked-in SQL, never request data.
    public func migrate() async throws {
        guard let url = Bundle.module.url(forResource: "001_snapshot", withExtension: "sql", subdirectory: "Migrations") else {
            throw ConfigurationError("Missing embedded PostgreSQL migration.")
        }
        let sql = try String(contentsOf: url, encoding: .utf8)
        try await client.withConnection { connection in
            try await execute(connection, "BEGIN")
            do {
                try await execute(connection, "SELECT pg_advisory_xact_lock(727382019)")
                try await execute(connection, "CREATE TABLE IF NOT EXISTS reva_schema_migrations (version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())")
                let rows = try await connection.query("SELECT COALESCE(MAX(version), 0) FROM reva_schema_migrations", logger: logger)
                var version = 0
                for try await value in rows.decode(Int.self) { version = value }
                guard version <= 1 else { throw ConfigurationError("Database schema is newer than this server.") }
                if version == 0 {
                    for statement in sql.split(separator: ";") {
                        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { try await execute(connection, PostgresQuery(unsafeSQL: trimmed)) }
                    }
                    try await execute(connection, "INSERT INTO reva_schema_migrations (version) VALUES (1)")
                }
                try await execute(connection, "COMMIT")
            } catch {
                try? await execute(connection, "ROLLBACK")
                throw error
            }
        }
    }

    public func getState(owner: String) async throws -> StateEnvelope {
        let rows = try await client.query("SELECT revision, snapshot::text FROM reva_owner_state WHERE owner_id = \(owner)", logger: logger)
        for try await (revision, json) in rows.decode((Int, String?).self) {
            guard let json else { throw StoreError.missing(revision) }
            return StateEnvelope(revision: revision, snapshot: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
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
            try await execute(connection, "UPDATE reva_owner_state SET revision = \(next), snapshot = \(json)::jsonb, updated_at = now() WHERE owner_id = \(owner)")
            try await audit(connection, owner: owner, action: "state.put", revision: next)
            return next
        }
    }

    public func deleteState(owner: String) async throws -> Int {
        try await ownerTransaction(owner) { connection, current in
            let rows = try await connection.query("SELECT snapshot IS NOT NULL OR EXISTS (SELECT 1 FROM reva_attachments WHERE owner_id = \(owner)) FROM reva_owner_state WHERE owner_id = \(owner)", logger: logger)
            var hasContent = false
            for try await value in rows.decode(Bool.self) { hasContent = value }
            guard hasContent else { return current }
            guard current < Int.max else { throw StoreError.corrupt }
            let next = current + 1
            try await execute(connection, "DELETE FROM reva_attachments WHERE owner_id = \(owner)")
            try await execute(connection, "UPDATE reva_owner_state SET snapshot = NULL, revision = \(next), updated_at = now() WHERE owner_id = \(owner)")
            try await audit(connection, owner: owner, action: "state.delete", revision: next)
            return next
        }
    }

    public func putAttachment(owner: String, attachment: StoredAttachment) async throws {
        try Validation.attachment(attachment)
        try await ownerTransaction(owner) { connection, current in
            let rows = try await connection.query("SELECT COALESCE(SUM(octet_length(bytes)), 0)::bigint, COUNT(*) FROM reva_attachments WHERE owner_id = \(owner) AND attachment_id != \(attachment.id)", logger: logger)
            for try await (size, count) in rows.decode((Int, Int).self) {
                guard size + attachment.data.count <= Validation.maxOwnerAttachmentBytes, count < Validation.maxAttachmentCount else { throw StoreError.quota }
            }
            try await execute(connection, """
                INSERT INTO reva_attachments (owner_id, attachment_id, filename, content_type, bytes, updated_at)
                VALUES (\(owner), \(attachment.id), \(attachment.filename), \(attachment.contentType), \(attachment.data), \(attachment.updatedAt))
                ON CONFLICT (owner_id, attachment_id) DO UPDATE SET filename = EXCLUDED.filename,
                content_type = EXCLUDED.content_type, bytes = EXCLUDED.bytes, updated_at = EXCLUDED.updated_at
                """)
            try await audit(connection, owner: owner, action: "attachment.put", revision: current)
        }
    }

    public func getAttachment(owner: String, id: String) async throws -> StoredAttachment {
        let rows = try await client.query("SELECT filename, content_type, bytes, updated_at FROM reva_attachments WHERE owner_id = \(owner) AND attachment_id = \(id)", logger: logger)
        for try await (filename, type, data, date) in rows.decode((String, String, Data, Date).self) {
            return StoredAttachment(id: id, filename: filename, contentType: type, data: data, updatedAt: date)
        }
        throw StoreError.attachmentMissing
    }

    public func deleteAttachment(owner: String, id: String) async throws {
        try await ownerTransaction(owner) { connection, current in
            let rows = try await connection.query("DELETE FROM reva_attachments WHERE owner_id = \(owner) AND attachment_id = \(id) RETURNING attachment_id", logger: logger)
            var deleted = false
            for try await _ in rows { deleted = true }
            if deleted { try await audit(connection, owner: owner, action: "attachment.delete", revision: current) }
        }
    }

    private func ownerTransaction<T: Sendable>(_ owner: String, _ operation: @Sendable (PostgresConnection, Int) async throws -> T) async throws -> T {
        guard Validation.safeID(owner) else { throw StoreError.corrupt }
        return try await client.withConnection { connection in
            try await execute(connection, "BEGIN")
            do {
                try await execute(connection, "SET LOCAL statement_timeout = '15s'")
                try await execute(connection, "INSERT INTO reva_owner_state (owner_id) VALUES (\(owner)) ON CONFLICT DO NOTHING")
                let rows = try await connection.query("SELECT revision FROM reva_owner_state WHERE owner_id = \(owner) FOR UPDATE", logger: logger)
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

    private func execute(_ connection: PostgresConnection, _ query: PostgresQuery) async throws {
        let rows = try await connection.query(query, logger: logger)
        for try await _ in rows {}
    }

    private func audit(_ connection: PostgresConnection, owner: String, action: String, revision: Int) async throws {
        try await execute(connection, "INSERT INTO reva_mutations (owner_id, mutation_id, action, revision) VALUES (\(owner), \(UUID()), \(action), \(revision))")
        // Bound metadata retention consistently with the file adapter; no patient text in audit rows.
        try await execute(connection, "DELETE FROM reva_mutations WHERE owner_id = \(owner) AND mutation_id NOT IN (SELECT mutation_id FROM reva_mutations WHERE owner_id = \(owner) ORDER BY created_at DESC, mutation_id DESC LIMIT 128)")
    }
}
