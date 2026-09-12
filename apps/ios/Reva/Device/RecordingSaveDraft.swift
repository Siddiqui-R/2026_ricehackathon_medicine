// Purpose: Retain finalized audio and stable recording metadata across a failed save.
// Inputs: The visit, a one-time audio finalizer and a recording persistence operation.
// Outputs: A saved recording ID or a retained pending recording and original file URL.
// Side effects: Invokes the supplied capture/persistence boundaries; never deletes original audio.

import Foundation

// MARK: - Finalize once and retry metadata persistence
// A failed persistence attempt retains the same UUID, timestamp, duration and filename for retry.
struct RecordingSaveDraft {
    private(set) var recording: VisitRecording?
    private(set) var audioURL: URL?

    mutating func save(
        visit: Visit, finishAudio: () throws -> (url: URL, duration: TimeInterval),
        persist: (VisitRecording) throws -> Void
    ) throws -> String {
        let pending: VisitRecording
        if let recording {
            pending = recording
        } else {
            let audio = try finishAudio()
            pending = VisitRecording(
                visitID: visit.id, title: visit.title + " · audio", duration: audio.duration,
                audioFilename: audio.url.lastPathComponent)
            audioURL = audio.url
            recording = pending
        }
        try persist(pending)
        recording = nil
        audioURL = nil
        return pending.id
    }
}
