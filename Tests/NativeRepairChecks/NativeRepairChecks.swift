// Purpose: Guard audited native state races and data-preservation behavior with production logic.
// Inputs: Synthetic fixture, real AppStore/LocalRepository, and deterministic service doubles.
// Outputs: Named behavioral assertions; a failed assertion exits nonzero.
// Side effects: Temporary snapshots and synthetic audio bytes only. No HTTP, providers, or microphone.

import Foundation

// MARK: - Controlled service boundaries
// Transport callbacks suspend requests while the real store processes a connection switch or edit.
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
    static func audioContentType(filename: String) -> String { "audio/mp4" }
}
@MainActor struct ProviderClient {
    static var duringRequest: (() async throws -> Void)?
    static var requestCount = 0
    static var summaryInput: MedicalRecord?
    static var preparationInput: [MedicalRecord] = []
    static let capabilities = ProviderStatus(
        gemini: .init(configured: true, model: "native-repair-double"),
        transcription: .init(configured: false, model: "native-repair-double"),
        booking: .init(configured: false, model: "native-repair-double"), liveCallsEnabled: false)
    init(url: String, token: String) throws {}
    private func wait() async throws {
        Self.requestCount += 1
        await Task.yield()
        try await Self.duringRequest?()
    }
    func status() async throws -> ProviderStatus {
        try await wait()
        return Self.capabilities
    }
    func summarize(_ record: MedicalRecord) async throws -> AISummary {
        Self.summaryInput = record
        try await wait()
        return AISummary(summary: "Current provider summary", model: "native-repair-double")
    }
    func prepare(_ visit: Visit, records: [MedicalRecord]) async throws -> AIPreparation {
        Self.preparationInput = records
        try await wait()
        return AIPreparation(
            overview: "Current overview", questions: ["Provider question"], selectedRecordIDs: [],
            model: "native-repair-double")
    }
    func transcribe(bytes: Data, filename: String) async throws -> AudioTranscription {
        try await wait()
        return AudioTranscription(
            text: "Current transcript", segments: [Self.segment], model: "native-repair-double")
    }
    static let segment = TranscriptSegment(
        id: "current-segment", speaker: "Clinician", start: 0, end: 1, text: "Current transcript")
    func startCall(_ input: LiveCallInput) async throws -> LiveCallResult {
        try await wait()
        return Self.callResult
    }
    func callStatus(requestID: String) async throws -> LiveCallResult {
        try await wait()
        return Self.callResult
    }
    static let callResult = LiveCallResult(
        conversationID: "current-conversation", status: "completed", provider: "native-repair-double",
        transcript: "Current call transcript")
}

// MARK: - Audited native regression checks
@main struct NativeRepairChecks {
    @MainActor static func main() async throws {
        let previousURL = UserDefaults.standard.object(forKey: "serverURL")
        defer { UserDefaults.standard.set(previousURL, forKey: "serverURL") }
        let fixture = try JSONDecoder().decode(
            AppSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let scratch = URL(fileURLWithPath: CommandLine.arguments[2])
        try checkStartupAndOrdering(fixture, root: scratch)
        try await checkProviders(fixture, root: scratch)
        try await checkProviderInputs(fixture, root: scratch)
        try await checkProviderCancellation(fixture, root: scratch)
        try await checkEditorMerges(fixture, root: scratch)
        try checkEditorConflicts(fixture, root: scratch)
        try checkRecordingPersistence(fixture, root: scratch)
        print("ALL NATIVE REPAIR STATE CHECKS PASSED")
    }

    @MainActor static func makeStore(_ fixture: AppSnapshot, root: URL) throws -> AppStore {
        let repository = LocalRepository(directory: root.appendingPathComponent(UUID().uuidString))
        try repository.save(fixture)
        let store = AppStore(repository: repository)
        precondition(store.startupError == nil)
        store.connectionURL = "http://127.0.0.1:8080"
        store.connectionToken = "synthetic-owner-a"
        store.notice = nil
        return store
    }

    static func request(_ fixture: AppSnapshot) -> BookingRequest {
        BookingRequest(
            id: "shared-request", visitID: fixture.visits[0].id, clinic: "Synthetic clinic",
            phone: "+15555550123", reason: "Synthetic review", earliest: "2026-09-15T09:00:00Z",
            latest: "2026-09-16T09:00:00Z", timeZone: "America/Chicago", preferences: "", status: "starting",
            isLive: true)
    }

    @MainActor static func checkStartupAndOrdering(_ fixture: AppSnapshot, root: URL) throws {
        for rename in [false, true] {
            var source = fixture
            var interrupted = request(fixture)
            interrupted.isLive = false
            interrupted.status = "queued"
            source.bookings = [interrupted]
            if rename {
                let i = source.records.firstIndex { $0.id == "demo-record-symptom-diary" }!
                source.records[i].title = "Nausea and palpitation diary - date needs review"
            }
            let repository = LocalRepository(directory: root.appendingPathComponent(UUID().uuidString))
            try repository.save(source)
            let backup = repository.directory.appendingPathComponent("state.backup.json")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
            let store = AppStore(repository: repository)
            precondition(store.startupError == nil && store.snapshot == source && store.errorMessage != nil)
            try FileManager.default.removeItem(at: backup)
            let retried = AppStore(repository: repository)
            precondition(
                retried.startupError == nil && retried.booking(interrupted.id)?.status == "needsUser")
            if rename {
                precondition(
                    retried.record("demo-record-symptom-diary")?.title
                        == "Weekly symptom diary")
            }
        }
        print(
            "PASS RVA-03-001: both startup repair failures preserve valid loaded state; a later launch repairs it"
        )
        let store = try makeStore(fixture, root: root)
        var early = fixture.visits[0]
        early.id = "a-early"
        early.date = "2026-09-15T13:00:00Z"
        var late = early
        late.id = "later"
        late.date = "2026-09-15T09:00:00-05:00"
        var tied = early
        tied.id = "b-tied"
        tied.date = "2026-09-15T15:00:00+02:00"
        try store.mutate {
            $0.visits = [late, tied, early]
            $0.bookings = []
            $0.recordings = []
        }
        precondition(store.visits.map(\.id) == [early.id, tied.id, late.id])
        print("PASS RVA-04-001: mixed offsets sort by actual instant with stable ID ties")
    }

    // MARK: - Provider success/error invalidation matrix
    @MainActor static func checkProviders(_ fixture: AppSnapshot, root: URL) async throws {
        let operations = ["summary", "prepare", "transcribe", "start", "poll", "discovery"]
        let boundaries = ["token", "url", "away-and-back", "replace", "pull", "reset"]
        for operation in operations {
            for boundary in boundaries {
                for fail in [false, true] {
                    var source = fixture
                    source.bookings = [request(fixture)]
                    source.recordings = [
                        VisitRecording(
                            id: "shared-recording", visitID: fixture.visits[0].id, title: "Synthetic audio",
                            duration: 2, audioFilename: "test.m4a")
                    ]
                    let store = try makeStore(source, root: root)
                    _ = try store.repository.storeAttachment(
                        Data("Synthetic audio".utf8), filename: "test.m4a")
                    store.useConnectedAI = true
                    var afterBoundary: AppSnapshot?
                    ProviderClient.duringRequest = {
                        switch boundary {
                        case "token": store.connectionToken = "synthetic-owner-b"
                        case "url": store.connectionURL = "http://localhost:9090"
                        case "away-and-back":
                            store.connectionToken = "synthetic-owner-b"
                            store.connectionToken = "synthetic-owner-a"
                        case "replace":
                            var replacement = source
                            replacement.profile.name = "Replacement workspace"
                            try store.repository.save(replacement)
                            store.snapshot = replacement
                        case "pull":
                            var replacement = source
                            for i in replacement.records.indices {
                                replacement.records[i].sourceFilename = nil
                            }
                            replacement.recordings[0].audioFilename = nil
                            replacement.profile.name = "Pulled workspace"
                            ServerClient.remote = replacement
                            await store.sync(
                                url: store.connectionURL, token: store.connectionToken, action: "pull")
                            precondition(store.snapshot == replacement)
                        default: try store.resetDemo()
                        }
                        afterBoundary = store.snapshot
                        store.notice = "Current workspace notice"
                        store.errorMessage = "Current workspace error"
                        if fail { throw RevaError.invalid("Obsolete provider failure") }
                    }
                    await run(operation, store: store, source: source)
                    precondition(
                        store.snapshot == afterBoundary, "Stale \(operation) changed \(boundary) workspace")
                    precondition(
                        store.notice == "Current workspace notice"
                            && store.errorMessage == "Current workspace error")
                    precondition(!store.isProviderBusy)
                    if operation == "discovery" { precondition(store.providerStatus == nil) }
                    if operation == "start", ["token", "url", "away-and-back"].contains(boundary) {
                        precondition(
                            store.booking("shared-request")?.status == "starting",
                            "Submitted request identity must remain available for polling under its original owner"
                        )
                    }
                }
            }
            // Normal responses still publish after unrelated notes/profile edits made during the await.
            var source = fixture
            source.bookings = [request(fixture)]
            source.recordings = [
                VisitRecording(
                    id: "shared-recording", visitID: fixture.visits[0].id, title: "Synthetic audio",
                    duration: 2, audioFilename: "test.m4a")
            ]
            let store = try makeStore(source, root: root)
            _ = try store.repository.storeAttachment(Data("Synthetic audio".utf8), filename: "test.m4a")
            store.useConnectedAI = true
            ProviderClient.duringRequest = {
                try store.mutate {
                    $0.profile.name = "Unrelated profile edit"
                    $0.records[0].notes = "New source notes"
                    $0.visits[0].notes = "New brief notes"
                    $0.recordings[0].summary = "New recording notes"
                }
            }
            await run(operation, store: store, source: source)
            precondition(store.snapshot?.profile.name == "Unrelated profile edit")
            precondition(store.record(source.records[0].id)?.notes == "New source notes")
            precondition(store.recording("shared-recording")?.summary == "New recording notes")
            precondition(store.errorMessage == nil)
            switch operation {
            case "summary":
                precondition(store.record(source.records[0].id)?.summary == "Current provider summary")
            case "prepare":
                precondition(
                    store.visit(source.visits[0].id)?.report?.generationModel == "native-repair-double")
                precondition(store.visit(source.visits[0].id)?.report?.notes == "New brief notes")
            case "transcribe":
                precondition(store.recording("shared-recording")?.segments == [ProviderClient.segment])
            case "discovery": precondition(store.providerStatus == ProviderClient.capabilities)
            default:
                precondition(
                    store.booking("shared-request")?.providerConversationID == "current-conversation")
            }
        }
        ProviderClient.duringRequest = nil
        print(
            "PASS RVA-10-001: 72 stale success/error cases across 6 provider operations and 6 boundaries; unrelated edits survive normal publication"
        )
        let store = try makeStore(fixture, root: root)
        store.useConnectedAI = true
        store.isProviderBusy = true
        let count = ProviderClient.requestCount
        let busyResult = await store.generatePreferredReport(fixture.visits[0].id)
        precondition(
            !busyResult && store.notice?.contains("still running") == true
                && ProviderClient.requestCount == count)
        store.isProviderBusy = false
        let normalResult = await store.generatePreferredReport(fixture.visits[0].id)
        precondition(normalResult && ProviderClient.requestCount == count + 1)
        print("PASS RVA-04-004: busy brief action explains retry, then succeeds after the request finishes")
    }

    @MainActor static func run(_ operation: String, store: AppStore, source: AppSnapshot) async {
        switch operation {
        case "summary": await store.summarizeWithAI(source.records[0].id)
        case "prepare": _ = await store.generatePreferredReport(source.visits[0].id)
        case "transcribe": await store.transcribeRecording("shared-recording")
        case "start": await store.placeLiveCall(request(source))
        case "discovery": await store.checkProviders()
        default: await store.refreshLiveCall("shared-request")
        }
    }

    // MARK: - Current source previews at the transport boundary
    @MainActor static func checkProviderInputs(_ fixture: AppSnapshot, root: URL) async throws {
        let completeLine = "Keep this complete source line."
        let sourceText = completeLine + "\n" + String(repeating: "x", count: 1800) + " 12 mg daily"
        var local = fixture.records[0]
        local.id = "input-local"
        local.isDemo = false
        local.text = sourceText
        local.summary = String(sourceText.prefix(1800))
        local.summaryModel = nil
        var legacyDemo = local
        legacyDemo.id = "input-legacy-demo"
        legacyDemo.isDemo = true
        legacyDemo.text = """
            SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD
            Source date: 2026-09-12
            \(sourceText)
            Invented for Reva software demonstration. Not a real patient record or medical advice.
            """
        var authoredDemo = legacyDemo
        authoredDemo.id = "input-authored-demo"
        authoredDemo.summary = "Authored fictional overview"
        var attributed = local
        attributed.id = "input-attributed"
        attributed.summary = "Previously reviewed provider overview"
        attributed.summaryModel = "previous-model"
        let examples = [local, legacyDemo, authoredDemo, attributed]
        let expected = [completeLine, completeLine, authoredDemo.summary, attributed.summary]
        var source = fixture
        source.records.append(contentsOf: examples)
        let store = try makeStore(source, root: root)
        store.useConnectedAI = true
        ProviderClient.duringRequest = nil
        let prepared = await store.generatePreferredReport(source.visits[0].id)
        precondition(prepared && store.snapshot?.records == source.records)
        for (record, summary) in zip(examples, expected) {
            var input = record
            input.summary = summary
            precondition(ProviderClient.preparationInput.first { $0.id == record.id } == input)
            ProviderClient.duringRequest = {
                precondition(
                    store.record(record.id) == record, "Preparing transport input rewrote saved source")
            }
            await store.summarizeWithAI(record.id)
            precondition(ProviderClient.summaryInput == input)
            precondition(store.record(record.id)?.summaryModel == "native-repair-double")
            precondition(store.record(record.id)?.text == record.text)
        }
        ProviderClient.duringRequest = nil
        print(
            "PASS provider inputs: summary and preparation refresh legacy local previews, preserve authored/model summaries and exact source text without rewriting saved inputs"
        )
    }

    // MARK: - Canceled requests must not publish a returned result
    @MainActor static func checkProviderCancellation(_ fixture: AppSnapshot, root: URL) async throws {
        for operation in ["summary", "prepare", "transcribe", "start", "poll", "discovery"] {
            var source = fixture
            source.bookings = [request(fixture)]
            source.recordings = [
                VisitRecording(
                    id: "shared-recording", visitID: fixture.visits[0].id, title: "Synthetic audio",
                    duration: 2, audioFilename: "cancel.m4a")
            ]
            let store = try makeStore(source, root: root)
            _ = try store.repository.storeAttachment(Data("Synthetic audio".utf8), filename: "cancel.m4a")
            store.useConnectedAI = true
            ProviderClient.duringRequest = { withUnsafeCurrentTask { $0?.cancel() } }
            // Cancel the operation task, not this harness task. The double still returns a valid result.
            let submittedSource = source
            await Task { @MainActor in await run(operation, store: store, source: submittedSource) }.value
            var expected = source
            if operation == "start" {
                expected.bookings[0].status = "unknown"
            }
            precondition(store.snapshot == expected, "Canceled \(operation) published a returned result")
            precondition(store.providerStatus == nil && store.notice == nil && !store.isProviderBusy)
            precondition(store.errorMessage != nil)
        }
        ProviderClient.duringRequest = nil
        precondition(!Task.isCancelled)
        print(
            "PASS provider cancellation: all 6 operations discard valid late results; submitted call identity remains recoverable"
        )
    }

    // MARK: - Field-specific editor preservation
    @MainActor static func checkEditorMerges(_ fixture: AppSnapshot, root: URL) async throws {
        let store = try makeStore(fixture, root: root)
        let original = store.records[0]
        var draft = original
        draft.notes = "Draft notes"
        ProviderClient.duringRequest = nil
        await store.summarizeWithAI(original.id)
        let summarized = store.record(original.id)!
        try store.saveRecordEdits(draft, original: original)
        let saved = store.record(original.id)!
        precondition(saved.summary == summarized.summary && saved.summaryModel == summarized.summaryModel)
        precondition(
            saved.version == summarized.version && saved.notes == draft.notes
                && saved.pageTexts == original.pageTexts)
        var corrected = saved
        corrected.text = "Corrected source words"
        try store.saveRecordEdits(corrected, original: saved)
        let edited = store.record(original.id)!
        precondition(
            edited.summary == ReportEngine.localExcerpt(corrected.text) && edited.summaryModel == nil
                && edited.pageTexts == nil && edited.status == "ready")
        var conflicting = draft
        conflicting.text = "Competing correction from the old source"
        do {
            try store.saveRecordEdits(conflicting, original: original)
            preconditionFailure("Edit of stale source text was accepted")
        } catch {}
        try store.deleteRecord(original.id)
        do {
            try store.saveRecordEdits(draft, original: original)
            preconditionFailure("Editor resurrected deleted record")
        } catch {}
        print(
            "PASS RVA-04-005: notes preserve completed AI summary/version/pages; real source edits refresh excerpt and deleted/stale sources are rejected"
        )
        let audio = VisitRecording(
            visitID: fixture.visits[0].id, title: "Synthetic audio", duration: 2,
            audioFilename: "notes-test.m4a")
        try store.save(audio)
        _ = try store.repository.storeAttachment(Data("Synthetic audio".utf8), filename: "notes-test.m4a")
        await store.transcribeRecording(audio.id)
        let transcribed = store.recording(audio.id)!
        try store.saveRecordingNotes("Separate visit notes", recordingID: audio.id)
        let notesSaved = store.recording(audio.id)!
        precondition(
            notesSaved.segments == transcribed.segments && notesSaved.status == transcribed.status
                && notesSaved.transcriptionModel == transcribed.transcriptionModel
                && notesSaved.audioFilename == transcribed.audioFilename
                && notesSaved.summary == "Separate visit notes")
        try store.mutate { $0.recordings.removeAll { $0.id == audio.id } }
        do {
            try store.saveRecordingNotes("Obsolete notes", recordingID: audio.id)
            preconditionFailure("Notes editor resurrected deleted recording")
        } catch {}
        print(
            "PASS RVA-05-001: notes preserve newer transcript/provenance/audio and cannot resurrect a deleted recording"
        )
    }

    // MARK: - Competing and converged edits share the production merge boundary
    @MainActor static func checkEditorConflicts(_ fixture: AppSnapshot, root: URL) throws {
        let edits: [(WritableKeyPath<MedicalRecord, String>, String, String)] = [
            (\.title, "Draft title", "Current title"),
            (\.provider, "Draft provider", "Current provider"),
            (\.date, "2026-09-13", "2026-09-14"),
            (\.kind, "Imaging", "Procedure"),
            (\.text, "Draft source words", "Current source words"),
            (\.notes, "Draft notes", "Current notes"),
        ]
        for (field, draftValue, currentValue) in edits {
            let store = try makeStore(fixture, root: root)
            let original = store.records[0]
            var draft = original
            draft[keyPath: field] = draftValue
            // Include another valid edit to prove rejection does not publish a partial merge.
            if field != \.title {
                draft.title = "Other draft title"
            } else {
                draft.notes = "Other draft notes"
            }
            var current = original
            current[keyPath: field] = currentValue
            try store.save(current)
            let before = store.snapshot
            do {
                try store.saveRecordEdits(draft, original: original)
                preconditionFailure("Competing editor field was overwritten")
            } catch {}
            precondition(store.snapshot == before)

            // Two edits reaching the same value are compatible, including a source whose new summary arrived later.
            current[keyPath: field] = draftValue
            if field == \.text {
                current.summary = "New provider summary for converged text"
                current.summaryModel = "converged-model"
                current.pageTexts = [draftValue]
            }
            try store.save(current)
            let converged = store.record(original.id)!
            var matching = original
            matching[keyPath: field] = draftValue
            try store.saveRecordEdits(matching, original: original)
            precondition(
                store.record(original.id) == converged, "Converged edit changed newer fields/version")
        }
        let store = try makeStore(fixture, root: root)
        let original = store.records[0]
        for invalid in ["identity", "title"] {
            var draft = original
            if invalid == "identity" { draft.id = "different-record" } else { draft.title = " \n " }
            let before = store.snapshot
            do {
                try store.saveRecordEdits(draft, original: original)
                preconditionFailure("Invalid editor identity/title accepted")
            } catch {}
            precondition(store.snapshot == before)
        }
        for field: WritableKeyPath<MedicalRecord, String> in [\.kind, \.provider] {
            let before = store.record(original.id)!
            var draft = before
            draft[keyPath: field] = field == \.kind ? "Imaging" : "Changed clinician"
            let signature = ReportEngine.signature(visit: fixture.visits[0], records: store.records)
            try store.saveRecordEdits(draft, original: before)
            var expected = draft
            expected.version = before.version + 1
            precondition(store.record(original.id) == expected)
            precondition(
                signature != ReportEngine.signature(visit: fixture.visits[0], records: store.records))
        }
        print(
            "PASS editor conflicts: 6 competing fields reject atomically; 6 converged fields preserve newer data/version; identity/title validation and kind/provider versioning hold"
        )
    }

    // MARK: - Finalized audio metadata failure and retry
    @MainActor static func checkRecordingPersistence(_ fixture: AppSnapshot, root: URL) throws {
        let store = try makeStore(fixture, root: root)
        let bytes = Data("Synthetic finalized audio bytes".utf8)
        let url = try store.repository.storeAttachment(bytes, filename: "finalized.m4a")
        let pending = VisitRecording(
            visitID: fixture.visits[0].id, title: "Finalized recording", duration: 2,
            audioFilename: url.lastPathComponent)
        var draft = RecordingSaveDraft()
        draft.retain(pending, audioURL: url)
        let backup = store.repository.directory.appendingPathComponent("state.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        for _ in 0..<2 {
            do {
                _ = try draft.save(to: store)
                preconditionFailure("Synthetic failed save unexpectedly succeeded")
            } catch {}
            precondition(
                store.recording(pending.id) == nil && draft.recording == pending && draft.audioURL == url)
            precondition((try? Data(contentsOf: draft.audioURL!)) == bytes)
        }
        try FileManager.default.removeItem(at: backup)
        let savedID = try draft.save(to: store)
        precondition(savedID == pending.id && draft.recording == nil && draft.audioURL == nil)
        try store.save(pending)
        precondition(
            store.recordings.filter { $0.id == pending.id }.count == 1
                && store.recording(pending.id) == pending)
        precondition((try? Data(contentsOf: url)) == bytes)
        print(
            "PASS RVA-05-008: production save draft retains metadata/audio after failure; retry saves the same identity/file and clears only on success"
        )
    }
}
