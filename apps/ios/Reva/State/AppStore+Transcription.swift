// Purpose: Turn real saved audio into a reviewable transcript and existing memory update.
// Inputs: An existing non-sample recording ID with an available audio file.
// Outputs: Validated relative transcript segments and provider provenance.
// Side effects: Reads audio, calls the server and saves transcript/memory; original audio remains.

import Foundation

// MARK: - Saved audio transcription
// Reject sample/missing audio, then validate unique segment IDs and recording-relative bounds.
extension AppStore {
    func transcribeRecording(_ id: String) async {
        guard !isProviderBusy, let original = recording(id), !original.isSample,
            let name = original.audioFilename, let url = sourceURL(name)
        else { return }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            let result = try await providerClient().transcribe(bytes: Data(contentsOf: url), filename: name)
            guard context == providerContext else { return }
            try Task.checkCancellation()
            guard var latest = recording(id), latest.audioFilename == original.audioFilename,
                latest.segments == original.segments
            else {
                throw RevaError.invalid(
                    "The recording or transcript changed. Your edits were kept; retry from the current recording."
                )
            }
            guard !result.text.isEmpty, !result.segments.isEmpty,
                Set(result.segments.map(\.id)).count == result.segments.count,
                result.segments.allSatisfy({
                    $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start
                        && $0.end <= original.duration + 5 && !$0.text.isEmpty
                })
            else {
                throw RevaError.invalid(
                    "The transcript contained invalid or missing timestamps. Your audio was kept.")
            }
            latest.segments = result.segments
            latest.transcriptionModel = result.model
            latest.status = "transcribed"
            try save(latest)
            if records.contains(where: { $0.sourceRecordingID == id || $0.id == "memory-" + id }) {
                try saveMemory(recordingID: id)
            }
            notice = "Transcript saved. Review the words and speaker attribution before using it."
        } catch {
            guard context == providerContext else { return }
            errorMessage = error.localizedDescription
        }
    }
}
