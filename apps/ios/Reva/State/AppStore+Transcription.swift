// Purpose: Turn real saved audio into a reviewable transcript and existing memory update.
// Inputs: An existing non-sample recording ID with an available audio file.
// Outputs: Validated relative transcript segments and provider provenance.
// Side effects: Reads audio, calls the server and saves transcript/memory; original audio remains.

import Foundation

// MARK: - Saved audio transcription
// Reject sample/missing audio, then validate unique segment IDs and recording-relative bounds.
extension AppStore {
    func transcribeRecording(_ id: String) async {
        guard !isProviderBusy, recordingProcessingID != id else { return }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            try await processRecordingTranscript(id)
            notice = "Transcript saved. Review the words and speaker attribution before using it."
        } catch {
            guard context == providerContext else { return }
            errorMessage = error.localizedDescription
        }
    }

    // The background queue uses this throwing boundary without blocking unrelated UI work.
    func processRecordingTranscript(_ id: String, automatic: Bool = false) async throws {
        guard let original = recording(id), !original.isSample,
            let name = original.audioFilename, let url = sourceURL(name)
        else { throw RevaError.invalid("The saved original audio is unavailable.") }
        let context = providerContext
        let result = try await withProviderRequest {
            try await self.providerClient().transcribe(bytes: Data(contentsOf: url), filename: name)
        }
        try Task.checkCancellation()
        guard context == providerContext else { throw CancellationError() }
        guard var latest = recording(id), latest.audioFilename == original.audioFilename,
            latest.duration == original.duration, latest.createdAt == original.createdAt,
            latest.isSample == original.isSample, latest.segments == original.segments
        else {
            throw RevaError.invalid(
                "The recording or transcript changed. Your edits were kept; retry from the current recording."
            )
        }
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.segments.isEmpty,
            Set(result.segments.map(\.id)).count == result.segments.count,
            result.segments.allSatisfy({
                $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start
                    && $0.end <= original.duration + 5
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw RevaError.invalid(
                "The transcript contained invalid or missing timestamps. Your audio was kept.")
        }
        latest.segments = result.segments
        latest.transcriptionModel = result.model
        latest.status = automatic ? "processing-analyzing" : "transcribed"
        latest.clearAISummary()
        try saveRecordingWithExistingMemory(latest)
    }

}
