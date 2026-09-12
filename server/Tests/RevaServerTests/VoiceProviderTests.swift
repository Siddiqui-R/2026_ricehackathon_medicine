// Purpose: Verify audio wire fidelity without contacting a transcription provider.
// Inputs: Synthetic bytes/transcripts, fake configuration, and controlled transport outcomes.
// Outputs: Assertions on timestamps, neutral speaker labels, audio limits, and authenticated route keys.
// Side effects: Creates VaporTesting apps with injected mock transports; no live provider requests.

import Foundation
import Testing
import VaporTesting

@testable import RevaServer

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Fake credentials and synthetic provider fixtures
private let voiceEnvironment = ["OPENAI_API_KEY": "mock-openai-key-never-used-live"]
private let whisperJSON =
    #"{"duration":5.0,"text":"A fictional visit. Follow up later.","segments":[{"id":0,"start":0.2,"end":2.0,"text":" A fictional visit."},{"id":1,"start":2.1,"end":4.8,"text":" Follow up later."}]}"#
// MARK: - Deterministic transport recording, delay, and failure injection
private actor VoiceMockHTTP {
    enum Outcome: Sendable {
        case response(Int, String)
        case failure
    }
    private(set) var requests: [URLRequest] = []
    private var outcomes: [Outcome]
    let delay: Duration
    let beforeSend: @Sendable (URLRequest) throws -> Void

    init(
        _ outcomes: [Outcome], delay: Duration = .zero,
        beforeSend: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) {
        self.outcomes = outcomes
        self.delay = delay
        self.beforeSend = beforeSend
    }
    func send(_ request: URLRequest) async throws -> VoiceHTTPResponse {
        requests.append(request)
        try beforeSend(request)
        guard !outcomes.isEmpty else { throw URLError(.resourceUnavailable) }
        let outcome = outcomes.removeFirst()
        if delay > .zero { try await Task.sleep(for: delay) }
        switch outcome {
        case .response(let status, let body):
            return VoiceHTTPResponse(statusCode: status, body: Data(body.utf8))
        case .failure: throw URLError(.timedOut)
        }
    }
    var count: Int { requests.count }
    nonisolated var transport: VoiceHTTPTransport { VoiceHTTPTransport { try await self.send($0) } }
}

// MARK: - Synthetic provider configuration and rejection assertions
private func voiceConfiguration(_ environment: [String: String] = voiceEnvironment, allowed: Bool = true)
    throws -> ProviderConfiguration
{
    try ProviderConfiguration(environment: environment, paidAccessAllowed: allowed)
}
private func expectVoiceAbort(_ status: HTTPResponseStatus, _ action: () async throws -> Void) async throws {
    do {
        try await action()
        Issue.record("Expected a safe HTTP rejection")
    } catch let error as Abort { #expect(error.status == status) }
}

// MARK: - Whisper multipart fidelity and transcript validation
@Suite("Voice provider adapters — mocked transport only")
struct VoiceProviderTests {
    // MARK: - Browser originals preserve bytes and MIME across storage and transcription boundaries
    @Test(arguments: ["webm", "ogg"])
    func browserAudioOriginalsAreAcceptedWithoutRelabeling(format: String) async throws {
        let audio = Data([0, 1, 255, 13, 10, 65])
        let contentType = "audio/" + format
        let filename = "Synthetic-browser-visit." + format
        try Validation.attachment(
            StoredAttachment(
                id: "browser-audio", filename: filename, contentType: contentType,
                data: audio, updatedAt: Date()))
        let mock = VoiceMockHTTP([.response(200, whisperJSON)])
        let service = VoiceTranscriptionService(
            configuration: try voiceConfiguration(), transport: mock.transport)
        let result = try await service.transcribe(audio: audio, filename: filename, contentType: contentType)
        #expect(result.model == "whisper-1")
        let request = try #require(await mock.requests.first)
        let body = try #require(request.httpBody)
        #expect(body.range(of: audio) != nil)
        #expect(body.range(of: Data(("Content-Type: " + contentType).utf8)) != nil)
        #expect(body.range(of: Data(("filename=\"" + filename + "\"").utf8)) != nil)
        #expect(await mock.count == 1)
    }

    @Test func whisperMultipartTimestampsAndNeutralSpeaker() async throws {
        let mock = VoiceMockHTTP([.response(200, whisperJSON)])
        let service = VoiceTranscriptionService(
            configuration: try voiceConfiguration(), transport: mock.transport)
        let audio = Data([0, 1, 255, 13, 10, 65])
        let result = try await service.transcribe(
            audio: audio, filename: "Synthetic visit.m4a", contentType: "audio/mp4")
        #expect(result.model == "whisper-1")
        #expect(result.text == "A fictional visit. Follow up later.")
        #expect(result.segments.map(\.speaker) == ["Speaker", "Speaker"])
        #expect(result.segments[0].start == 0.2 && result.segments[1].end == 4.8)
        #expect(result.segments.map(\.id) == ["whisper-segment-0", "whisper-segment-1"])
        let request = try #require(await mock.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-openai-key-never-used-live")
        let body = try #require(request.httpBody)
        #expect(body.range(of: audio) != nil)
        for field in [
            "name=\"model\"\r\n\r\nwhisper-1", "name=\"response_format\"\r\n\r\nverbose_json",
            "name=\"timestamp_granularities[]\"\r\n\r\nsegment", "filename=\"Synthetic visit.m4a\"",
        ] {
            #expect(body.range(of: Data(field.utf8)) != nil)
        }
    }

    @Test func transcriptionDisabledAndInvalidInputNeverReachTransport() async throws {
        let mock = VoiceMockHTTP([])
        for configuration in [try voiceConfiguration([:]), try voiceConfiguration(allowed: false)] {
            let service = VoiceTranscriptionService(configuration: configuration, transport: mock.transport)
            try await expectVoiceAbort(.serviceUnavailable) {
                _ = try await service.transcribe(
                    audio: Data([1]), filename: "audio.m4a", contentType: "audio/mp4")
            }
        }
        let enabled = VoiceTranscriptionService(
            configuration: try voiceConfiguration(), transport: mock.transport)
        for (audio, filename, type, status) in [
            (Data(), "audio.m4a", "audio/mp4", HTTPResponseStatus.badRequest),
            (Data([1]), "../audio.m4a", "audio/mp4", .badRequest),
            (Data([1]), "a\"\r\nInjected.m4a", "audio/mp4", .badRequest),
            (Data([1]), "audio.html", "text/html", .unsupportedMediaType),
            (
                Data(repeating: 0, count: VoiceProviderLimits.audioBytes + 1), "audio.wav", "audio/wav",
                .payloadTooLarge
            ),
        ] {
            try await expectVoiceAbort(status) {
                _ = try await enabled.transcribe(audio: audio, filename: filename, contentType: type)
            }
        }
        #expect(await mock.count == 0)
    }

    @Test func transcriptionRejectsMalformedOffsetsAndUnavailableProviders() async throws {
        let invalid = [
            #"{"duration":5,"text":"Words","segments":[{"id":0,"start":-1,"end":2,"text":"Words"}]}"#,
            #"{"duration":5,"text":"Words","segments":[{"id":0,"start":3,"end":2,"text":"Words"}]}"#,
            #"{"duration":5,"text":"Words","segments":[{"id":0,"start":0,"end":20,"text":"Words"}]}"#,
            #"{"duration":5,"text":"Words","segments":[{"id":0,"start":0,"end":2,"text":"Words"},{"id":0,"start":2,"end":3,"text":"Again"}]}"#,
            #"{"duration":5,"text":"Words"}"#,
            #"{"duration":5,"text":"Words","segments":[]}"#,
            "invalid json",
        ]
        for body in invalid {
            let mock = VoiceMockHTTP([.response(200, body)])
            let service = VoiceTranscriptionService(
                configuration: try voiceConfiguration(), transport: mock.transport)
            try await expectVoiceAbort(.badGateway) {
                _ = try await service.transcribe(
                    audio: Data([1]), filename: "a.wav", contentType: "audio/wav")
            }
        }
        let silent = VoiceMockHTTP([.response(200, #"{"duration":5,"text":" ","segments":[]}"#)])
        let service = VoiceTranscriptionService(
            configuration: try voiceConfiguration(), transport: silent.transport)
        try await expectVoiceAbort(.unprocessableEntity) {
            _ = try await service.transcribe(audio: Data([1]), filename: "a.wav", contentType: "audio/wav")
        }
        for outcome in [
            VoiceMockHTTP.Outcome.failure, .response(401, #"{"error":"secret-provider-message"}"#),
        ] {
            let mock = VoiceMockHTTP([outcome])
            let service = VoiceTranscriptionService(
                configuration: try voiceConfiguration(), transport: mock.transport)
            do {
                _ = try await service.transcribe(
                    audio: Data([1]), filename: "a.mp3", contentType: "audio/mpeg")
                Issue.record("Expected provider failure")
            } catch let error as Abort {
                #expect(error.status == .badGateway)
                #expect(!error.reason.contains("secret-provider-message"))
            }
        }
    }

    // MARK: - Authenticated raw audio route and exact response keys
    @Test func transcriptionRoutePreservesAuthenticationAndWireKeys() async throws {
        let mock = VoiceMockHTTP([.response(200, whisperJSON)])
        let configuration = try voiceConfiguration()
        try await withApp(configure: { app in
            registerVoiceProviderRoutes(
                app.grouped(VoiceTestOwnerMiddleware()).grouped("v1"), configuration: configuration,
                transport: mock.transport)
        }) { app in
            try await app.testing().test(.POST, "v1/audio/transcribe") { response async in
                #expect(response.status == .unauthorized)
            }
            try await app.testing().test(
                .POST, "v1/audio/transcribe",
                headers: [
                    "Authorization": "Bearer owner-a", "Content-Type": "audio/mp4",
                    "X-Filename": "synthetic.m4a",
                ],
                body: ByteBuffer(bytes: [0, 1, 2])
            ) { response async throws in
                #expect(response.status == .ok)
                let json = try #require(
                    JSONSerialization.jsonObject(with: Data(response.body.readableBytesView))
                        as? [String: Any])
                #expect(Set(json.keys) == ["text", "segments", "model"])
                let segments = try #require(json["segments"] as? [[String: Any]])
                #expect(Set(segments[0].keys) == ["id", "start", "end", "speaker", "text"])
            }
            #expect(await mock.count == 1)
        }
    }

    @Test func disabledTranscriptionRouteReturnsServiceUnavailable() async throws {
        let mock = VoiceMockHTTP([])
        let configuration = try voiceConfiguration([:])
        try await withApp(configure: { app in
            registerVoiceProviderRoutes(
                app.grouped(VoiceTestOwnerMiddleware()).grouped("v1"), configuration: configuration,
                transport: mock.transport)
        }) { app in
            try await app.testing().test(
                .POST, "v1/audio/transcribe",
                headers: [
                    "Authorization": "Bearer owner-a", "Content-Type": "audio/wav",
                    "X-Filename": "synthetic.wav",
                ],
                body: ByteBuffer(bytes: [1])
            ) { response async in
                #expect(response.status == .serviceUnavailable)
            }
        }
        #expect(await mock.count == 0)
    }
}

// MARK: - Test-only owner injection without production credential handling
private struct VoiceTestOwnerMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let owner = request.headers.bearerAuthorization?.token, ["owner-a", "owner-b"].contains(owner) {
            request.auth.login(OwnerIdentity(id: owner))
        }
        return try await next.respond(to: request)
    }
}
