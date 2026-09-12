// Purpose: Save recordings, load fictional samples and maintain transcript-backed memories.
// Inputs: Recording edits, fixture access or reviewed segment corrections.
// Outputs: Stored recordings and stable source-linked memory records.
// Side effects: Reads bundled sample JSON and writes snapshot changes; no audio generation or AI.

import Foundation

// MARK: - Recording metadata persistence
// Keep recording identity and its visit relationship in the main snapshot.

extension AppStore {
    func save(_ recording: VisitRecording) throws {
        try mutate { data in
            if let i = data.recordings.firstIndex(where: { $0.id == recording.id }) {
                data.recordings[i] = recording
            } else {
                data.recordings.append(recording)
            }
        }
    }
    // MARK: - Separate visit notes
    // Change only notes on the current recording; a transcript arriving during editing must survive.
    func updateRecordingNotes(id: String, summary: String) throws {
        try mutate { data in
            guard let i = data.recordings.firstIndex(where: { $0.id == id }) else {
                throw RevaError.invalid("This recording is no longer available. Close this editor.")
            }
            data.recordings[i].summary = summary
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
            guard let recordingIndex = data.recordings.firstIndex(where: { $0.id == recordingID }) else {
                throw RevaError.invalid("This recording is no longer available.")
            }
            var recording = data.recordings[recordingIndex]
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
                data.recordings[recordingIndex] = recording
            }
            let id = "memory-" + recording.id
            let existingIndex =
                data.records.firstIndex(where: { $0.id == id })
                ?? data.records.firstIndex(where: { $0.sourceRecordingID == recording.id })
            // Editing a transcript updates an existing saved memory, but does not create an unrequested record.
            if correctedSegmentTexts != nil, existingIndex == nil { return }
            let fullText = recording.segments.map {
                "[\(RevaDate.duration($0.start))–\(RevaDate.duration($0.end))] \($0.speaker): \($0.text)"
            }.joined(separator: "\n\n")
            let sourceText = fullText.isEmpty ? recording.summary : fullText
            guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RevaError.invalid("Add notes or a transcript before saving a visit memory.")
            }
            var record =
                existingIndex.map { data.records[$0] }
                ?? MedicalRecord(
                    id: id, title: recording.title + " · memory", kind: "Recording",
                    provider: data.visits.first(where: { $0.id == recording.visitID })?.provider ?? "Visit",
                    date: String(recording.createdAt.prefix(10)), tags: ["visit memory"], text: "",
                    summary: "")
            let previous = record
            record.text = sourceText
            record.summary = ReportEngine.localExcerpt(sourceText)
            record.summaryModel = nil
            let origin =
                recording.isSample
                ? "Fictional sample transcript. No matching audio."
                : recording.transcriptionModel.map {
                    "Transcript generated by " + $0 + "; review for accuracy."
                } ?? "Saved visit memory from user-entered notes."
            if correctedSegmentTexts == nil || existingIndex == nil {
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
                if previous.text != record.text || previous.summary != record.summary {
                    record.version = previous.version + 1
                }
                data.records[existingIndex] = record
            } else {
                data.records.append(record)
            }
        }
        notice =
            correctedSegmentTexts == nil
            ? "Visit memory saved to Records."
            : "Transcript corrections saved. Any saved memory was updated; your separate notes were kept."
    }

}
