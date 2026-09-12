// Purpose: Exercise production state and storage behavior using deterministic synthetic services.
// Inputs: The checked-in demo snapshot and real AppStore/LocalRepository sources.
// Outputs: Fatal assertion on regression, otherwise named passing checks.
// Side effects: Temporary files only; mock clients never contact a network.

import Foundation

#if !canImport(CryptoKit)
    // Equality-only signature double for Windows state checks; cryptography is verified by native tests.
    enum SHA256 {
        static func hash(data: Data) -> [UInt8] { Array(data) }
    }
#endif

#if canImport(Combine)
    import Combine
#else
    // Windows lacks Combine; observation delivery is outside this harness's scope.
    @propertyWrapper struct Published<Value> {
        var wrappedValue: Value
        init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }
    protocol ObservableObject {}
#endif

// MARK: - Deterministic service doubles
struct ServerState {
    var revision: Int
    var snapshot: AppSnapshot
}
enum ServerFailure: LocalizedError {
    case conflict
    case empty(Int)
    var errorDescription: String? { "Synthetic server failure" }
}
@MainActor struct ServerClient {
    static var remote: AppSnapshot!
    static var onHealth: (() async throws -> Void)?
    static var onPull: (() async throws -> Void)?
    static var onUpload: (() async throws -> Void)?
    static var onPush: (() async throws -> Void)?
    static var onAttachment: ((String) async throws -> Void)?
    static var uploads: [String] = []
    static var uploadedTypes: [String: String] = [:]
    static var uploadedBytes: [String: Data] = [:]
    static var pushes = 0
    static var lastPushed: AppSnapshot?
    static var files: [String: Data] = [:]
    init(baseURL: URL, token: String) throws {}
    func health() async throws -> String {
        try await Self.onHealth?()
        return "Connected"
    }
    func pull() async throws -> ServerState {
        try await Self.onPull?()
        return ServerState(revision: 2, snapshot: Self.remote)
    }
    func push(_ snapshot: AppSnapshot, revision: Int) async throws -> Int {
        Self.pushes += 1
        Self.lastPushed = snapshot
        try await Self.onPush?()
        return revision + 1
    }
    func uploadAttachment(id: String, filename: String, data: Data, type: String) async throws {
        try await Self.onUpload?()
        Self.uploads.append(id)
        Self.uploadedTypes[id] = type
        Self.uploadedBytes[id] = data
    }
    func attachment(id: String) async throws -> Data {
        try await Self.onAttachment?(id)
        guard let data = Self.files[id] else { throw RevaError.invalid("Missing synthetic attachment") }
        return data
    }
    static func attachmentID(for name: String) -> String { name }
    static func attachmentMetadataName(_ name: String) -> String { name }
    static func uploadContentType(_ type: String?) -> String { type ?? "application/octet-stream" }
    // The harness compiles audioContentType verbatim from production in a separate extension.
}
@MainActor struct ProviderClient {
    static var onStatus: (() async throws -> Void)?
    static var result = ProviderStatus(
        gemini: .init(configured: true, model: "synthetic"),
        transcription: .init(configured: false, model: "synthetic"),
        booking: .init(configured: false, model: "synthetic"), liveCallsEnabled: false)
    init(url: String, token: String) throws {}
    func status() async throws -> ProviderStatus {
        try await Self.onStatus?()
        return Self.result
    }
}

// MARK: - Behavioral checks
@main struct StateChecks {
    @MainActor static func main() async throws {
        let previousURL = UserDefaults.standard.object(forKey: "serverURL")
        defer { UserDefaults.standard.set(previousURL, forKey: "serverURL") }
        let fixture = try JSONDecoder().decode(
            AppSnapshot.self,
            from: Data(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        try fixture.validate()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(directory: root)
        try repository.save(fixture)
        // An injected repository keeps all checks away from the user's application data.
        let store = AppStore(repository: repository)
        assert(store.startupError == nil)
        let orderedRecords = store.records
        let orderedVisits = store.visits
        for record in fixture.records { assert(store.record(record.id) == record) }
        for visit in fixture.visits { assert(store.visit(visit.id) == visit) }
        assert(store.record("missing") == nil && store.visit("missing") == nil)
        assert(store.records == orderedRecords && store.visits == orderedVisits)
        print("PASS R5: identity lookup preserves values, missing IDs, and list ordering")
        try await checkSync(store, fixture: fixture)
        await checkDiscovery(store)
        try await checkUploads(store, fixture: fixture)
        try await checkPullFiles(store, fixture: fixture)
    }

    @MainActor static func checkSync(_ store: AppStore, fixture: AppSnapshot) async throws {
        var remote = fixture
        for i in remote.records.indices { remote.records[i].sourceFilename = nil }
        for i in remote.recordings.indices { remote.recordings[i].audioFilename = nil }
        ServerClient.remote = remote
        store.connectionURL = "http://localhost"
        store.connectionToken = "synthetic-token"
        ServerClient.onPull = {
            await Task.yield()
            try store.mutate { $0.profile.name = "New edit during pull" }
        }
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.snapshot?.profile.name == "New edit during pull", "R1: pull erased a newer edit")
        assert(!store.isSyncing)
        ServerClient.onPull = {
            await Task.yield()
            store.connectionURL = "http://127.0.0.1"
        }
        let before = store.snapshot
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.snapshot == before, "R1: old connection published state")
        assert(store.serverRevision == 0, "R1: old connection published a revision")
        ServerClient.onPull = nil
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.snapshot == remote && store.serverRevision == 2, "R1: normal pull broke")
        ServerClient.onHealth = {
            await Task.yield()
            store.connectionToken = "another-synthetic-token"
        }
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "probe")
        assert(store.serverStatus == "Not connected", "R1: old health result replaced new connection state")
        ServerClient.onHealth = nil
        ServerClient.onPush = {
            try store.mutate { $0.profile.name = "Edited during push" }
        }
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "push")
        assert(store.snapshot?.profile.name == "Edited during push")
        assert(ServerClient.lastPushed?.profile.name == remote.profile.name)
        assert(store.notice?.contains("Newer local edits") == true)
        ServerClient.onPush = {
            store.connectionToken = "third-synthetic-token"
        }
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "push")
        assert(store.serverRevision == 0, "R1: old push revision attached to a new connection")
        ServerClient.onPush = nil
        print("PASS R1: stale pull/probe/push results rejected; normal pull and edits during push preserved")
    }

    @MainActor static func checkDiscovery(_ store: AppStore) async {
        store.providerStatus = nil
        store.connectionURL = "http://localhost"
        ProviderClient.onStatus = {
            await Task.yield()
            store.connectionURL = "http://127.0.0.1"
        }
        await store.checkProviders()
        assert(store.providerStatus == nil, "R3: old connection published capabilities")
        ProviderClient.onStatus = nil
        await store.checkProviders()
        assert(store.providerStatus == ProviderClient.result, "R3: normal discovery broke")
        var calls = 0
        ProviderClient.onStatus = {
            calls += 1
            if calls == 1 {
                await store.checkProviders()
                throw RevaError.invalid("Older discovery failed after the latest succeeded")
            }
        }
        await store.checkProviders()
        assert(store.providerStatus == ProviderClient.result, "R3: older failure cleared latest result")
        ProviderClient.onStatus = nil
        print("PASS R3: stale discovery rejected; normal discovery succeeds")
    }

    @MainActor static func checkUploads(_ store: AppStore, fixture: AppSnapshot) async throws {
        var source = fixture
        let expectedTypes = [
            "shared.m4a": "audio/mp4", "shared.WEBM": "audio/webm", "shared.ogg": "audio/ogg",
        ]
        let names = expectedTypes.keys.sorted()
        // Each recording overrides conflicting record metadata, even when references are repeated.
        for i in source.records.indices {
            source.records[i].sourceFilename = names[i % names.count]
            source.records[i].mimeType = "application/pdf"
        }
        source.recordings = names.flatMap { name in
            (0..<2).map { _ in
                VisitRecording(
                    visitID: source.visits[0].id, title: "Synthetic", duration: 1,
                    audioFilename: name)
            }
        }
        for name in names {
            _ = try store.repository.storeAttachment(Data(name.utf8), filename: name)
        }
        store.snapshot = source
        ServerClient.uploads = []
        ServerClient.uploadedTypes = [:]
        ServerClient.uploadedBytes = [:]
        ServerClient.pushes = 0
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "push")
        assert(ServerClient.uploads == names, "R6: shared files must upload once each in stable order")
        assert(ServerClient.uploadedTypes == expectedTypes, "R6: audio MIME metadata precedence changed")
        for name in names {
            assert(ServerClient.uploadedBytes[name] == Data(name.utf8), "R6: original bytes changed")
        }
        assert(ServerClient.pushes == 1)
        ServerClient.onUpload = { throw RevaError.invalid("Synthetic upload failure") }
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "push")
        assert(ServerClient.pushes == 1, "R6: snapshot pushed after failed attachment")
        ServerClient.onUpload = nil
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "push")
        assert(ServerClient.pushes == 2, "R6: explicit retry failed")
        print("PASS R6: deduplicated M4A/WebM/Ogg uploads, original bytes, MIME precedence, failure/retry")
    }

    @MainActor static func checkPullFiles(_ store: AppStore, fixture: AppSnapshot) async throws {
        var original = fixture
        for i in original.records.indices { original.records[i].sourceFilename = "original.pdf" }
        original.recordings = []
        let bytes = Data("original evidence".utf8)
        _ = try store.repository.storeAttachment(bytes, filename: "original.pdf")
        try store.repository.save(original)
        store.snapshot = original
        ServerClient.remote = original
        ServerClient.files = ["original.pdf": Data("different evidence".utf8)]
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        let afterConflict = try Data(contentsOf: store.repository.attachment("original.pdf")!)
        assert(
            afterConflict == bytes,
            "R2: pull replaced an original under the same filename")
        assert(store.snapshot == original)
        // Identical existing bytes must still allow normal pulls.
        ServerClient.files = ["original.pdf": bytes]
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.serverRevision == 2)
        // A new source must be rolled back when the subsequent snapshot write fails.
        var remote = original
        remote.records[0].sourceFilename = "a-staged.pdf"
        remote.records[1].sourceFilename = "z-missing.pdf"
        ServerClient.remote = remote
        ServerClient.files["a-staged.pdf"] = Data("staged evidence".utf8)
        ServerClient.onAttachment = { name in
            if name == "z-missing.pdf" {
                assert(
                    store.repository.attachment("a-staged.pdf") != nil,
                    "R4: previous file should be staged before downloading the next")
            }
        }
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.snapshot == original)
        assert(
            store.repository.attachment("a-staged.pdf") == nil,
            "R2: failed download left a staged file")
        ServerClient.onAttachment = nil
        remote = original
        remote.records[0].sourceFilename = "new-source.pdf"
        ServerClient.remote = remote
        ServerClient.files["new-source.pdf"] = Data("new evidence".utf8)
        let backup = store.repository.directory.appendingPathComponent("state.backup.json")
        try FileManager.default.removeItem(at: backup)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.snapshot == original)
        assert(store.repository.attachment("new-source.pdf") == nil, "R2: failed pull left a staged source")
        let afterFailure = try Data(contentsOf: store.repository.attachment("original.pdf")!)
        assert(afterFailure == bytes)
        try FileManager.default.removeItem(at: backup)
        await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
        assert(store.snapshot == remote)
        assert(store.repository.attachment("new-source.pdf") != nil)
        // Verify the backup still has both the old references and their original bytes.
        let savedBackup = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: backup))
        assert(savedBackup == original)
        let afterSuccess = try Data(contentsOf: store.repository.attachment("original.pdf")!)
        assert(afterSuccess == bytes)
        print(
            "PASS R2: collisions preserve originals; identical/new files work; failed save rolls back new files and backup stays usable"
        )
    }
}
