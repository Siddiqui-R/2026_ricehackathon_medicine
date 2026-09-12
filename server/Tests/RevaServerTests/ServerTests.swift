// Purpose: Exercise HTTP ownership, revision conflicts, binary preservation, local durability, and resource limits.
// Inputs: Synthetic snapshots/bytes, private test tokens, and temporary actor-backed local storage.
// Outputs: Swift Testing assertions on the real route/store contract, including negative and concurrent cases.
// Side effects: Writes temporary owner files and launches VaporTesting applications with cleanup. No paid provider calls.

import Foundation
import Testing
import VaporTesting

@testable import RevaServer

// MARK: - Synthetic identities, data, and temporary application lifetime
private let tokenA = "test-owner-a-token-123456789"
private let tokenB = "test-owner-b-token-123456789"
private let sample: JSONValue = .object([
    "schemaVersion": .integer(1),
    "profile": .object(["id": .string("owner-b"), "name": .string("Synthetic patient")]),
    "records": .array([.object(["id": .string("record-1"), "text": .string("Synthetic source")])]),
    "visits": .array([]), "bookings": .array([]), "recordings": .array([]),
])

private func withServer(_ test: (Application, LocalFileStore, URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "reva-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = try ServerConfiguration(environment: [
        "REVA_TOKENS": "{\"\(tokenA)\":\"owner-a\",\"\(tokenB)\":\"owner-b\"}"
    ])
    let store = try LocalFileStore(directory: directory)
    try await withApp(configure: { app in configure(app, configuration: configuration, store: store) }) {
        app in
        try await test(app, store, directory)
    }
}

private func headers(_ token: String = tokenA) -> HTTPHeaders { ["Authorization": "Bearer \(token)"] }

// MARK: - HTTP authentication and original-byte contracts
@Suite("Reva HTTP and persistence")
struct ServerTests {
    @Test func authOwnershipAndRevisionConflicts() async throws {
        try await withServer { app, _, _ async throws in
            try await app.testing().test(.GET, "health") { response async throws in
                #expect(response.status == .ok)
                #expect(try response.content.decode(HealthResponse.self).storage == "local")
                #expect(response.headers.first(name: .cacheControl) == "no-store")
            }
            for route in ["v1/state", "v1/attachments/source-1"] {
                try await app.testing().test(.GET, route) { response async in
                    #expect(response.status == .unauthorized)
                }
            }
            try await app.testing().test(.GET, "v1/state", headers: headers("invalid")) { response async in
                #expect(response.status == .unauthorized)
            }
            try await app.testing().test(
                .PUT, "v1/state", headers: headers(),
                beforeRequest: { request in
                    try request.content.encode(StateWrite(baseRevision: 0, snapshot: sample))
                },
                afterResponse: { response async throws in
                    #expect(response.status == .ok)
                    #expect(try response.content.decode(RevisionResponse.self).revision == 1)
                })
            try await app.testing().test(.GET, "v1/state", headers: headers(tokenB)) { response async in
                #expect(response.status == .notFound)
                #expect(response.headers.first(name: "X-State-Revision") == "0")
            }
            try await app.testing().test(.GET, "v1/state", headers: headers()) { response async throws in
                #expect(try response.content.decode(StateEnvelope.self).snapshot == sample)
            }
            try await app.testing().test(
                .PUT, "v1/state", headers: headers(),
                beforeRequest: { request in
                    try request.content.encode(StateWrite(baseRevision: 0, snapshot: sample))
                },
                afterResponse: { response async in
                    #expect(response.status == .conflict)
                    #expect(response.headers.first(name: "X-State-Revision") == "1")
                })
            try await app.testing().test(.DELETE, "v1/state", headers: headers(tokenB)) { response async in
                #expect(response.status == .ok)
            }
            try await app.testing().test(.GET, "v1/state", headers: headers()) { response async in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func attachmentRoundtripAndDeletion() async throws {
        try await withServer { app, _, _ async throws in
            let bytes = Data([0, 1, 2, 255, 13, 10, 128])
            var uploadHeaders = headers()
            uploadHeaders.replaceOrAdd(name: .contentType, value: "application/pdf")
            uploadHeaders.replaceOrAdd(name: "X-Filename", value: "Synthetic source.pdf")
            try await app.testing().test(
                .PUT, "v1/attachments/source-1", headers: uploadHeaders, body: ByteBuffer(data: bytes)
            ) { response async in
                #expect(response.status == .noContent)
            }
            try await app.testing().test(.GET, "v1/attachments/source-1", headers: headers()) {
                response async in
                #expect(response.status == .ok)
                #expect(Data(response.body.readableBytesView) == bytes)
                #expect(response.headers.first(name: "X-Filename") == "Synthetic source.pdf")
                #expect(response.headers.first(name: .contentType) == "application/pdf")
            }
            try await app.testing().test(.GET, "v1/attachments/source-1", headers: headers(tokenB)) {
                response async in #expect(response.status == .notFound)
            }
            try await app.testing().test(.DELETE, "v1/attachments/source-1", headers: headers(tokenB)) {
                response async in #expect(response.status == .noContent)
            }
            try await app.testing().test(.GET, "v1/attachments/source-1", headers: headers()) {
                response async in #expect(response.status == .ok)
            }
            try await app.testing().test(.DELETE, "v1/attachments/source-1", headers: headers()) {
                response async in #expect(response.status == .noContent)
            }
            try await app.testing().test(.GET, "v1/attachments/source-1", headers: headers()) {
                response async in #expect(response.status == .notFound)
            }
        }
    }

    // MARK: - Reject malformed requests before storage changes
    @Test func invalidPayloadsAndPathsAreRejected() async throws {
        try await withServer { app, _, _ async throws in
            try await app.testing().test(
                .PUT, "v1/state", headers: headers(),
                beforeRequest: { request in
                    try request.content.encode(
                        StateWrite(baseRevision: 0, snapshot: .object(["profile": .string("wrong")])))
                }, afterResponse: { response async in #expect(response.status == .badRequest) })
            try await app.testing().test(
                .PUT, "v1/state", headers: headers(), body: ByteBuffer(string: "garbage")
            ) { response async in
                #expect(response.status == .unsupportedMediaType)
            }
            let oversize: JSONValue = .object([
                "schemaVersion": .integer(1),
                "profile": .object([
                    "name": .string(String(repeating: "x", count: Validation.maxSnapshotBytes))
                ]), "records": .array([]), "visits": .array([]), "bookings": .array([]),
                "recordings": .array([]),
            ])
            try await app.testing().test(
                .PUT, "v1/state", headers: headers(),
                beforeRequest: { request in
                    try request.content.encode(StateWrite(baseRevision: 0, snapshot: oversize))
                }, afterResponse: { response async in #expect(response.status == .payloadTooLarge) })
            for (id, filename, type, expected) in [
                ("unsafe%2Fpath", "source.pdf", "application/pdf", HTTPStatus.badRequest),
                ("source-1", "../source.pdf", "application/pdf", .badRequest),
                ("source-1", "source.html", "text/html", .unsupportedMediaType),
            ] {
                var requestHeaders = headers()
                requestHeaders.replaceOrAdd(name: "X-Filename", value: filename)
                requestHeaders.replaceOrAdd(name: .contentType, value: type)
                try await app.testing().test(
                    .PUT, "v1/attachments/\(id)", headers: requestHeaders, body: ByteBuffer(string: "data")
                ) { response async in
                    #expect(response.status == expected)
                }
            }
            try await app.testing().test(.GET, "v1/state", headers: headers()) { response async in
                #expect(response.status == .notFound)
            }
        }
    }

    // MARK: - Deletion and restart durability
    @Test func deletionTombstonePreventsResurrection() async throws {
        try await withServer { app, store, _ async throws in
            #expect(try await store.putState(owner: "owner-a", baseRevision: 0, snapshot: sample) == 1)
            try await store.putAttachment(
                owner: "owner-a",
                attachment: .init(
                    id: "source", filename: "source.txt", contentType: "text/plain",
                    data: Data("fictional".utf8), updatedAt: Date()))
            try await app.testing().test(.DELETE, "v1/state", headers: headers()) { response async throws in
                #expect(try response.content.decode(RevisionResponse.self).revision == 2)
            }
            try await app.testing().test(.GET, "v1/state", headers: headers()) { response async in
                #expect(response.status == .notFound)
                #expect(response.headers.first(name: "X-State-Revision") == "2")
            }
            try await app.testing().test(.GET, "v1/attachments/source", headers: headers()) {
                response async in #expect(response.status == .notFound)
            }
            #expect(try await store.deleteState(owner: "owner-a") == 2)
            await #expect(throws: StoreError.self) {
                try await store.putState(owner: "owner-a", baseRevision: 1, snapshot: sample)
            }
            #expect(try await store.putState(owner: "owner-a", baseRevision: 2, snapshot: sample) == 3)
        }
    }

    @Test func persistenceSurvivesNewStoreAndCorruptionFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reva-restart-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attachment = StoredAttachment(
            id: "audio", filename: "synthetic.m4a", contentType: "audio/mp4", data: Data([0, 255, 128]),
            updatedAt: Date(timeIntervalSince1970: 10))
        func writeOriginal() async throws {
            let original = try LocalFileStore(directory: directory)
            #expect(try await original.putState(owner: "owner-a", baseRevision: 0, snapshot: sample) == 1)
            try await original.putAttachment(owner: "owner-a", attachment: attachment)
            #expect(throws: ConfigurationError.self) { try LocalFileStore(directory: directory) }
        }
        try await writeOriginal()
        let restarted = try LocalFileStore(directory: directory)
        #expect(try await restarted.getState(owner: "owner-a").snapshot == sample)
        #expect(try await restarted.getAttachment(owner: "owner-a", id: "audio") == attachment)
        try Data("broken persisted JSON".utf8).write(to: directory.appendingPathComponent("owner-a.json"))
        await #expect(throws: StoreError.self) { try await restarted.getState(owner: "owner-a") }
        await #expect(throws: StoreError.self) {
            try await restarted.putState(owner: "owner-a", baseRevision: 0, snapshot: sample)
        }
        #expect(
            try String(contentsOf: directory.appendingPathComponent("owner-a.json"), encoding: .utf8)
                == "broken persisted JSON")
    }

    // MARK: - Concurrent writers, configuration, and aggregate bounds
    @Test func simultaneousWritesHaveExactlyOneWinner() async throws {
        try await withServer { _, store, _ async throws in
            let wins = await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<8 {
                    group.addTask {
                        (try? await store.putState(owner: "owner-a", baseRevision: 0, snapshot: sample))
                            != nil
                    }
                }
                var wins = 0
                for await won in group { if won { wins += 1 } }
                return wins
            }
            #expect(wins == 1)
            #expect(try await store.getState(owner: "owner-a").revision == 1)
        }
    }

    @Test func explicitConfigurationFailsClosed() throws {
        #expect(try ServerConfiguration(environment: [:]).isDemo)
        #expect(throws: ConfigurationError.self) {
            try ServerConfiguration(environment: [:], arguments: ["serve", "--hostname", "0.0.0.0"])
        }
        // A non-loopback listener without REVA_TOKENS is accepted only while accounts are enabled.
        for environment in [
            ["REVA_STORAGE": "unknown"], ["REVA_STORAGE": "postgres"],
            ["DATABASE_URL": "postgres://not-used"], ["REVA_PORT": "0"],
            ["REVA_TOKENS": "{}"], ["REVA_TOKENS": "{\"short\":\"owner\"}"],
            ["REVA_HOST": "0.0.0.0", "REVA_ACCOUNTS": "disabled"],
        ] { #expect(throws: ConfigurationError.self) { try ServerConfiguration(environment: environment) } }
        let accountsOnly = try ServerConfiguration(environment: ["REVA_HOST": "0.0.0.0"])
        #expect(accountsOnly.tokens.isEmpty)
        #expect(!accountsOnly.isDemo)
        let tokens = "{\"\(tokenA)\":\"owner-a\"}"
        #expect(throws: ConfigurationError.self) {
            try ServerConfiguration(environment: [
                "REVA_STORAGE": "postgres", "REVA_TOKENS": tokens,
                "DATABASE_URL": "postgres://user:secret@db.example/reva?sslmode=disable",
            ])
        }
        let configured = try ServerConfiguration(environment: [
            "REVA_STORAGE": "postgres", "REVA_TOKENS": tokens,
            "DATABASE_URL": "postgres://user:secret@db.example/reva?sslmode=verify-full",
        ])
        #expect(configured.postgres != nil)
        #expect(!configured.isDemo)
    }

    @Test func attachmentSizeAndOwnerQuotaAreEnforced() async throws {
        try await withServer { app, store, _ async throws in
            var uploadHeaders = headers()
            uploadHeaders.replaceOrAdd(name: .contentType, value: "audio/mp4")
            uploadHeaders.replaceOrAdd(name: "X-Filename", value: "Synthetic.m4a")
            try await app.testing().test(
                .PUT, "v1/attachments/too-big", headers: uploadHeaders,
                body: ByteBuffer(repeating: 0, count: Validation.maxAttachmentBytes + 1)
            ) { response async in
                #expect(response.status == .payloadTooLarge)
            }
            try await app.testing().test(.PUT, "v1/attachments/empty", headers: uploadHeaders) {
                response async in
                #expect(response.status == .badRequest)
            }
            for index in 0..<Validation.maxAttachmentCount {
                try await store.putAttachment(
                    owner: "owner-a",
                    attachment: .init(
                        id: "file-\(index)", filename: "Synthetic.txt", contentType: "text/plain",
                        data: Data([1]), updatedAt: Date()))
            }
            await #expect(throws: StoreError.self) {
                try await store.putAttachment(
                    owner: "owner-a",
                    attachment: .init(
                        id: "over-quota", filename: "Synthetic.txt", contentType: "text/plain",
                        data: Data([1]), updatedAt: Date()))
            }
            // Replacing an existing attachment does not consume another slot.
            try await store.putAttachment(
                owner: "owner-a",
                attachment: .init(
                    id: "file-0", filename: "Synthetic.txt", contentType: "text/plain", data: Data([2]),
                    updatedAt: Date()))
            #expect(try await store.getAttachment(owner: "owner-a", id: "file-0").data == Data([2]))
        }
    }
}
