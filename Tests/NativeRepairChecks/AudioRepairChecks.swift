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
            let capture = AVAudioRecorder.lastCreated!
            // Normal notification delivery must still pause active capture and allow explicit resumption.
            for event in pauseEvents {
                NotificationCenter.default.post(event)
                await settleCallbacks()
                precondition(recorder.isPaused && recorder.errorMessage?.contains("paused") == true)
                recorder.resume()
                precondition(!recorder.isPaused && recorder.errorMessage == nil)
            }
            // A callback queued before finalization may reach the main actor after finalization fails.
            recorder.audioRecorderDidFinishRecording(capture, successfully: false)
            do {
                _ = try recorder.finish()
                preconditionFailure("Synthetic unusable recording was accepted")
            } catch {}
            precondition(recorder.finishFailed && recorder.isRecording && recorder.isPaused)
            precondition(recorder.errorMessage?.contains("Discard it and start a new recording") == true)
            let terminalMessage = recorder.errorMessage
            await settleCallbacks()
            precondition(
                recorder.errorMessage == terminalMessage, "Queued finish callback replaced terminal guidance")
            for event in pauseEvents + [Notification(name: AVAudioSession.mediaServicesWereResetNotification)]
            {
                NotificationCenter.default.post(event)
                await settleCallbacks()
                precondition(
                    recorder.errorMessage == terminalMessage, "Device event replaced terminal guidance")
            }
            for success in [false, true] {
                recorder.audioRecorderDidFinishRecording(capture, successfully: success)
                await settleCallbacks()
                precondition(
                    recorder.errorMessage == terminalMessage,
                    "Late finish callback replaced terminal guidance")
            }
            recorder.audioRecorderEncodeErrorDidOccur(capture, error: DeviceAudioError.invalidAudio)
            await settleCallbacks()
            precondition(
                recorder.errorMessage == terminalMessage, "Late encode callback replaced terminal guidance")
            precondition(recorder.finishFailed && recorder.isPaused)
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
            "PASS terminal recovery: queued/late recorder callbacks and device notifications preserve finalization guidance; normal event pauses still resume"
        )
        print(
            "PASS audio control: restarted capture can finish; later cancel preserves the finalized original")
        print(
            "LIMIT: device/codec boundaries are doubles; actual microphone, codec behavior, and native UI are not exercised"
        )
    }

    // MARK: - Real notification entry points and main-actor callback delivery
    static var pauseEvents: [Notification] {
        [
            Notification(name: UIApplication.didEnterBackgroundNotification),
            Notification(
                name: AVAudioSession.interruptionNotification,
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]),
            Notification(
                name: AVAudioSession.routeChangeNotification,
                userInfo: [
                    AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable
                        .rawValue
                ]),
        ]
    }

    @MainActor static func settleCallbacks() async {
        // Enqueue behind the callbacks and yield the actor so their production Tasks can reconcile state.
        await Task { @MainActor in await Task.yield() }.value
    }
}
