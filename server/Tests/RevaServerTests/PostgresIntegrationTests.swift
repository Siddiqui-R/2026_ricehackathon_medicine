// Purpose: Opt in to real PostgreSQL migration, revision, ownership, attachment, tombstone, and account verification.
// Inputs: REVA_TEST_DATABASE_URL for a dedicated test database and optional insecure-loopback test permission.
// Outputs: Swift Testing assertions, or skipped tests when the explicit database URL is absent.
// Side effects: Applies schema and writes random synthetic owners/users in the supplied database, then cleans them on success.
// Cleanup boundary: A failure may leave those synthetic rows for inspection. The database client is always cancelled.

import Foundation
import Testing
import Vapor

@testable import RevaServer

// MARK: - Explicit opt-in to a dedicated real database
private func makeIntegrationStore() throws -> PostgresStore {
    let url = try #require(ProcessInfo.processInfo.environment["REVA_TEST_DATABASE_URL"])
    var environment = [
        "REVA_STORAGE": "postgres", "DATABASE_URL": url,
        "REVA_TOKENS": "{\"integration-test-token-123456789\":\"test-owner\"}",
    ]
    if ProcessInfo.processInfo.environment["REVA_ALLOW_INSECURE_LOCAL_POSTGRES"] == "true" {
        environment["REVA_ALLOW_INSECURE_LOCAL_POSTGRES"] = "true"
    }
    let configuration = try ServerConfiguration(environment: environment)
    return PostgresStore(configuration: try #require(configuration.postgres))
}

@Suite("PostgreSQL integration — dedicated database only")
struct PostgresIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REVA_TEST_DATABASE_URL"] != nil))
    func realDatabaseRoundtripAndMigrations() async throws {
        let store = try makeIntegrationStore()
        let task = Task { await store.client.run() }
        do {
            // MARK: - Migration replay and isolated synthetic owner lifecycle
            try await withDatabaseDeadline {
                try await store.migrate()
                try await store.migrate()
                let owner = "integration-" + UUID().uuidString
                let snapshot: JSONValue = .object([
                    "schemaVersion": .integer(1),
                    "profile": .object(["name": .string("Synthetic integration patient")]),
                    "records": .array([]), "visits": .array([]), "bookings": .array([]),
                    "recordings": .array([]),
                ])
                #expect(try await store.putState(owner: owner, baseRevision: 0, snapshot: snapshot) == 1)
                #expect(try await store.getState(owner: owner).snapshot == snapshot)
                await #expect(throws: StoreError.self) {
                    try await store.putState(owner: owner, baseRevision: 0, snapshot: snapshot)
                }
                await #expect(throws: StoreError.self) { try await store.getState(owner: owner + "x") }
                let attachment = StoredAttachment(
                    id: "source", filename: "sample.pdf", contentType: "application/pdf",
                    data: Data([0, 255, 128]), updatedAt: Date(timeIntervalSince1970: 10))
                try await store.putAttachment(owner: owner, attachment: attachment)
                #expect(try await store.getAttachment(owner: owner, id: "source") == attachment)
                await #expect(throws: StoreError.self) {
                    try await store.getAttachment(owner: owner + "x", id: "source")
                }
                #expect(try await store.deleteState(owner: owner) == 2)
                await #expect(throws: StoreError.self) {
                    try await store.getAttachment(owner: owner, id: "source")
                }
                #expect(try await store.deleteState(owner: owner) == 2)
                // Clean only this random synthetic owner, including its tombstone and audit.
                let rows = try await store.client.query(
                    "DELETE FROM reva_owner_state WHERE owner_id = \(owner)")
                for try await _ in rows {}
            }
            // MARK: - Always stop the database connection runner
            task.cancel()
            await task.value
        } catch {
            task.cancel()
            await task.value
            throw error
        }
    }

    // MARK: - Accounts, sessions, the 20-session cap, and cascading deletion on a real database
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REVA_TEST_DATABASE_URL"] != nil))
    func realDatabaseAccountsAndSessions() async throws {
        let store = try makeIntegrationStore()
        let task = Task { await store.client.run() }
        let userID = AccountIdentifiers.userID()
        let email = "integration-" + UUID().uuidString.lowercased() + "@example.test"
        func cleanup() async {
            // Rows cascade from reva_users and reva_owner_state; a failure may leave them for inspection.
            do {
                let rows = try await store.client.query("DELETE FROM reva_users WHERE user_id = \(userID)")
                for try await _ in rows {}
                let owners = try await store.client.query(
                    "DELETE FROM reva_owner_state WHERE owner_id = \(userID)")
                for try await _ in owners {}
            } catch {}
        }
        do {
            try await withDatabaseDeadline {
                try await store.migrate()
                let now = Date()
                let user = UserRecord(
                    id: userID, email: email, name: "Integration Person",
                    passwordHash: try Bcrypt.hash("integration-only-secret", cost: 4), createdAt: now,
                    passwordUpdatedAt: now)
                try await store.createUser(user)
                await #expect(throws: AccountError.self) {
                    try await store.createUser(
                        UserRecord(
                            id: AccountIdentifiers.userID(), email: email.uppercased().lowercased(),
                            name: "Twin", passwordHash: user.passwordHash, createdAt: now,
                            passwordUpdatedAt: now))
                }
                let byEmail = try #require(try await store.user(email: email.uppercased()))
                #expect(byEmail.id == userID && byEmail.name == "Integration Person")
                #expect(try await store.user(id: userID)?.passwordHash == user.passwordHash)
                // Session lookup, touch, and revocation.
                let token = SessionToken.generate()
                let session = SessionRecord(
                    id: UUID(), tokenHash: SessionToken.hash(token), userID: userID, label: "integration",
                    createdAt: now, lastUsedAt: now.addingTimeInterval(-600),
                    expiresAt: now.addingTimeInterval(3600),
                    revokedAt: nil)
                try await store.createSession(session)
                let found = try #require(try await store.session(tokenHash: SessionToken.hash(token)))
                #expect(found.0.id == session.id && found.1.id == userID && found.0.revokedAt == nil)
                try await store.touchSession(id: session.id, at: now)
                let touched = try #require(try await store.session(tokenHash: SessionToken.hash(token)))
                #expect(abs(touched.0.lastUsedAt.timeIntervalSince(now)) < 1)
                try await store.revokeSession(id: session.id)
                #expect(try await store.session(tokenHash: SessionToken.hash(token)) == nil)
                await #expect(throws: AccountError.self) { try await store.touchSession(id: UUID(), at: now) }
                // The 20-live-session cap revokes the oldest session.
                var tokens: [String] = []
                for index in 0..<21 {
                    let extra = SessionToken.generate()
                    tokens.append(extra)
                    try await store.createSession(
                        SessionRecord(
                            id: UUID(), tokenHash: SessionToken.hash(extra), userID: userID, label: "",
                            createdAt: now.addingTimeInterval(Double(index)), lastUsedAt: now,
                            expiresAt: now.addingTimeInterval(3600), revokedAt: nil))
                }
                #expect(try await store.session(tokenHash: SessionToken.hash(tokens[0])) == nil)
                #expect(try await store.session(tokenHash: SessionToken.hash(tokens[1])) != nil)
                let live = try await store.client.query(
                    "SELECT COUNT(*)::bigint FROM reva_sessions WHERE user_id = \(userID) AND revoked_at IS NULL"
                )
                for try await count in live.decode(Int.self) { #expect(count == 20) }
                try await store.revokeSessions(userID: userID, except: nil)
                #expect(try await store.session(tokenHash: SessionToken.hash(tokens[20])) == nil)
                // Password update and cascading account deletion including the owner snapshot.
                try await store.updatePassword(
                    userID: userID, hash: try Bcrypt.hash("another-secret", cost: 4), at: now)
                #expect(try await store.user(id: userID)?.passwordHash != user.passwordHash)
                let snapshot: JSONValue = .object([
                    "schemaVersion": .integer(1), "profile": .object(["name": .string("Integration")]),
                    "records": .array([]), "visits": .array([]), "bookings": .array([]),
                    "recordings": .array([]),
                ])
                #expect(try await store.putState(owner: userID, baseRevision: 0, snapshot: snapshot) == 1)
                try await store.deleteUser(id: userID)
                #expect(try await store.user(id: userID) == nil)
                await #expect(throws: StoreError.self) { try await store.getState(owner: userID) }
                let remaining = try await store.client.query(
                    "SELECT COUNT(*)::bigint FROM reva_sessions WHERE user_id = \(userID)")
                for try await count in remaining.decode(Int.self) { #expect(count == 0) }
                await #expect(throws: AccountError.self) { try await store.deleteUser(id: userID) }
            }
            await cleanup()
            task.cancel()
            await task.value
        } catch {
            await cleanup()
            task.cancel()
            await task.value
            throw error
        }
    }
}
