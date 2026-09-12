// Purpose: Reproduce native audit races and recovery/editor failures using production state logic.
// Inputs: Fictional seed plus deterministic suspended provider and server doubles.
// Outputs: Named assertions covering each repaired state boundary.
// Side effects: Synthetic temporary files only; no network, real audio, or patient data.

import Foundation

#if canImport(Combine)
    import Combine
#else
    // Observation delivery is an Apple UI concern, outside these state mutation checks.
    @propertyWrapper struct Published<Value> {
        var wrappedValue: Value
        init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }
    protocol ObservableObject {}
#endif
#if !canImport(CryptoKit)
    // Preserve exact input equality for production signature checks. This does not test cryptography.
    enum SHA256 {
        static func hash(data: Data) -> [UInt8] { Array(data) }
    }
#endif

// MARK: - Controlled provider completions
@MainActor struct ProviderClient {
    static var onRequest: ((String) async throws -> Void)?
    static var preparedRecords: [MedicalRecord] = []
    static let capabilities = ProviderStatus(
        gemini: .init(configured: true, model: "synthetic"),
        transcription: .init(configured: true, model: "synthetic"),
        booking: .init(configured: true, model: "synthetic"), liveCallsEnabled: true)
    static let segments = [
        TranscriptSegment(id: "segment-a", speaker: "Speaker", start: 0, end: 1, text: "First words."),
        TranscriptSegment(id: "segment-b", speaker: "Speaker", start: 1, end: 2, text: "Second words."),
    ]
    init(url: String, token: String) throws {}
    func status() async throws -> ProviderStatus {
        try await Self.onRequest?("discovery")
        return Self.capabilities
    }
    func summarize(_ record: MedicalRecord) async throws -> AISummary {
        try await Self.onRequest?("summary")
        return AISummary(summary: "Latest synthetic summary", model: "synthetic-summary")
    }
    func prepare(_ visit: Visit, records: [MedicalRecord]) async throws -> AIPreparation {
        Self.preparedRecords = records
        try await Self.onRequest?("prepare")
        return AIPreparation(
            overview: "Synthetic overview", questions: [], selectedRecordIDs: [records[0].id],
            model: "synthetic-brief")
    }
    func transcribe(bytes: Data, filename: String) async throws -> AudioTranscription {
        try await Self.onRequest?("transcribe")
        return AudioTranscription(
            text: "First words. Second words.", segments: Self.segments, model: "synthetic-speech")
    }
    func startCall(_ input: LiveCallInput) async throws -> LiveCallResult {
        try await Self.onRequest?("start")
        return LiveCallResult(conversationID: "synthetic-call", status: "calling", provider: "synthetic")
    }
    func callStatus(requestID: String) async throws -> LiveCallResult {
        try await Self.onRequest?("status")
        return LiveCallResult(
            conversationID: "synthetic-call", status: "completed", provider: "synthetic",
            transcript: "Synthetic outcome")
    }
}

// MARK: - Synthetic snapshot transport
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
    init(baseURL: URL, token: String) throws {}
    func health() async throws -> String { "Connected" }
    func pull() async throws -> ServerState { ServerState(revision: 1, snapshot: Self.remote) }
    func push(_ snapshot: AppSnapshot, revision: Int) async throws -> Int { revision + 1 }
    func uploadAttachment(id: String, filename: String, data: Data, type: String) async throws {}
    func attachment(id: String) async throws -> Data { Data("Synthetic audio".utf8) }
    static func attachmentID(for name: String) -> String { name }
    static func attachmentMetadataName(_ name: String) -> String { name }
    static func uploadContentType(_ type: String?) -> String { type ?? "application/octet-stream" }
}

// MARK: - Isolated fixture ownership
@main struct AuditStateChecks {
    @MainActor static func main() async throws {
        let previousURL = UserDefaults.standard.object(forKey: "serverURL")
        defer { UserDefaults.standard.set(previousURL, forKey: "serverURL") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RevaAudit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try JSONDecoder().decode(
            AppSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        try checkStartup(fixture, root: root)
        let store = try makeStore(fixture, root: root)
        try checkOrder(store)
        try await checkEditors(store)
        try await checkBusy(store)
        try await checkProviderOwnership(fixture, root: root)
        try await checkLegacyPreview(fixture, root: root)
        print("PASS AuditStateChecks: all production state regressions passed")
    }

    // MARK: - Legacy local previews never become inaccurate provider input
    @MainActor static func checkLegacyPreview(_ fixture: AppSnapshot, root: URL) async throws {
        let store = try makeStore(fixture, root: root)
        ProviderClient.onRequest = nil
        try store.mutate { data in
            data.records[0].isDemo = false
            data.records[0].text = String(repeating: "x", count: 1791) + " dose: 100 mg"
            data.records[0].summary = String(data.records[0].text.prefix(1800))
            data.records[0].summaryModel = nil
            data.records[1].isDemo = false
            data.records[1].summaryModel = "synthetic-attributed-model"
        }
        let savedRecords = store.snapshot!.records
        let generated = await store.generatePreferredReport(store.visits[0].id)
        precondition(generated)
        let sent = ProviderClient.preparedRecords
        precondition(sent.first { $0.id == savedRecords[0].id }?.summary == "")
        precondition(sent.first { $0.id == savedRecords[0].id }?.text == savedRecords[0].text)
        precondition(sent.first { $0.id == savedRecords[1].id }?.summary == savedRecords[1].summary)
        precondition(store.snapshot!.records == savedRecords)
        print("PASS: provider preparation refreshes legacy local excerpts without rewriting originals")
    }

    @MainActor static func makeStore(_ fixture: AppSnapshot, root: URL) throws -> AppStore {
        var source = fixture
        for i in source.records.indices { source.records[i].sourceFilename = nil }
        source.recordings = [
            VisitRecording(
                id: "synthetic-recording", visitID: source.visits[0].id, title: "Synthetic visit",
                duration: 3,
                audioFilename: "synthetic.m4a")
        ]
        source.bookings = [
            BookingRequest(
                id: "synthetic-booking", visitID: source.visits[0].id, clinic: "Synthetic clinic",
                phone: "5555550100",
                reason: "Synthetic follow-up", earliest: source.visits[0].date, latest: source.visits[0].date,
                timeZone: "America/Chicago", preferences: "", isLive: true)
        ]
        let repository = LocalRepository(directory: root.appendingPathComponent(UUID().uuidString))
        try repository.save(source)
        _ = try repository.storeAttachment(Data("Synthetic audio".utf8), filename: "synthetic.m4a")
        let store = AppStore(repository: repository)
        assert(store.startupError == nil)
        store.connectionURL = "http://localhost"
        store.connectionToken = "synthetic-owner"
        store.useConnectedAI = true
        return store
    }

    // MARK: - Valid startup survives failed optional repair
    @MainActor static func checkStartup(_ fixture: AppSnapshot, root: URL) throws {
        var source = fixture
        source.bookings = [
            BookingRequest(
                id: "interrupted-booking", visitID: source.visits[0].id, clinic: "Synthetic clinic",
                phone: "5555550100",
                reason: "Synthetic follow-up", earliest: source.visits[0].date, latest: source.visits[0].date,
                timeZone: "America/Chicago", preferences: "", status: "queued")
        ]
        let repository = LocalRepository(directory: root.appendingPathComponent("repair-failure"))
        try repository.save(source)
        let backup = repository.directory.appendingPathComponent("state.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        let store = AppStore(repository: repository)
        assert(store.startupError == nil && store.snapshot == source)
        assert(store.errorMessage?.contains("startup repair") == true)
        assert(store.bookings[0].status == "queued")
        let loaded = try repository.load()
        assert(loaded?.snapshot == source)
        print(
            "PASS RVA-03-001: failed repair leaves valid saved data available and surfaces a recoverable error"
        )
    }

    // MARK: - Visits sort by actual instant
    @MainActor static func checkOrder(_ store: AppStore) throws {
        var later = store.visits[0]
        later.id = "later"
        later.date = "2026-09-15T09:00:00-05:00"
        later.status = "upcoming"
        var earlier = later
        earlier.id = "earlier"
        earlier.date = "2026-09-15T13:00:00Z"
        var equal = earlier
        equal.id = "equal"
        equal.date = "2026-09-15T08:00:00-05:00"
        try store.mutate { $0.visits.append(contentsOf: [later, equal, earlier]) }
        let sorted = store.visits.filter { ["earlier", "equal", "later"].contains($0.id) }
        assert(sorted.map(\.id) == ["earlier", "equal", "later"])
        assert(sorted.first(where: { $0.status == "upcoming" })?.id == "earlier")
        print("PASS RVA-04-001: mixed UTC/offset instants sort chronologically with stable ID ties")
    }

    // MARK: - Field-targeted editor reconciliation
    @MainActor static func checkEditors(_ store: AppStore) async throws {
        let original = store.records[0]
        var draft = original
        draft.notes = "Notes drafted before the summary arrived"
        ProviderClient.onRequest = nil
        await store.summarizeWithAI(original.id)
        let summarized = store.record(original.id)!
        assert(summarized.summaryModel == "synthetic-summary")
        try store.saveRecordEdits(original: original, draft: draft, reviewed: false)
        let merged = store.record(original.id)!
        assert(merged.summary == summarized.summary && merged.summaryModel == summarized.summaryModel)
        assert(merged.notes == draft.notes && merged.version == summarized.version)
        assert(merged.pageTexts == summarized.pageTexts && merged.isDemo == summarized.isDemo)
        var sourceEdit = merged
        sourceEdit.text = "Reviewed correction with original units: 10 mg."
        try store.saveRecordEdits(original: merged, draft: sourceEdit, reviewed: false)
        let corrected = store.record(original.id)!
        assert(corrected.summary == ReportEngine.localExcerpt(sourceEdit.text))
        assert(
            corrected.summaryModel == nil && corrected.pageTexts == nil && corrected.status == "needsReview")
        assert(corrected.version == merged.version + 1)
        var staleSourceEdit = merged
        staleSourceEdit.text = "Conflicting source correction"
        do {
            try store.saveRecordEdits(original: merged, draft: staleSourceEdit, reviewed: true)
            assertionFailure("A conflicting source edit replaced the latest source")
        } catch { assert(store.record(original.id) == corrected) }
        var kindEdit = corrected
        kindEdit.kind = "Imaging"
        try store.saveRecordEdits(original: corrected, draft: kindEdit, reviewed: true)
        let classified = store.record(original.id)!
        assert(classified.kind == "Imaging" && classified.summary == corrected.summary)
        assert(classified.version == corrected.version + 1 && classified.status == "ready")
        print(
            "PASS RVA-04-005: notes preserve incoming summary; source conflicts reject; correction invalidates derived data; kind edit saves"
        )

        let staleRecording = store.recordings[0]
        await store.transcribeRecording(staleRecording.id)
        let transcribed = store.recording(staleRecording.id)!
        assert(transcribed.segments.count == 2 && transcribed.transcriptionModel == "synthetic-speech")
        try store.updateRecordingNotes(id: staleRecording.id, summary: "Notes from the open editor")
        var expected = transcribed
        expected.summary = "Notes from the open editor"
        assert(store.recording(staleRecording.id) == expected)
        print(
            "PASS RVA-05-001: notes-only save preserves incoming transcript, model, timestamps, status and audio"
        )
    }

    // MARK: - Busy preparation has visible feedback and recovers
    @MainActor static func checkBusy(_ store: AppStore) async throws {
        let visitID = store.visits[0].id
        ProviderClient.onRequest = { operation in
            assert(operation == "summary")
            let generated = await store.generatePreferredReport(visitID)
            assert(!generated && store.notice?.contains("still running") == true)
        }
        await store.summarizeWithAI(store.records[0].id)
        ProviderClient.onRequest = nil
        let generated = await store.generatePreferredReport(visitID)
        assert(generated && store.visit(visitID)?.report?.generationModel == "synthetic-brief")
        print(
            "PASS RVA-04-004: busy report request explains retry; generation succeeds once provider finishes")
    }

    // MARK: - Provider results cannot cross identity or workspace boundaries
    @MainActor static func checkProviderOwnership(_ fixture: AppSnapshot, root: URL) async throws {
        let operations = ["summary", "prepare", "transcribe", "start", "status", "discovery"]
        for operation in operations {
            for change in ["token", "url-away-back", "workspace", "pull"] {
                for fail in [false, true] {
                    let store = try makeStore(fixture, root: root)
                    var expected: AppSnapshot?
                    ProviderClient.onRequest = { actual in
                        assert(actual == operation)
                        await Task.yield()
                        switch change {
                        case "token": store.connectionToken = "different-synthetic-owner"
                        case "url-away-back":
                            let url = store.connectionURL
                            store.connectionURL = "http://127.0.0.1"
                            store.connectionURL = url
                        case "workspace":
                            let sameData = store.snapshot
                            store.snapshot = sameData
                        default:
                            ServerClient.remote = store.snapshot
                            await store.sync(
                                url: store.connectionURL, token: store.connectionToken, action: "pull")
                        }
                        expected = store.snapshot
                        store.notice = "Current workspace notice"
                        store.errorMessage = "Current workspace error"
                        if fail { throw RevaError.invalid("Stale synthetic provider failure") }
                    }
                    await invoke(operation, store: store)
                    assert(
                        expected != nil && store.snapshot == expected, "Stale \(operation) crossed \(change)")
                    assert(
                        store.notice == "Current workspace notice"
                            && store.errorMessage == "Current workspace error")
                    assert(!store.isProviderBusy)
                    if operation == "start", change != "pull" {
                        assert(
                            store.bookings[0].status == "starting"
                                && store.bookings[0].providerConversationID == nil)
                    }
                }
            }
            let control = try makeStore(fixture, root: root)
            ProviderClient.onRequest = { _ in
                await Task.yield()
                // An ordinary unrelated edit must not invalidate the operation's workspace identity.
                try control.mutate { $0.profile.careNotes = "Newer local note" }
            }
            await invoke(operation, store: control)
            assert(control.snapshot?.profile.careNotes == "Newer local note")
            switch operation {
            case "summary": assert(control.record(fixture.records[0].id)?.summaryModel == "synthetic-summary")
            case "prepare":
                assert(control.visit(fixture.visits[0].id)?.report?.generationModel == "synthetic-brief")
            case "transcribe": assert(control.recordings[0].transcriptionModel == "synthetic-speech")
            case "start": assert(control.bookings[0].providerConversationID == "synthetic-call")
            case "status": assert(control.bookings[0].providerTranscript == "Synthetic outcome")
            default: assert(control.providerStatus == ProviderClient.capabilities)
            }
            print(
                "PASS RVA-10-001: \(operation) rejects stale success/error across token, switch-back, replacement and pull; valid completion keeps unrelated edits"
            )
        }
        ProviderClient.onRequest = nil
    }

    @MainActor static func invoke(_ operation: String, store: AppStore) async {
        switch operation {
        case "summary": await store.summarizeWithAI(store.snapshot!.records[0].id)
        case "prepare": await store.generatePreferredReport(store.snapshot!.visits[0].id)
        case "transcribe": await store.transcribeRecording(store.recordings[0].id)
        case "start": await store.placeLiveCall(store.bookings[0])
        case "status": await store.refreshLiveCall(store.bookings[0].id)
        default: await store.checkProviders()
        }
    }
}
