// Purpose: Exercise production AudioRecorder failure transitions with controlled device boundaries.
// Inputs: Synthetic recorder and decoder, and a temporary draft directory.
// Outputs: Assertions for terminal finish failure, accurate guidance, cleanup, and normal success.
// Side effects: Production recorder creates/deletes synthetic temporary drafts. No device access.

import Foundation

// MARK: - Actual recorder lifecycle with deterministic codec outcomes
@main struct AudioRepairChecks {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("audio")
        for decodeFailure in [false, true] {
            AVAudioPlayer.decodedDuration = 0.05
            AVAudioPlayer.failsDecoding = decodeFailure
            let recorder = AudioRecorder()
            try await recorder.start(directory: directory)
            let draft = recorder.audioURL!
            do {
                _ = try recorder.finish()
                preconditionFailure("Synthetic unusable recording was accepted")
            } catch {}
            precondition(recorder.finishFailed && recorder.isRecording && recorder.isPaused)
            precondition(recorder.errorMessage?.contains("Discard it and start a new recording") == true)
            recorder.resume()
            precondition(recorder.isPaused && recorder.errorMessage?.contains("Discard it") == true)
            precondition(recorder.errorMessage?.contains("one-hour") == false)
            precondition(
                FileManager.default.fileExists(atPath: draft.path),
                "Failed finalization must keep owned draft until explicit discard")
            recorder.cancel()
            precondition(
                !recorder.isRecording && !recorder.isPaused && !recorder.finishFailed
                    && recorder.audioURL == nil && recorder.errorMessage == nil)
            precondition(!FileManager.default.fileExists(atPath: draft.path))
            AVAudioPlayer.decodedDuration = 2
            AVAudioPlayer.failsDecoding = false
            try await recorder.start(directory: directory)
            let saved = try recorder.finish()
            precondition(!recorder.isRecording && !recorder.finishFailed && recorder.elapsed == 2)
            recorder.cancel()
            precondition(
                FileManager.default.fileExists(atPath: saved.path),
                "Cancel after successful handoff must preserve finalized original")
        }
        print(
            "PASS RVA-05-002: production finish rejects short/undecodable audio, exposes terminal recovery, gives accurate resume guidance, and resets on discard"
        )
        print(
            "PASS audio control: restarted capture can finish; later cancel preserves the finalized original")
        print(
            "LIMIT: device/codec boundaries are doubles; actual microphone, codec behavior, and native UI are not exercised"
        )
    }
}
