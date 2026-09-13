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
        guard !isProviderBusy, recordingProcessingID != id, recording(id) != nil else { return }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            try await processRecordingSummary(id)
            notice = "AI appointment summary saved. Review it against the transcript and recording."
        } catch {
            guard context == providerContext else { return }
            errorMessage = error.localizedDescription
        }
    }

    func processRecordingSummary(_ id: String) async throws {
        guard let original = recording(id), !original.segments.isEmpty,
            original.segments.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw RevaError.invalid("A complete saved transcript is required for the appointment summary.")
        }
        guard providerStatus?.gemini.configured == true else {
            throw RevaError.invalid("The summary service is not available yet.")
        }
        let context = providerContext
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
        guard context == providerContext else { throw CancellationError() }
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
            if correctedSegmentTexts != nil,
                let index = data.recordings.firstIndex(where: { $0.id == recordingID }),
                !data.recordings[index].isSample, data.recordings[index].audioFilename != nil,
                !data.recordings[index].hasAISummary
            {
                data.recordings[index].status = "processing-analyzing"
            }
        }
        if correctedSegmentTexts != nil {
            recordingProcessingErrors.removeValue(forKey: recordingID)
            considerRecordingProcessing()
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
        if existingIndex == nil {
            if let capturedAt = recording.capturedAt {
                record.date = RevaDate.day(RevaDate.parse(capturedAt), zone: RevaDate.defaultTimeZone)
                record.dateSource = "recorded"
            } else if let savedAt = recording.savedAt {
                record.date = RevaDate.day(RevaDate.parse(savedAt), zone: RevaDate.defaultTimeZone)
                record.dateSource = "added"
            }
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

// MARK: - Durable automatic recording processing
// A single app-owned task survives navigation, resumes pending stages on reopen, and never trusts live previews.
extension AppStore {
    static let pendingRecordingStates: Set<String> = [
        "processing-queued", "processing-transcribing", "processing-analyzing", "processing-retranscribing",
    ]
    var hasPendingRecordings: Bool {
        recordings.contains {
            !$0.isSample && $0.audioFilename != nil && Self.pendingRecordingStates.contains($0.status)
        }
    }
    func queueRecording(_ recording: VisitRecording) throws {
        guard !recording.isSample, let name = recording.audioFilename, sourceURL(name) != nil,
            recording.duration.isFinite, recording.duration > 0
        else { throw RevaError.invalid("Save a valid original audio recording first.") }
        var queued = recording
        queued.status = "processing-queued"
        queued.segments = []
        queued.clearAISummary()
        queued.savedAt = queued.savedAt ?? RevaDate.now
        try save(queued)
        notice = "Recording saved. Its transcript and summary are being prepared automatically."
        considerRecordingProcessing()
    }
    func stopRecordingProcessing(clearErrors: Bool = false) {
        recordingProcessingGeneration = UUID()
        recordingProcessingTask?.cancel()
        recordingProcessingTask = nil
        recordingProcessingID = nil
        if clearErrors { recordingProcessingErrors.removeAll() }
    }
    func recordingProcessingMessage(_ recording: VisitRecording) -> String? {
        if let failure = recordingProcessingErrors[recording.id] { return failure }
        switch recording.status {
        case "processing-complete": return "Transcript and summary ready."
        case "processing-failed", "processing-reprocess-failed":
            return "Processing could not finish. Your audio and completed steps are saved."
        case "processing-queued", "processing-transcribing", "processing-retranscribing",
            "processing-analyzing":
            if recording.segments.isEmpty || recording.status == "processing-retranscribing" {
                return providerStatus?.transcription.configured == true
                    ? "Preparing your final transcript automatically…"
                    : "Audio saved. Waiting for transcription service."
            }
            return providerStatus?.gemini.configured == true
                ? "Preparing your appointment summary automatically…"
                : "Transcript saved. Waiting for summary service."
        default: return nil
        }
    }
    func retryRecordingProcessing(_ id: String, reprocess: Bool = false) {
        guard recordingProcessingID != id, let original = recording(id), !original.isSample,
            original.audioFilename != nil
        else { return }
        recordingProcessingErrors.removeValue(forKey: id)
        perform {
            try mutate { data in
                guard let index = data.recordings.firstIndex(where: { $0.id == id }) else { return }
                data.recordings[index].status =
                    reprocess
                        || ["processing-reprocess-failed", "processing-retranscribing"].contains(
                            original.status)
                    ? "processing-retranscribing" : "processing-queued"
            }
        }
        considerRecordingProcessing()
    }
    func considerRecordingProcessing() {
        guard backgroundActive, !needsSignIn, !providerWorkSuspended, !isProviderBusy,
            recordingProcessingTask == nil
        else { return }
        guard
            let next = recordings.first(where: {
                guard !$0.isSample, $0.audioFilename != nil, Self.pendingRecordingStates.contains($0.status),
                    recordingProcessingErrors[$0.id] == nil
                else { return false }
                return $0.segments.isEmpty || $0.status == "processing-retranscribing"
                    ? providerStatus?.transcription.configured == true
                    : $0.hasAISummary || providerStatus?.gemini.configured == true
            })
        else { return }
        let generation = UUID()
        recordingProcessingGeneration = generation
        recordingProcessingID = next.id
        let context = providerContext
        recordingProcessingTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueuedRecording(next.id, context: context, generation: generation)
        }
    }
    private func processQueuedRecording(_ id: String, context: ProviderContext, generation: UUID) async {
        func valid() -> Bool {
            !Task.isCancelled && backgroundActive && !needsSignIn && !providerWorkSuspended
                && context == providerContext
                && generation == recordingProcessingGeneration
        }
        var rebuilding = false
        defer {
            if generation == recordingProcessingGeneration {
                recordingProcessingTask = nil
                recordingProcessingID = nil
                considerRecordingProcessing()
            }
        }
        do {
            guard valid(), let original = recording(id), Self.pendingRecordingStates.contains(original.status)
            else { return }
            rebuilding = original.status == "processing-retranscribing"
            if original.segments.isEmpty || rebuilding {
                try mutate { data in
                    guard valid(), let index = data.recordings.firstIndex(where: { $0.id == id }) else {
                        throw CancellationError()
                    }
                    data.recordings[index].status =
                        rebuilding ? "processing-retranscribing" : "processing-transcribing"
                }
                try await processRecordingTranscript(id, automatic: true)
                rebuilding = false
            }
            guard valid(), let transcribed = recording(id) else { return }
            guard transcribed.hasAISummary || providerStatus?.gemini.configured == true else { return }
            try mutate { data in
                guard valid(), let index = data.recordings.firstIndex(where: { $0.id == id }) else {
                    throw CancellationError()
                }
                data.recordings[index].status = "processing-analyzing"
            }
            if !transcribed.hasAISummary { try await processRecordingSummary(id) }
            guard valid() else { return }
            try mutate { data in
                guard valid(), let index = data.recordings.firstIndex(where: { $0.id == id }),
                    data.recordings[index].hasAISummary
                else { throw CancellationError() }
                try Self.reconcileMemory(recordingID: id, preserveNotes: true, data: &data)
                data.recordings[index].status = "processing-complete"
            }
        } catch {
            guard valid(), recording(id) != nil else { return }
            recordingProcessingErrors[id] =
                error is CancellationError
                ? "Processing stopped. Your audio and completed steps are saved."
                : error.localizedDescription
            if !(error is CancellationError) {
                try? mutate { data in
                    guard valid(), let index = data.recordings.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    data.recordings[index].status =
                        rebuilding ? "processing-reprocess-failed" : "processing-failed"
                }
            }
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
        try store.queueRecording(recording)
        self.recording = nil
        audioURL = nil
        return recording.id
    }
}
