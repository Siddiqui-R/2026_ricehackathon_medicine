// Purpose: Save recordings, load fictional samples and maintain transcript-backed memories.
// Inputs: Recording edits, fixture access or reviewed segment corrections.
// Outputs: Stored recordings and stable source-linked memory records.
// Side effects: Reads sample JSON, requests connected transcript summaries, and writes snapshot changes.

import Foundation

// MARK: - Recording metadata persistence
// Keep recording identity and its visit relationship in the main snapshot.
extension AppStore {
    func save(_ recording: VisitRecording) throws {
        try mutate { data in
            if let i = data.recordings.firstIndex(where: { $0.id == recording.id }) {
                var next = recording
                if next.segments != data.recordings[i].segments {
                    next.clearAISummary()
                }
                data.recordings[i] = next
            } else {
                data.recordings.append(recording)
            }
        }
    }

    // MARK: - Appointment transcript summary
    // Publish only against the same recording and exact transcript; unrelated notes stay authoritative.
    func summarizeRecording(_ id: String) async {
        guard !isProviderBusy, let original = recording(id) else { return }
        guard providerStatus?.gemini.configured == true else {
            errorMessage = "Connect Gemini in Profile & settings to summarize this appointment."
            return
        }
        guard !original.segments.isEmpty,
            original.segments.contains(where: {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            errorMessage = "Transcribe the appointment before generating its summary."
            return
        }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            var source = MedicalRecord(
                id: original.id, title: original.title, kind: "Recording", provider: "",
                date: original.createdAt, text: original.transcriptText, summary: "")
            if let capturedAt = original.capturedAt {
                source.date = capturedAt
                source.dateSource = "recorded"
            } else if let savedAt = original.savedAt {
                source.date = RevaDate.day(RevaDate.parse(savedAt), zone: RevaDate.defaultTimeZone)
                source.dateSource = "added"
            }
            let result = try await withProviderRequest { try await self.providerClient().summarize(source) }
            guard context == providerContext else { return }
            try Task.checkCancellation()
            guard var latest = recording(id), latest.visitID == original.visitID,
                latest.createdAt == original.createdAt, latest.title == original.title,
                latest.capturedAt == original.capturedAt, latest.savedAt == original.savedAt,
                latest.audioFilename == original.audioFilename, latest.duration == original.duration,
                latest.isSample == original.isSample, latest.segments == original.segments
            else {
                throw RevaError.invalid(
                    "The recording or transcript changed while summarizing. Your edits were kept; summarize the current transcript again."
                )
            }
            guard !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !result.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw RevaError.invalid(
                    "No appointment summary was returned. Your transcript and notes were kept.")
            }
            latest.aiSummary = result.summary
            latest.aiSummaryModel = result.model
            latest.aiSummaryGeneratedAt = RevaDate.now
            try saveRecordingWithExistingMemory(latest)
            notice = "AI appointment summary saved. Review it against the transcript and recording."
        } catch {
            guard context == providerContext else { return }
            errorMessage = error.localizedDescription
        }
    }
    // MARK: - Separate notes merge
    // Resolve the current recording by identity; saving notes cannot replace a newer transcript or audio link.
    func saveRecordingNotes(_ notes: String, recordingID: String) throws {
        try mutate { data in
            guard let index = data.recordings.firstIndex(where: { $0.id == recordingID }) else {
                throw RevaError.invalid("This recording is no longer available.")
            }
            data.recordings[index].summary = notes
        }
    }

    // MARK: - Fictional transcript access
    // The fixture remains attached to its own demo visit and never supplies transcript text for new audio.
    func loadSample(visitID: String) throws -> String {
        guard let url = Bundle.main.url(forResource: "sample-transcript", withExtension: "json") else {
            throw RevaError.invalid("The sample transcript is missing.")
        }
        var sample = try JSONDecoder().decode(VisitRecording.self, from: Data(contentsOf: url))
        // The fictional conversation stays attached to its actual fixture visit, never the visit currently being recorded.
        if let existing = recordings.first(where: { $0.visitID == sample.visitID && $0.isSample }) {
            return existing.id
        }
        guard visit(sample.visitID) != nil else {
            throw RevaError.invalid("Restore the fictional demo to explore its sample visit.")
        }
        sample.id = UUID().uuidString
        sample.audioFilename = nil
        sample.isSample = true
        try save(sample)
        return sample.id
    }
    // MARK: - Transcript and memory reconciliation
    // Apply reviewed words by segment ID, preserve timestamps/notes, and update one source-linked record.
    func saveMemory(recordingID: String, correctedSegmentTexts: [String: String]? = nil) throws {
        try mutate { data in
            try Self.reconcileMemory(
                recordingID: recordingID, correctedSegmentTexts: correctedSegmentTexts, data: &data)
        }
        notice =
            correctedSegmentTexts == nil
            ? "Visit memory saved to Records."
            : "Transcript corrections saved. Any saved memory was updated; your separate notes were kept."
    }

    // MARK: - Atomic provider publication
    // Derived changes and an existing memory commit together without replacing separately edited notes.
    func saveRecordingWithExistingMemory(_ recording: VisitRecording) throws {
        try mutate { data in
            guard let index = data.recordings.firstIndex(where: { $0.id == recording.id }) else {
                throw RevaError.invalid("This recording is no longer available.")
            }
            var next = recording
            if next.segments != data.recordings[index].segments { next.clearAISummary() }
            data.recordings[index] = next
            try Self.reconcileMemory(
                recordingID: next.id, createIfMissing: false, preserveNotes: true, data: &data)
        }
    }

    // MARK: - Transcript-backed memory mutation
    // Reuse source reconciliation for explicit saves, corrections, and atomic provider publication.
    private static func reconcileMemory(
        recordingID: String, correctedSegmentTexts: [String: String]? = nil,
        createIfMissing: Bool = true, preserveNotes: Bool = false, data: inout AppSnapshot
    ) throws {
        guard let recordingIndex = data.recordings.firstIndex(where: { $0.id == recordingID }) else {
            throw RevaError.invalid("This recording is no longer available.")
        }
        var recording = data.recordings[recordingIndex]
        let previousSegments = recording.segments
        if let correctedSegmentTexts {
            let ids = recording.segments.map(\.id)
            guard !ids.isEmpty, Set(ids).count == ids.count, Set(ids) == Set(correctedSegmentTexts.keys)
            else {
                throw RevaError.invalid(
                    "The source transcript changed. Close this editor and reopen it before correcting text."
                )
            }
            guard
                correctedSegmentTexts.values.allSatisfy({
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 20_000
                }),
                correctedSegmentTexts.values.reduce(0, { $0 + $1.count }) <= 200_000
            else {
                throw RevaError.invalid(
                    "Keep every transcript segment nonempty and below 20,000 characters, with at most 200,000 characters overall."
                )
            }
            for i in recording.segments.indices {
                // Change only words: retain identity, speaker, start/end, audio, origin, and separate visit notes.
                if let text = correctedSegmentTexts[recording.segments[i].id] {
                    recording.segments[i].text = text
                }
            }
            if recording.segments != previousSegments { recording.clearAISummary() }
            data.recordings[recordingIndex] = recording
        }
        let id = "memory-" + recording.id
        let existingIndex =
            data.records.firstIndex(where: { $0.id == id })
            ?? data.records.firstIndex(where: { $0.sourceRecordingID == recording.id })
        // Editing a transcript updates an existing saved memory, but does not create an unrequested record.
        if (correctedSegmentTexts != nil || !createIfMissing), existingIndex == nil { return }
        let fullText = recording.transcriptText
        let sourceText = fullText.isEmpty ? recording.summary : fullText
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RevaError.invalid("Add notes or a transcript before saving a visit memory.")
        }
        var record =
            existingIndex.map { data.records[$0] }
            ?? MedicalRecord(
                id: id, title: recording.title + " · memory", kind: "Recording",
                provider: data.visits.first(where: { $0.id == recording.visitID })?.provider ?? "Visit",
                date: RevaDate.day(RevaDate.parse(recording.createdAt), zone: RevaDate.defaultTimeZone),
                tags: ["visit memory"], text: "",
                summary: "")
        let previous = record
        record.text = sourceText
        record.summary =
            recording.hasAISummary ? recording.aiSummary! : ReportEngine.localExcerpt(sourceText)
        record.summaryModel = recording.hasAISummary ? recording.aiSummaryModel : nil
        record.summaryGeneratedAt = recording.hasAISummary ? recording.aiSummaryGeneratedAt : nil
        if let capturedAt = recording.capturedAt {
            record.date = RevaDate.day(RevaDate.parse(capturedAt), zone: RevaDate.defaultTimeZone)
            record.dateSource = "recorded"
        } else if let savedAt = recording.savedAt {
            record.date = RevaDate.day(RevaDate.parse(savedAt), zone: RevaDate.defaultTimeZone)
            record.dateSource = "added"
        }
        let origin =
            recording.isSample
            ? "Fictional sample transcript. No matching audio."
            : recording.transcriptionModel.map {
                "Transcript generated by " + $0 + "; review for accuracy."
            } ?? "Saved visit memory from user-entered notes."
        if existingIndex == nil || (!preserveNotes && correctedSegmentTexts == nil) {
            record.notes =
                origin
                + (recording.summary.isEmpty
                    ? ""
                    : "\n\nSeparate visit notes (not automatically changed with transcript corrections):\n"
                        + recording.summary)
        }
        record.isDemo = recording.isSample
        record.sourceRecordingID = recording.id
        // Transcript timestamps identify the source; this is not a paginated document.
        record.pageTexts = nil
        if let existingIndex {
            if previous.text != record.text || previous.summary != record.summary
                || previous.summaryModel != record.summaryModel
                || previous.date != record.date || previous.dateSource != record.dateSource
            {
                record.version = previous.version + 1
            }
            data.records[existingIndex] = record
        } else {
            data.records.append(record)
        }
    }

}

// MARK: - Finalized recording save draft
// Keep the same metadata and audio reference across failed writes; only a successful save clears the draft.
@MainActor struct RecordingSaveDraft {
    private(set) var recording: VisitRecording?
    private(set) var audioURL: URL?

    mutating func retain(_ recording: VisitRecording, audioURL: URL) {
        self.recording = recording
        self.audioURL = audioURL
    }

    mutating func save(to store: AppStore) throws -> String {
        guard let recording else { throw RevaError.invalid("There is no finished recording to save.") }
        try store.save(recording)
        self.recording = nil
        audioURL = nil
        return recording.id
    }
}
