// Purpose: Guard audited native state races and data-preservation behavior with production logic.
// Inputs: Synthetic fixture, real AppStore/LocalRepository, and deterministic service doubles.
// Outputs: Named behavioral assertions; a failed assertion exits nonzero.
// Side effects: Temporary snapshots and synthetic audio bytes only. No HTTP, providers, or microphone.

import Foundation

// MARK: - Controlled service boundaries
// Transport callbacks suspend requests while the real store processes a connection switch or edit.
struct ServerState: Codable {
    var revision: Int
    var snapshot: AppSnapshot
}
enum ServerFailure: LocalizedError {
    case conflict
    case empty(Int)
    case response(Int)
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
    init(baseURL: URL, token: String, session: URLSession = .shared) throws {}
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
        transcription: .init(configured: false, model: "native-repair-double"))
    init(url: String, token: String, session: URLSession = .shared) throws {}
    private func wait() async throws {
        Self.requestCount += 1
        await Task.yield()
        try await Self.duringRequest?()
    }
    func status() async throws -> ProviderStatus {
        try await wait()
        return Self.capabilities
    }
    func medicalProfile(_ sources: [NativeProfileSource]) async throws -> NativeProfileResult {
        try await wait()
        return NativeProfileResult(
            allergies: [], medications: [], conditions: [], surgeriesAndImplants: [], careNotes: [],
            model: "native-repair-double")
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
        try await checkAppointmentSummaries(fixture, root: scratch)
        try await checkAutomaticAccountSync(root: scratch)
        print("ALL NATIVE REPAIR STATE CHECKS PASSED")
    }

    @MainActor static func checkAutomaticAccountSync(root: URL) async throws {
        let user = NativeAccountUser(
            id: "sync-test", email: "judge@example.test", name: "Native Judge", createdAt: RevaDate.now)
        let session = NativeAccountSession(token: "synthetic", expiresAt: "2099-01-01T00:00:00Z", user: user)
        let repository = LocalRepository(directory: root.appendingPathComponent("account-sync"))
        let store = AppStore(repository: repository, account: session)
        let empty = NativeAccount.emptySnapshot(user)
        precondition(
            store.snapshot == empty && store.useConnectedAI && store.connectionToken == session.token)
        ServerClient.onPull = nil
        ServerClient.onPush = nil
        ServerClient.onUpload = nil
        ServerClient.onAttachment = nil
        ServerClient.remote = empty
        var remote = empty
        remote.profile.allergies = ["Remote allergy"]
        ServerClient.remote = remote
        try store.mutate { $0.profile.medications = ["Local medication"] }
        store.backgroundActive = true
        await store.synchronizeAccount()
        precondition(store.snapshot?.profile.medications == ["Local medication"])
        precondition(store.snapshot?.profile.allergies == ["Remote allergy"])
        precondition(ServerClient.lastPushed == store.snapshot && store.syncBase?.snapshot == store.snapshot)
        precondition(store.syncStatus == "All changes saved")
        let persisted = AppStore(repository: repository, account: session)
        precondition(persisted.syncBase?.snapshot == store.syncBase?.snapshot)
        ServerClient.onPush = {
            try store.mutate { $0.profile.careNotes = "Typed during upload" }
        }
        try store.mutate { $0.profile.conditions = ["Another edit"] }
        await store.synchronizeAccount()
        precondition(store.snapshot?.profile.careNotes == "Typed during upload")
        precondition(store.syncBase?.snapshot.profile.careNotes == nil)
        precondition(store.syncStatus == "Saving newer changes…")
        ServerClient.onPush = nil
        ServerClient.onPull = { throw ServerFailure.response(401) }
        var expired = false
        let retained = store.snapshot
        store.sessionExpired = {
            expired = true
            store.stopBackgroundUpdates()
            store.needsSignIn = true
        }
        await store.synchronizeAccount()
        precondition(expired && store.snapshot == retained && store.needsSignIn)
        ServerClient.onPull = nil
        let demo = try makeStore(empty, root: root)
        demo.backgroundActive = true
        demo.providerStatus = ProviderClient.capabilities
        demo.useConnectedAI = true
        try demo.mutate {
            $0.records = [
                MedicalRecord(
                    title: "Report", kind: "Notes", provider: "", date: RevaDate.now,
                    text: "Synthetic original", summary: "")
            ]
        }
        precondition(demo.profileDebounce != nil)
        demo.useConnectedAI = false
        precondition(demo.profileDebounce?.isCancelled == true && demo.profileObserved.isEmpty)
        demo.stopBackgroundUpdates()
        print(
            "PASS native accounts: isolated empty workspace, automatic merge and baseline persistence, edits during upload, expiry preserves state, and AI opt-out cancels work"
        )
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

    @MainActor static func checkStartupAndOrdering(_ fixture: AppSnapshot, root: URL) throws {
        var source = fixture
        let i = source.records.firstIndex { $0.id == "demo-record-symptom-diary" }!
        source.records[i].title = "Nausea and palpitation diary - date needs review"
        let repository = LocalRepository(directory: root.appendingPathComponent(UUID().uuidString))
        try repository.save(source)
        let backup = repository.directory.appendingPathComponent("state.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        let failedRepair = AppStore(repository: repository)
        precondition(
            failedRepair.startupError == nil && failedRepair.snapshot == source
                && failedRepair.errorMessage != nil)
        try FileManager.default.removeItem(at: backup)
        let retried = AppStore(repository: repository)
        precondition(retried.record("demo-record-symptom-diary")?.title == "Weekly symptom diary")
        precondition(retried.snapshot?.bookings == source.bookings)
        print(
            "PASS RVA-03-001: failed label repair preserves loaded state; later launch repairs labels and preserves archived data"
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
        let operations = ["summary", "prepare", "transcribe", "appointmentSummary", "discovery"]
        let boundaries = ["token", "url", "away-and-back", "replace", "pull", "reset"]
        for operation in operations {
            for boundary in boundaries {
                for fail in [false, true] {
                    var source = fixture
                    source.recordings = [
                        VisitRecording(
                            id: "shared-recording", visitID: fixture.visits[0].id, title: "Synthetic audio",
                            duration: 2, audioFilename: "test.m4a",
                            segments: operation == "appointmentSummary" ? [ProviderClient.segment] : [])
                    ]
                    let store = try makeStore(source, root: root)
                    _ = try store.repository.storeAttachment(
                        Data("Synthetic audio".utf8), filename: "test.m4a")
                    store.useConnectedAI = true
                    if operation == "appointmentSummary" {
                        store.providerStatus = ProviderClient.capabilities
                    }
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

                }
            }
            // Normal responses still publish after unrelated notes/profile edits made during the await.
            var source = fixture
            source.recordings = [
                VisitRecording(
                    id: "shared-recording", visitID: fixture.visits[0].id, title: "Synthetic audio",
                    duration: 2, audioFilename: "test.m4a",
                    segments: operation == "appointmentSummary" ? [ProviderClient.segment] : [])
            ]
            let store = try makeStore(source, root: root)
            _ = try store.repository.storeAttachment(Data("Synthetic audio".utf8), filename: "test.m4a")
            store.useConnectedAI = true
            if operation == "appointmentSummary" { store.providerStatus = ProviderClient.capabilities }
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
            case "appointmentSummary":
                precondition(store.recording("shared-recording")?.aiSummary == "Current provider summary")
            default: preconditionFailure("Unexpected synthetic operation")
            }
        }
        ProviderClient.duringRequest = nil
        print(
            "PASS RVA-10-001: 60 stale success/error cases across 5 provider operations and 6 boundaries; unrelated edits survive normal publication"
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
        case "appointmentSummary": await store.summarizeRecording("shared-recording")
        case "discovery": await store.checkProviders()
        default: preconditionFailure("Unexpected synthetic operation")
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
        for operation in ["summary", "prepare", "transcribe", "appointmentSummary", "discovery"] {
            var source = fixture
            source.recordings = [
                VisitRecording(
                    id: "shared-recording", visitID: fixture.visits[0].id, title: "Synthetic audio",
                    duration: 2, audioFilename: "cancel.m4a",
                    segments: operation == "appointmentSummary" ? [ProviderClient.segment] : [])
            ]
            let store = try makeStore(source, root: root)
            _ = try store.repository.storeAttachment(Data("Synthetic audio".utf8), filename: "cancel.m4a")
            store.useConnectedAI = true
            if operation == "appointmentSummary" { store.providerStatus = ProviderClient.capabilities }
            ProviderClient.duringRequest = { withUnsafeCurrentTask { $0?.cancel() } }
            // Cancel the operation task, not this harness task. The double still returns a valid result.
            let submittedSource = source
            await Task { @MainActor in await run(operation, store: store, source: submittedSource) }.value
            let expected = source
            precondition(store.snapshot == expected, "Canceled \(operation) published a returned result")
            precondition(
                store.providerStatus
                    == (operation == "appointmentSummary" ? ProviderClient.capabilities : nil)
                    && store.notice == nil && !store.isProviderBusy)
            precondition(store.errorMessage != nil)
        }
        ProviderClient.duringRequest = nil
        precondition(!Task.isCancelled)
        print(
            "PASS provider cancellation: all 5 operations discard valid late results"
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

    // MARK: - Appointment summary source, edit, and memory integrity
    @MainActor static func checkAppointmentSummaries(_ fixture: AppSnapshot, root: URL) async throws {
        let store = try makeStore(fixture, root: root)
        let transcript = [
            TranscriptSegment(
                id: "first", speaker: "Speaker", start: 0, end: 2, text: "Exact first words: café, 0.25 mg."),
            TranscriptSegment(
                id: "last", speaker: "Speaker", start: 2, end: 4,
                text: String(repeating: "Full source words. ", count: 200)),
        ]
        let recording = VisitRecording(
            id: "appointment", visitID: fixture.visits[0].id, title: "Synthetic appointment",
            createdAt: "2026-09-12T02:00:00Z", duration: 4,
            audioFilename: "appointment.m4a", segments: transcript, summary: "Private separate notes")
        try store.save(recording)
        let requestCount = ProviderClient.requestCount
        await store.summarizeRecording(recording.id)
        precondition(
            ProviderClient.requestCount == requestCount && store.recording(recording.id)?.aiSummary == nil)
        store.providerStatus = ProviderClient.capabilities
        store.errorMessage = nil
        ProviderClient.duringRequest = {
            try store.saveRecordingNotes("Newer user notes", recordingID: recording.id)
        }
        await store.summarizeRecording(recording.id)
        let summarized = store.recording(recording.id)!
        precondition(summarized.hasAISummary && summarized.summary == "Newer user notes")
        precondition(summarized.segments == transcript && summarized.audioFilename == recording.audioFilename)
        precondition(ProviderClient.summaryInput?.title == recording.title)
        precondition(ProviderClient.summaryInput?.text == recording.transcriptText)
        precondition(ProviderClient.summaryInput?.summary == "" && ProviderClient.summaryInput?.notes == "")
        try store.saveMemory(recordingID: recording.id)
        let memory = store.record("memory-" + recording.id)!
        precondition(memory.text == recording.transcriptText && memory.text.count > 1800)
        precondition(
            memory.summary == summarized.aiSummary && memory.summaryModel == summarized.aiSummaryModel)
        precondition(memory.notes.contains("Newer user notes"))
        precondition(memory.date == "2026-09-11" && summarized.createdAt == recording.createdAt)

        var editedMemory = memory
        editedMemory.notes = "Separate notes edited directly on the saved memory."
        editedMemory.date = "2026-09-10"
        try store.save(editedMemory)
        ProviderClient.duringRequest = nil
        await store.summarizeRecording(recording.id)
        precondition(store.record(memory.id)?.notes == editedMemory.notes)
        precondition(store.record(memory.id)?.date == editedMemory.date)
        precondition(store.recording(recording.id)?.summary == "Newer user notes")

        // A failed checkpoint cannot save the new derived summary without its memory (or vice versa).
        let beforeFailure = store.snapshot
        let backup = store.repository.directory.appendingPathComponent("state.backup.json")
        try FileManager.default.removeItem(at: backup)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        await store.summarizeRecording(recording.id)
        precondition(store.snapshot == beforeFailure && store.errorMessage != nil)
        try FileManager.default.removeItem(at: backup)
        store.errorMessage = nil

        // Saving unchanged transcript text retains a reviewed summary, while changed words invalidate it.
        let unchanged = Dictionary(uniqueKeysWithValues: transcript.map { ($0.id, $0.text) })
        try store.saveMemory(recordingID: recording.id, correctedSegmentTexts: unchanged)
        precondition(store.recording(recording.id)?.aiSummary == summarized.aiSummary)
        var corrected = unchanged
        corrected["first"] = "Corrected exact words."
        try store.saveMemory(recordingID: recording.id, correctedSegmentTexts: corrected)
        let changed = store.recording(recording.id)!
        precondition(
            !changed.hasAISummary && changed.aiSummary == nil && changed.aiSummaryModel == nil
                && changed.aiSummaryGeneratedAt == nil)
        precondition(
            changed.summary == "Newer user notes" && changed.segments[0].start == transcript[0].start
                && changed.segments[0].end == transcript[0].end)
        precondition(
            store.record(memory.id)?.text == changed.transcriptText
                && store.record(memory.id)?.summaryModel == nil)
        precondition(store.record(memory.id)?.notes == editedMemory.notes)

        // A result from old source text, title, or a deleted recording cannot publish.
        for boundary in ["transcript", "title", "delete"] {
            try store.save(recording)
            store.errorMessage = nil
            ProviderClient.duringRequest = {
                try store.mutate { data in
                    let index = data.recordings.firstIndex { $0.id == recording.id }!
                    switch boundary {
                    case "transcript": data.recordings[index].segments[0].text = "Concurrent correction"
                    case "title": data.recordings[index].title = "Current title"
                    default: data.recordings.remove(at: index)
                    }
                }
            }
            await store.summarizeRecording(recording.id)
            precondition(store.recording(recording.id)?.aiSummary == nil && store.errorMessage != nil)
        }
        var empty = recording
        empty.segments = []
        try store.save(empty)
        ProviderClient.duringRequest = nil
        let beforeEmpty = ProviderClient.requestCount
        await store.summarizeRecording(recording.id)
        precondition(
            ProviderClient.requestCount == beforeEmpty && store.recording(recording.id)?.aiSummary == nil)
        print(
            "PASS appointment summaries: configured transcript-only requests; newer notes, full source, summary provenance and timestamps preserved; corrections invalidate AI; stale/deleted/empty sources rejected"
        )
    }
}
