import Foundation
import Combine

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot?
    @Published var errorMessage: String?
    @Published var startupError: String?
    @Published var notice: String?
    @Published var isSyncing = false
    @Published var serverStatus = "Not connected"
    @Published var serverRevision = 0
    @Published var serverConflictRevision: Int?
    let repository: LocalRepository
    private var serverIdentity = ""

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Reva", isDirectory: true)
        repository = LocalRepository(directory: root)
        do {
            if let loaded = try repository.load() {
                snapshot = loaded.snapshot
                if loaded.recovered { notice = "Recovered the last valid checkpoint. Your original files remain available." }
                if snapshot?.bookings.contains(where: { ["queued", "calling"].contains($0.status) }) == true {
                    try mutate { data in for i in data.bookings.indices where ["queued", "calling"].contains(data.bookings[i].status) { data.bookings[i].status = "needsUser" } }
                    notice = "An interrupted demo booking needs your attention. Open it to retry."
                }
            } else { try resetDemo() }
        } catch { startupError = error.localizedDescription }
    }
    var records: [MedicalRecord] { (snapshot?.records ?? []).sorted { $0.date > $1.date } }
    var visits: [Visit] { (snapshot?.visits ?? []).sorted { $0.date < $1.date } }
    var bookings: [BookingRequest] { snapshot?.bookings ?? [] }
    var recordings: [VisitRecording] { snapshot?.recordings ?? [] }
    func record(_ id: String) -> MedicalRecord? { records.first { $0.id == id } }
    func visit(_ id: String) -> Visit? { visits.first { $0.id == id } }
    func booking(_ id: String) -> BookingRequest? { bookings.first { $0.id == id } }
    func recording(_ id: String) -> VisitRecording? { recordings.first { $0.id == id } }
    func sourceURL(_ record: MedicalRecord) -> URL? { record.sourceFilename.flatMap(sourceURL) }
    func sourceURL(_ filename: String) -> URL? { repository.attachment(filename) ?? Bundle.main.url(forResource: filename, withExtension: nil) }
    func mutate(_ action: (inout AppSnapshot) throws -> Void) throws {
        guard var next = snapshot else { throw RevaError.invalid("Load or reset the demo first.") }
        try action(&next); try repository.save(next); snapshot = next
    }
    @discardableResult func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); return true } catch { errorMessage = error.localizedDescription; return false }
    }
    func resetDemo() throws {
        guard let url = Bundle.main.url(forResource: "seed", withExtension: "json") else { throw RevaError.invalid("The fictional demo dataset is missing from this build.") }
        let seed = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url)); try seed.validate(); try repository.save(seed)
        snapshot = seed; startupError = nil; notice = "Fictional demo restored."; serverRevision = 0; serverConflictRevision = nil
    }
    func save(_ record: MedicalRecord) throws {
        try mutate { data in
            guard let i = data.records.firstIndex(where: { $0.id == record.id }) else { data.records.append(record); return }
            let current = data.records[i]
            var revised = record
            // Only changes a brief can quote or select on advance the source version; notes and provider edits keep it.
            let affectsBriefs = revised.title != current.title || revised.date != current.date || revised.text != current.text || revised.tags != current.tags || revised.summary != current.summary || revised.status != current.status
            revised.version = affectsBriefs ? current.version + 1 : current.version
            data.records[i] = revised
        }
    }
    func deleteRecord(_ id: String) throws {
        try mutate { data in data.records.removeAll { $0.id == id }; for i in data.visits.indices { data.visits[i].pinnedRecordIDs.removeAll { $0 == id } } }
    }
    func save(_ visit: Visit) throws {
        var visit = visit
        visit.report?.questions = visit.questions; visit.report?.notes = visit.notes
        try mutate { data in if let i = data.visits.firstIndex(where: { $0.id == visit.id }) { data.visits[i] = visit } else { data.visits.append(visit) } }
    }
    func generateReport(_ id: String) throws {
        try mutate { data in guard let i = data.visits.firstIndex(where: { $0.id == id }) else { return }; let report = ReportEngine.generate(visit: data.visits[i], records: data.records); data.visits[i].questions = report.questions; data.visits[i].report = report }
    }
    func save(_ request: BookingRequest) throws {
        try BookingEngine.validate(request)
        try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == request.id }) { data.bookings[i] = request } else { data.bookings.append(request) } }
    }
    func runBooking(_ id: String) async {
        guard let request = booking(id), ["draft", "needsUser", "failed"].contains(request.status) else { return }
        guard perform({ try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }) { data.bookings[i].status = "queued" } } }) else { return }
        try? await Task.sleep(for: .seconds(0.7))
        guard perform({ try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }), data.bookings[i].status == "queued" { data.bookings[i].status = "calling" } } }) else { return }
        try? await Task.sleep(for: .seconds(1.3))
        perform { try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }), data.bookings[i].status == "calling" { data.bookings[i].status = request.scenario == "Clinic needs details" ? "needsUser" : request.scenario == "No answer" ? "failed" : "proposed" } } }
    }
    func confirmBooking(_ id: String) throws { try mutate { try BookingEngine.confirm(id: id, snapshot: &$0) } }
    func save(_ recording: VisitRecording) throws {
        try mutate { data in if let i = data.recordings.firstIndex(where: { $0.id == recording.id }) { data.recordings[i] = recording } else { data.recordings.append(recording) } }
    }
    func loadSample(visitID: String) throws -> String {
        guard let url = Bundle.main.url(forResource: "sample-transcript", withExtension: "json") else { throw RevaError.invalid("The sample transcript is missing.") }
        var sample = try JSONDecoder().decode(VisitRecording.self, from: Data(contentsOf: url))
        // The fictional conversation stays attached to its actual fixture visit, never the visit currently being recorded.
        if let existing = recordings.first(where: { $0.visitID == sample.visitID && $0.isSample }) { return existing.id }
        guard visit(sample.visitID) != nil else { throw RevaError.invalid("Restore the fictional demo to explore its sample visit.") }
        sample.id = UUID().uuidString; sample.audioFilename = nil; sample.isSample = true
        try save(sample); return sample.id
    }
    func saveMemory(recordingID: String, correctedSegmentTexts: [String: String]? = nil) throws {
        try mutate { data in
            guard let recordingIndex = data.recordings.firstIndex(where: { $0.id == recordingID }) else {
                throw RevaError.invalid("This recording is no longer available.")
            }
            var recording = data.recordings[recordingIndex]
            if let correctedSegmentTexts {
                let ids = recording.segments.map(\.id)
                guard !ids.isEmpty, Set(ids).count == ids.count, Set(ids) == Set(correctedSegmentTexts.keys) else {
                    throw RevaError.invalid("The source transcript changed. Close this editor and reopen it before correcting text.")
                }
                guard correctedSegmentTexts.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 20_000 }),
                      correctedSegmentTexts.values.reduce(0, { $0 + $1.count }) <= 200_000 else {
                    throw RevaError.invalid("Keep every transcript segment nonempty and below 20,000 characters, with at most 200,000 characters overall.")
                }
                for i in recording.segments.indices {
                    // Change only words: retain identity, speaker, start/end, audio, origin, and separate visit notes.
                    if let text = correctedSegmentTexts[recording.segments[i].id] { recording.segments[i].text = text }
                }
                data.recordings[recordingIndex] = recording
            }
            let id = "memory-" + recording.id
            let existingIndex = data.records.firstIndex(where: { $0.id == id })
                ?? data.records.firstIndex(where: { $0.sourceRecordingID == recording.id })
            // Editing a transcript updates an existing saved memory, but does not create an unrequested record.
            if correctedSegmentTexts != nil, existingIndex == nil { return }
            let fullText = recording.segments.map { "[\(RevaDate.duration($0.start))–\(RevaDate.duration($0.end))] \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
            let sourceText = fullText.isEmpty ? recording.summary : fullText
            guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RevaError.invalid("Add notes or a transcript before saving a visit memory.")
            }
            var record = existingIndex.map { data.records[$0] }
                ?? MedicalRecord(id: id, title: recording.title + " · memory", kind: "Recording",
                                 provider: data.visits.first(where: { $0.id == recording.visitID })?.provider ?? "Visit",
                                 date: String(recording.createdAt.prefix(10)), tags: ["visit memory"], text: "", summary: "")
            let previous = record
            record.text = sourceText
            record.summary = ReportEngine.localExcerpt(sourceText)
            let origin = recording.isSample ? "Fictional sample transcript. No matching audio." : "Saved visit memory. Live transcription is not configured."
            if correctedSegmentTexts == nil || existingIndex == nil {
                record.notes = origin + (recording.summary.isEmpty ? "" : "\n\nSeparate visit notes (not automatically changed with transcript corrections):\n" + recording.summary)
            }
            record.isDemo = recording.isSample
            record.sourceRecordingID = recording.id
            record.pageTexts = nil // Transcript timestamps identify the source; this is not a paginated document.
            if let existingIndex {
                if previous.text != record.text || previous.summary != record.summary { record.version = previous.version + 1 }
                data.records[existingIndex] = record
            } else { data.records.append(record) }
        }
        notice = correctedSegmentTexts == nil ? "Visit memory saved to Records." : "Transcript corrections saved. Any saved memory was updated; your separate notes were kept."
    }
    func client(url: String, token: String) throws -> ServerClient {
        guard let base = URL(string: url) else { throw RevaError.invalid("Enter a valid server URL.") }
        let identity = url + "|" + token
        if identity != serverIdentity { serverRevision = 0; serverConflictRevision = nil; serverIdentity = identity; serverStatus = "Not connected" }
        return try ServerClient(baseURL: base, token: token)
    }
    func sync(url: String, token: String, action: String) async {
        guard !isSyncing else { return }; isSyncing = true; defer { isSyncing = false }
        do {
            let client = try client(url: url, token: token)
            serverStatus = try await client.health()
            if action == "push", let snapshot {
                for record in snapshot.records { if let name = record.sourceFilename {
                    guard let url = sourceURL(name) else { throw RevaError.invalid("An original source is missing. Restore it before pushing.") }
                    try await client.uploadAttachment(id: ServerClient.attachmentID(for: name), filename: ServerClient.attachmentMetadataName(name), data: Data(contentsOf: url), type: ServerClient.uploadContentType(record.mimeType))
                } }
                for recording in snapshot.recordings { if let name = recording.audioFilename {
                    guard let url = sourceURL(name) else { throw RevaError.invalid("A recording file is missing. Restore it before pushing.") }
                    try await client.uploadAttachment(id: ServerClient.attachmentID(for: name), filename: ServerClient.attachmentMetadataName(name), data: Data(contentsOf: url), type: "audio/mp4")
                } }
                serverRevision = try await client.push(snapshot, revision: serverRevision); serverConflictRevision = nil; notice = "Local snapshot copied to server revision \(serverRevision)."
            } else if action == "pull" {
                let remote = try await client.pull()
                let names = remote.snapshot.records.compactMap(\.sourceFilename) + remote.snapshot.recordings.compactMap(\.audioFilename)
                // Download every attachment before replacing state. A failed transfer leaves local state untouched.
                var bytes: [String: Data] = [:]
                for name in Set(names) { bytes[name] = try await client.attachment(id: ServerClient.attachmentID(for: name)) }
                for (name, data) in bytes { _ = try repository.storeAttachment(data, filename: name) }
                try repository.save(remote.snapshot); snapshot = remote.snapshot; serverRevision = remote.revision; serverConflictRevision = nil; notice = "Server revision \(remote.revision) loaded."
            }
        } catch ServerFailure.conflict {
            do { let remote = try await client(url: url, token: token).pull(); serverConflictRevision = remote.revision }
            catch ServerFailure.empty(let revision) { serverConflictRevision = revision }
            catch { serverConflictRevision = nil }
            errorMessage = "The server changed. Your local snapshot is intact. Pull the server copy, or explicitly replace it with your local copy in Developer settings."
        } catch ServerFailure.empty(let revision) { serverRevision = revision; errorMessage = ServerFailure.empty(revision).localizedDescription }
        catch { errorMessage = error.localizedDescription; if action == "probe" { serverStatus = "Connection failed" } }
    }
}
