// Purpose: Own microphone recording and local playback through one coordinated audio session.
// Inputs: User consent flow, local file URLs and AVFoundation/foreground notifications.
// Outputs: Observable capture/playback state and a validated original audio file.
// Side effects: Microphone permission, audio-session activation, draft file writes/deletion and timed tasks.

import AVFoundation
import Combine
import UIKit

// MARK: - Audio adapter failures
// Expose actionable permission, availability and original-file errors to the recording UI.
enum DeviceAudioError: LocalizedError {
    case permissionDenied, unavailableInput, busy, invalidDirectory, startFailed, noRecording, emptyRecording,
        invalidAudio

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is off. Enable it for Reva in Settings to record a visit."
        case .unavailableInput:
            return "No microphone input is available. Connect a microphone or try on your iPhone."
        case .busy: return "Pause the other audio session before starting this one."
        case .invalidDirectory: return "The recording folder is unavailable. Please try saving again."
        case .startFailed: return "Recording could not start. Check microphone access and try again."
        case .noRecording: return "There is no recording to save. Start recording first."
        case .emptyRecording: return "No usable audio was captured. Record a little longer and try again."
        case .invalidAudio: return "This audio file could not be played. It may be missing or damaged."
        }
    }
}

/// Ownership prevents a paused or dismissed controller from deactivating another one's audio.
// MARK: - Shared audio-session ownership
// Only the current owner may deactivate the session; recording and playback coordinate this resource.
@MainActor
private final class DeviceAudioSession {
    static let shared = DeviceAudioSession()
    private var owner: UUID?

    func activate(owner newOwner: UUID, recording: Bool) throws {
        guard owner == nil || owner == newOwner else { throw DeviceAudioError.busy }
        let session = AVAudioSession.sharedInstance()
        if recording {
            try session.setCategory(
                .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        } else {
            try session.setCategory(.playback, mode: .spokenAudio)
        }
        do {
            try session.setActive(true)
            owner = newOwner
        } catch {
            if owner == newOwner { owner = nil }
            throw error
        }
    }

    func release(owner oldOwner: UUID) {
        guard owner == oldOwner else { return }
        owner = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Microphone capture lifecycle
// Own a unique draft and one-hour capture limit; background/interruption events pause rather than resume silently.
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    /// True while a recording session exists, including when paused.
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var audioURL: URL?
    @Published private(set) var errorMessage: String?

    static let maximumDuration: TimeInterval = 60 * 60
    private var recorder: AVAudioRecorder?
    private let sessionID = UUID()
    private var ticker: Task<Void, Never>?
    private var startID: UUID?
    private var ownedDraftURL: URL?
    private var reachedEnd = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(mediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    deinit {
        ticker?.cancel()
        NotificationCenter.default.removeObserver(self)
        let id = sessionID
        Task { @MainActor in DeviceAudioSession.shared.release(owner: id) }
    }

    // MARK: - Capture start and permission
    // Track the pending start identity across permission awaits and retain only this recorder's draft.
    func start(directory: URL) async throws {
        guard !isRecording, recorder == nil, startID == nil else { throw DeviceAudioError.busy }
        guard directory.isFileURL else { throw DeviceAudioError.invalidDirectory }
        let attempt = UUID()
        startID = attempt
        errorMessage = nil
        defer { if startID == attempt { startID = nil } }
        do {
            let granted = await AVAudioApplication.requestRecordPermission()
            try Task.checkCancellation()
            guard startID == attempt else { throw CancellationError() }
            guard granted else { throw DeviceAudioError.permissionDenied }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let properties = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard properties.isDirectory == true, properties.isSymbolicLink != true else {
                throw DeviceAudioError.invalidDirectory
            }
            try DeviceAudioSession.shared.activate(owner: sessionID, recording: true)
            guard AVAudioSession.sharedInstance().isInputAvailable else {
                throw DeviceAudioError.unavailableInput
            }
            let url = directory.appendingPathComponent(
                "recording-\(UUID().uuidString).m4a", isDirectory: false)
            ownedDraftURL = url
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let capture = try AVAudioRecorder(url: url, settings: settings)
            capture.delegate = self
            guard capture.prepareToRecord(), capture.record(forDuration: Self.maximumDuration) else {
                throw DeviceAudioError.startFailed
            }
            recorder = capture
            audioURL = url
            elapsed = 0
            reachedEnd = false
            isRecording = true
            isPaused = false
            beginTicker()
        } catch {
            if startID == attempt {
                cleanUpDraft()
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
            throw error
        }
    }

    // MARK: - Capture pause and resume
    // Keep captured bytes while releasing session ownership; resume requires a still-valid recorder.
    func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        elapsed = max(elapsed, recorder.currentTime)
        recorder.pause()
        isPaused = true
        ticker?.cancel()
        ticker = nil
        DeviceAudioSession.shared.release(owner: sessionID)
    }

    func resume() {
        guard isRecording, isPaused, let recorder else { return }
        guard !reachedEnd, elapsed < Self.maximumDuration else {
            errorMessage =
                "The one-hour recording limit was reached. Save this recording before starting another."
            return
        }
        do {
            try DeviceAudioSession.shared.activate(owner: sessionID, recording: true)
            guard AVAudioSession.sharedInstance().isInputAvailable else {
                throw DeviceAudioError.unavailableInput
            }
            guard recorder.record(forDuration: Self.maximumDuration - elapsed) else {
                throw DeviceAudioError.startFailed
            }
            isPaused = false
            errorMessage = nil
            beginTicker()
        } catch {
            DeviceAudioSession.shared.release(owner: sessionID)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Validate and hand off original audio
    // Return a nonempty playable original file; mark it committed so cleanup does not delete saved audio.
    func finish() throws -> URL {
        guard let recorder, let url = ownedDraftURL else { throw DeviceAudioError.noRecording }
        elapsed = max(elapsed, recorder.currentTime)
        recorder.delegate = nil
        recorder.stop()
        ticker?.cancel()
        ticker = nil
        isPaused = true
        reachedEnd = true
        DeviceAudioSession.shared.release(owner: sessionID)
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let verification = try AVAudioPlayer(contentsOf: url)
            guard size > 0, verification.duration > 0.1 else { throw DeviceAudioError.emptyRecording }
            elapsed = verification.duration
            self.recorder = nil
            ownedDraftURL = nil  // ownership transfers to caller; cancel cannot delete a saved recording
            isRecording = false
            isPaused = false
            errorMessage = nil
            audioURL = url
            return url
        } catch {
            errorMessage = "The recording could not be saved: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Draft cleanup
    // Cancel pending work and remove only the owned uncommitted draft.
    func cancel() {
        startID = nil
        cleanUpDraft()
        elapsed = 0
        audioURL = nil
        errorMessage = nil
    }

    private func cleanUpDraft() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        ticker?.cancel()
        ticker = nil
        if let ownedDraftURL { try? FileManager.default.removeItem(at: ownedDraftURL) }
        ownedDraftURL = nil
        isRecording = false
        isPaused = false
        reachedEnd = false
        audioURL = nil
        DeviceAudioSession.shared.release(owner: sessionID)
    }

    // MARK: - Capture progress and duration bound
    // A cancellable 200 ms task stops on cancellation/pause/missing recorder and enforces maximumDuration.
    private func beginTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self, let recorder = self.recorder, self.isRecording, !self.isPaused else { return }
                self.elapsed = max(self.elapsed, recorder.currentTime)
                if self.elapsed >= Self.maximumDuration {
                    self.pause()
                    self.reachedEnd = true
                    self.errorMessage =
                        "The one-hour recording limit was reached. Save this recording before starting another."
                }
            }
        }
    }

    private func pauseForEvent(_ message: String) {
        guard isRecording else { return }
        pause()
        errorMessage = message
    }

    // MARK: - Capture interruption callbacks
    // Hop back to the main actor before state changes; never automatically resume after a device event.
    @objc nonisolated private func interrupted(_ notification: Notification) {
        let began =
            (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
            == AVAudioSession.InterruptionType.began.rawValue
        if began {
            Task { @MainActor [weak self] in
                self?.pauseForEvent(
                    "Recording paused for an audio interruption. Resume when ready, or save what was captured."
                )
            }
        }
    }

    @objc nonisolated private func routeChanged(_ notification: Notification) {
        let removed =
            (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        if removed {
            Task { @MainActor [weak self] in
                self?.pauseForEvent(
                    "Recording paused because an audio device disconnected. Check the microphone before resuming."
                )
            }
        }
    }

    @objc nonisolated private func enteredBackground() {
        Task { @MainActor [weak self] in
            self?.pauseForEvent(
                "Recording paused when Reva left the screen. Return to Reva and resume when ready.")
        }
    }

    @objc nonisolated private func mediaServicesReset() {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.pauseForEvent(
                "Audio services restarted. Save what was captured, then start a new recording.")
            self.reachedEnd = true
        }
    }

    // MARK: - Recorder delegate reconciliation
    // Ignore callbacks from replaced recorder instances and keep recoverable captured audio.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity else { return }
            self.elapsed = max(self.elapsed, current.currentTime)
            self.isPaused = true
            self.reachedEnd = true
            self.ticker?.cancel()
            self.ticker = nil
            DeviceAudioSession.shared.release(owner: self.sessionID)
            self.errorMessage =
                flag
                ? "Recording stopped. Save the captured audio before starting another recording."
                : "Recording stopped unexpectedly. Try saving the captured audio before starting again."
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identity = ObjectIdentifier(recorder)
        let message = error?.localizedDescription ?? "An audio encoding error occurred."
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity else { return }
            self.pauseForEvent("\(message) Try saving what was captured.")
            self.reachedEnd = true
        }
    }
}

// MARK: - Original audio playback
// Load only valid local audio; coordinate session ownership and publish recording-relative position.
@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?
    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private let sessionID = UUID()
    private var ticker: Task<Void, Never>?

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(mediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    deinit {
        ticker?.cancel()
        NotificationCenter.default.removeObserver(self)
        let id = sessionID
        Task { @MainActor in DeviceAudioSession.shared.release(owner: id) }
    }

    // MARK: - Playback start
    // Validate the file/player and activate the shared session; failed start publishes an error and pauses.
    func play(url: URL) throws {
        do {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                throw DeviceAudioError.invalidAudio
            }
            if loadedURL != url || player == nil {
                stop()
                let audio = try AVAudioPlayer(contentsOf: url)
                guard audio.duration.isFinite, audio.duration > 0, audio.prepareToPlay() else {
                    throw DeviceAudioError.invalidAudio
                }
                audio.delegate = self
                player = audio
                loadedURL = url
                duration = audio.duration
                currentTime = 0
            }
            guard let player else { throw DeviceAudioError.invalidAudio }
            try DeviceAudioSession.shared.activate(owner: sessionID, recording: false)
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else { throw DeviceAudioError.invalidAudio }
            isPlaying = true
            errorMessage = nil
            beginTicker()
        } catch {
            pause()
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Playback pause and cleanup
    // Release only this player's session and cancel progress work when playback stops.
    func pause() {
        player?.pause()
        if let player { currentTime = player.currentTime }
        isPlaying = false
        ticker?.cancel()
        ticker = nil
        DeviceAudioSession.shared.release(owner: sessionID)
    }

    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        ticker?.cancel()
        ticker = nil
        DeviceAudioSession.shared.release(owner: sessionID)
    }

    // MARK: - Clamped seeking
    // Reject nonfinite positions and clamp movement to the loaded audio duration.
    func seek(to time: TimeInterval) {
        guard let player, time.isFinite else { return }
        let target = min(max(0, time), player.duration)
        player.currentTime = target
        currentTime = target
        if target >= player.duration, isPlaying {
            pause()
            currentTime = duration
        }
    }

    // MARK: - Playback progress task
    // This lifecycle loop exits when cancelled, stopped or detached from its player.
    private func beginTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self, let player = self.player, self.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    // MARK: - Playback interruption callbacks
    // Dispatch device events to the main actor and pause; resumption remains a user action.
    @objc nonisolated private func interrupted(_ notification: Notification) {
        let began =
            (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
            == AVAudioSession.InterruptionType.began.rawValue
        if began { Task { @MainActor [weak self] in self?.pause() } }
    }

    @objc nonisolated private func routeChanged(_ notification: Notification) {
        let removed =
            (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        if removed { Task { @MainActor [weak self] in self?.pause() } }
    }

    @objc nonisolated private func enteredBackground() {
        Task { @MainActor [weak self] in self?.pause() }
    }

    @objc nonisolated private func mediaServicesReset() {
        Task { @MainActor [weak self] in
            self?.stop()
            self?.errorMessage = "Audio services restarted. Start playback again when ready."
        }
    }

    // MARK: - Player delegate reconciliation
    // Ignore stale player callbacks and preserve the last valid playhead on failure.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.pause()
            self.currentTime = flag ? self.duration : current.currentTime
            if flag {
                current.currentTime = current.duration
            } else {
                self.errorMessage = "Playback stopped before the audio finished."
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "Audio could not be decoded."
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.pause()
            self.errorMessage = message
        }
    }
}
