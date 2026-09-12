// Purpose: Guard SQL migration execution and account-registry compatibility with existing local owner data.
// Inputs: Checked-in migration SQL and synthetic owner/account files in isolated temporary directories.
// Outputs: Regression assertions for comment handling, safe registry relocation, and fail-closed corruption.
// Side effects: Writes and removes only test-owned temporary directories. No database or provider calls.

import Foundation
import Testing

@testable import RevaServer

// MARK: - Migration and local filename compatibility
@Suite("Persistence compatibility")
struct PersistenceCompatibilityTests {
    @Test func migrationCommentsCannotBecomeSQL() throws {
        let source = """
            -- Description; punctuation must remain a comment.
            CREATE TABLE example (id INTEGER);
              -- Another comment; before the index.
            CREATE INDEX example_id ON example(id);
            """
        #expect(
            PostgresStore.migrationStatements(in: source) == [
                "CREATE TABLE example (id INTEGER)", "CREATE INDEX example_id ON example(id)",
            ])
        let server = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for (index, migration) in PostgresStore.migrations.enumerated() {
            let file = server.appendingPathComponent("Sources/RevaServer/Migrations/\(migration.name).sql")
            let statements = PostgresStore.migrationStatements(
                in: try String(contentsOf: file, encoding: .utf8))
            #expect(statements.count == [4, 3][index])
            #expect(statements.allSatisfy { $0.hasPrefix("CREATE ") })
        }
    }

    @Test func staticAccountsOwnerAndRegistryCoexist() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFileStore(directory: directory)
        let snapshot = sampleSnapshot()
        #expect(try await store.putState(owner: "accounts", baseRevision: 0, snapshot: snapshot) == 1)
        let original = try Data(contentsOf: directory.appendingPathComponent("accounts.json"))
        let user = sampleUser()
        try await store.createUser(user)
        #expect(try await store.user(id: user.id) == user)
        #expect(try await store.getState(owner: "accounts").snapshot == snapshot)
        #expect(try Data(contentsOf: directory.appendingPathComponent("accounts.json")) == original)
        #expect(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(".accounts.json").path))
    }

    @Test func legacyRegistryMovesWithSessionsAndFreesOwnerFilename() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFileStore(directory: directory)
        let user = sampleUser()
        let token = SessionToken.generate()
        let now = Date()
        let session = SessionRecord(
            id: UUID(), tokenHash: SessionToken.hash(token), userID: user.id, label: "Test",
            createdAt: now, lastUsedAt: now, expiresAt: now.addingTimeInterval(3600), revokedAt: nil)
        let legacy = directory.appendingPathComponent("accounts.json")
        let data = try JSONEncoder().encode(AccountsDocument(users: [user], sessions: [session]))
        try data.write(to: legacy)
        // Accessing the old static-owner name first must also migrate a registry safely.
        let snapshot = sampleSnapshot()
        #expect(try await store.putState(owner: "accounts", baseRevision: 0, snapshot: snapshot) == 1)
        #expect(try await store.user(id: user.id) == user)
        let found = try await store.session(tokenHash: SessionToken.hash(token))
        #expect(found?.0 == session)
        let target = directory.appendingPathComponent(".accounts.json")
        #expect(try Data(contentsOf: target) == data)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect(try await store.getState(owner: "accounts").snapshot == snapshot)
    }

    @Test func malformedOrAmbiguousLegacyRegistryIsNeverOverwritten() async throws {
        for value in [
            #"{"formatVersion":1,"users":"broken","sessions":[]}"#,
            #"{"formatVersion":1,"users":[],"sessions":[],"revision":0,"attachments":{},"audit":[]}"#,
            "broken JSON",
        ] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try LocalFileStore(directory: directory)
            let legacy = directory.appendingPathComponent("accounts.json")
            try Data(value.utf8).write(to: legacy)
            await #expect(throws: StoreError.self) { try await store.createUser(sampleUser()) }
            #expect(try String(contentsOf: legacy, encoding: .utf8) == value)
            #expect(
                !FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(".accounts.json").path))
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("reva-persistence-\(UUID())")
    }

    private func sampleUser() -> UserRecord {
        let now = Date()
        return UserRecord(
            id: "u_0123456789abcdef01234567", email: "synthetic@example.com", name: "Synthetic",
            passwordHash: "$2b$04$synthetic-persistence-only", createdAt: now, passwordUpdatedAt: now)
    }

    private func sampleSnapshot() -> JSONValue {
        .object([
            "schemaVersion": .integer(1), "profile": .object(["id": .string("accounts")]),
            "records": .array([]), "visits": .array([]), "bookings": .array([]), "recordings": .array([]),
        ])
    }
}
