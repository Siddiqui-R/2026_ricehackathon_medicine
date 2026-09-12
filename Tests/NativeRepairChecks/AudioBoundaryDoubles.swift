// Purpose: Replace AVFoundation/UIKit device boundaries for deterministic AudioRecorder lifecycle checks.
// Inputs: Synthetic file bytes and controllable decoder duration/failure.
// Outputs: Recorder/player responses without microphone, speaker, or simulator access.
// Side effects: Creates a synthetic draft file; production AudioRecorder owns its cleanup.

import Foundation

// MARK: - Device and codec doubles
let AVFormatIDKey = "format"
let AVSampleRateKey = "rate"
let AVNumberOfChannelsKey = "channels"
let AVEncoderBitRateKey = "bitrate"
let AVEncoderAudioQualityKey = "quality"
let kAudioFormatMPEG4AAC = 0
let AVAudioSessionInterruptionTypeKey = "interruption"
let AVAudioSessionRouteChangeReasonKey = "route"
enum AVAudioQuality: Int { case high }
protocol AVAudioRecorderDelegate: AnyObject {}
protocol AVAudioPlayerDelegate: AnyObject {}

final class AVAudioRecorder {
    weak var delegate: AVAudioRecorderDelegate?
    var currentTime = 0.05
    init(url: URL, settings: [String: Any]) throws {
        try Data("Synthetic encoded draft".utf8).write(to: url)
    }
    func prepareToRecord() -> Bool { true }
    func record(forDuration duration: TimeInterval) -> Bool { true }
    func pause() {}
    func stop() {}
}

final class AVAudioPlayer {
    static var decodedDuration = 0.05
    static var failsDecoding = false
    weak var delegate: AVAudioPlayerDelegate?
    var currentTime: TimeInterval = 0
    let duration: TimeInterval
    init(contentsOf url: URL) throws {
        if Self.failsDecoding { throw DeviceAudioError.invalidAudio }
        duration = Self.decodedDuration
    }
    func prepareToPlay() -> Bool { true }
    func play() -> Bool { true }
    func pause() {}
    func stop() {}
}

enum AVAudioApplication {
    static func requestRecordPermission() async -> Bool { true }
}

enum UIApplication {
    static let didEnterBackgroundNotification = Notification.Name("fake-background")
}

final class AVAudioSession {
    enum Category { case playAndRecord, playback }
    enum Mode { case `default`, spokenAudio }
    struct Options: OptionSet {
        let rawValue: Int
        static let defaultToSpeaker = Options(rawValue: 1)
        static let allowBluetoothHFP = Options(rawValue: 2)
        static let notifyOthersOnDeactivation = Options(rawValue: 4)
    }
    enum InterruptionType: UInt { case began }
    enum RouteChangeReason: UInt { case oldDeviceUnavailable }
    static let interruptionNotification = Notification.Name("fake-interruption")
    static let routeChangeNotification = Notification.Name("fake-route")
    static let mediaServicesWereResetNotification = Notification.Name("fake-reset")
    static let instance = AVAudioSession()
    static func sharedInstance() -> AVAudioSession { instance }
    var isInputAvailable = true
    func setCategory(_ category: Category, mode: Mode, options: Options = []) throws {}
    func setActive(_ active: Bool, options: Options = []) throws {}
}
