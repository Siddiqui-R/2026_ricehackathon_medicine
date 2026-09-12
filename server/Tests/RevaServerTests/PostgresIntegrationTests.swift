// Purpose: Opt in to real PostgreSQL migration, revision, ownership, attachment, and tombstone verification.
// Inputs: REVA_TEST_DATABASE_URL for a dedicated test database and optional insecure-loopback test permission.
// Outputs: Swift Testing assertions, or a skipped test when the explicit database URL is absent.
// Side effects: Applies schema and writes a random synthetic owner in the supplied database, then cleans that owner on success.
// Cleanup boundary: A failure may leave that synthetic owner for inspection. The database client is always cancelled.

import Foundation
import Testing

@testable import RevaServer

// MARK: - Explicit opt-in to a dedicated real database
@Suite("PostgreSQL integration — dedicated database only")
struct PostgresIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REVA_TEST_DATABASE_URL"] != nil))
    func realDatabaseRoundtripAndMigrations() async throws {
        let url = try #require(ProcessInfo.processInfo.environment["REVA_TEST_DATABASE_URL"])
        var environment = [
            "REVA_STORAGE": "postgres", "DATABASE_URL": url,
            "REVA_TOKENS": "{\"integration-test-token-123456789\":\"test-owner\"}",
        ]
        if ProcessInfo.processInfo.environment["REVA_ALLOW_INSECURE_LOCAL_POSTGRES"] == "true" {
            environment["REVA_ALLOW_INSECURE_LOCAL_POSTGRES"] = "true"
        }
        let configuration = try ServerConfiguration(environment: environment)
        let store = PostgresStore(configuration: try #require(configuration.postgres))
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
}
