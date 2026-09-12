import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import VaporTesting
@testable import RevaServer

private let voiceEnvironment = [
    "OPENAI_API_KEY": "mock-openai-key-never-used-live", "ELEVENLABS_API_KEY": "mock-elevenlabs-key-never-used-live",
    "ELEVENLABS_AGENT_ID": "agent_mock", "ELEVENLABS_PHONE_NUMBER_ID": "phone_mock", "REVA_ENABLE_LIVE_CALLS": "true"
]
private let whisperJSON = #"{"duration":5.0,"text":"A fictional visit. Follow up later.","segments":[{"id":0,"start":0.2,"end":2.0,"text":" A fictional visit."},{"id":1,"start":2.1,"end":4.8,"text":" Follow up later."}]}"#
private let outboundJSON = #"{"success":true,"message":"initiated","conversation_id":"conv_mock","callSid":"mock_sid"}"#
private let conversationJSON = #"{"conversation_id":"conv_mock","status":"done","transcript":[{"role":"agent","time_in_call_secs":0,"message":"I am calling about availability."},{"role":"user","time_in_call_secs":2.4,"message":"Please ask the patient to call us."},{"role":"agent","time_in_call_secs":3,"message":null}]}"#

private actor VoiceMockHTTP {
    enum Outcome: Sendable { case response(Int, String), failure }
    private(set) var requests: [URLRequest] = []
    private var outcomes: [Outcome]
    let delay: Duration
    let beforeSend: @Sendable (URLRequest) throws -> Void

    init(_ outcomes: [Outcome], delay: Duration = .zero, beforeSend: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) {
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
        case .response(let status, let body): return VoiceHTTPResponse(statusCode: status, body: Data(body.utf8))
        case .failure: throw URLError(.timedOut)
        }
    }
    var count: Int { requests.count }
    nonisolated var transport: VoiceHTTPTransport { VoiceHTTPTransport { try await self.send($0) } }
}

private func voiceConfiguration(_ environment: [String: String] = voiceEnvironment, allowed: Bool = true) throws -> ProviderConfiguration {
    try ProviderConfiguration(environment: environment, paidAccessAllowed: allowed)
}
private func temporaryVoiceDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("reva-voice-tests-" + UUID().uuidString)
}
private func callRequest(id: String = "request-a", phone: String = "+13125550123", consent: Bool = true,
                         reason: String = "Ask about a fictional appointment", earliest: String = "2030-09-12T14:00:00Z",
                         latest: String = "2030-09-20T20:00:00Z", zone: String = "America/Chicago") -> VoiceBookingCallRequest {
    VoiceBookingCallRequest(requestID: id, clinic: "Fictional Clinic", phone: phone, reason: reason,
                            earliest: earliest, latest: latest, timeZone: zone, preferences: "Morning, if available",
                            patientName: "Synthetic Example", consent: consent)
}
private func expectVoiceAbort(_ status: HTTPResponseStatus, _ action: () async throws -> Void) async throws {
    do { try await action(); Issue.record("Expected a safe HTTP rejection") }
    catch let error as Abort { #expect(error.status == status) }
}

@Suite("Voice provider adapters — mocked transport only")
struct VoiceProviderTests {
    @Test func whisperMultipartTimestampsAndNeutralSpeaker() async throws {
        let mock = VoiceMockHTTP([.response(200, whisperJSON)])
        let service = VoiceTranscriptionService(configuration: try voiceConfiguration(), transport: mock.transport)
        let audio = Data([0, 1, 255, 13, 10, 65])
        let result = try await service.transcribe(audio: audio, filename: "Synthetic visit.m4a", contentType: "audio/mp4")
        #expect(result.model == "whisper-1")
        #expect(result.text == "A fictional visit. Follow up later.")
        #expect(result.segments.map(\.speaker) == ["Speaker", "Speaker"])
        #expect(result.segments[0].start == 0.2 && result.segments[1].end == 4.8)
        #expect(result.segments.map(\.id) == ["whisper-segment-0", "whisper-segment-1"])
        let request = try #require(await mock.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-openai-key-never-used-live")
        let body = try #require(request.httpBody)
        #expect(body.range(of: audio) != nil)
        for field in ["name=\"model\"\r\n\r\nwhisper-1", "name=\"response_format\"\r\n\r\nverbose_json", "name=\"timestamp_granularities[]\"\r\n\r\nsegment", "filename=\"Synthetic visit.m4a\""] {
            #expect(body.range(of: Data(field.utf8)) != nil)
        }
    }

    @Test func transcriptionDisabledAndInvalidInputNeverReachTransport() async throws {
        let mock = VoiceMockHTTP([])
        for configuration in [try voiceConfiguration([:]), try voiceConfiguration(allowed: false)] {
            let service = VoiceTranscriptionService(configuration: configuration, transport: mock.transport)
            try await expectVoiceAbort(.serviceUnavailable) { _ = try await service.transcribe(audio: Data([1]), filename: "audio.m4a", contentType: "audio/mp4") }
        }
        let enabled = VoiceTranscriptionService(configuration: try voiceConfiguration(), transport: mock.transport)
        for (audio, filename, type, status) in [
            (Data(), "audio.m4a", "audio/mp4", HTTPResponseStatus.badRequest),
            (Data([1]), "../audio.m4a", "audio/mp4", .badRequest),
            (Data([1]), "a\"\r\nInjected.m4a", "audio/mp4", .badRequest),
            (Data([1]), "audio.html", "text/html", .unsupportedMediaType),
            (Data(repeating: 0, count: VoiceProviderLimits.audioBytes + 1), "audio.wav", "audio/wav", .payloadTooLarge)
        ] {
            try await expectVoiceAbort(status) { _ = try await enabled.transcribe(audio: audio, filename: filename, contentType: type) }
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
            "invalid json"
        ]
        for body in invalid {
            let mock = VoiceMockHTTP([.response(200, body)])
            let service = VoiceTranscriptionService(configuration: try voiceConfiguration(), transport: mock.transport)
            try await expectVoiceAbort(.badGateway) { _ = try await service.transcribe(audio: Data([1]), filename: "a.wav", contentType: "audio/wav") }
        }
        let silent = VoiceMockHTTP([.response(200, #"{"duration":5,"text":" ","segments":[]}"#)])
        let service = VoiceTranscriptionService(configuration: try voiceConfiguration(), transport: silent.transport)
        try await expectVoiceAbort(.unprocessableEntity) { _ = try await service.transcribe(audio: Data([1]), filename: "a.wav", contentType: "audio/wav") }
        for outcome in [VoiceMockHTTP.Outcome.failure, .response(401, #"{"error":"secret-provider-message"}"#)] {
            let mock = VoiceMockHTTP([outcome])
            let service = VoiceTranscriptionService(configuration: try voiceConfiguration(), transport: mock.transport)
            do { _ = try await service.transcribe(audio: Data([1]), filename: "a.mp3", contentType: "audio/mpeg"); Issue.record("Expected provider failure") }
            catch let error as Abort { #expect(error.status == .badGateway); #expect(!error.reason.contains("secret-provider-message")) }
        }
    }

    @Test func callPersistsIntentBeforeTransportAndReplaysWithoutRedial() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let receiptURL = directory.appendingPathComponent("voice-call-receipts/owner-a/request-a.json")
        let mock = VoiceMockHTTP([.response(200, outboundJSON), .response(200, conversationJSON)], beforeSend: { request in
            if request.httpMethod == "POST" {
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any]
                #expect(json?["status"] as? String == "intent")
                #expect(json?["owner"] as? String == "owner-a")
            }
        })
        let service = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        #expect(!FileManager.default.fileExists(atPath: directory.path)) // Initialization has no filesystem effect.
        let started = try await service.start(owner: "owner-a", call: callRequest())
        #expect(started == VoiceBookingCallResponse(conversationID: "conv_mock", status: "initiated", provider: "ElevenLabs"))
        let replay = try await service.start(owner: "owner-a", call: callRequest())
        #expect(replay == started)
        #expect(await mock.count == 1)
        let submitted = try #require(await mock.requests.first)
        #expect(submitted.url?.absoluteString == "https://api.elevenlabs.io/v1/convai/twilio/outbound-call")
        #expect(submitted.value(forHTTPHeaderField: "xi-api-key") == "mock-elevenlabs-key-never-used-live")
        let submittedBody = try #require(submitted.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: submittedBody) as? [String: Any])
        #expect(payload["agent_id"] as? String == "agent_mock")
        #expect(payload["agent_phone_number_id"] as? String == "phone_mock")
        #expect(payload["to_number"] as? String == "+13125550123")
        #expect(payload["call_recording_enabled"] as? Bool == false)
        let initiation = try #require(payload["conversation_initiation_client_data"] as? [String: Any])
        let variables = try #require(initiation["dynamic_variables"] as? [String: String])
        #expect(variables["patient_name"] == "Synthetic Example" && variables["request_id"] == "request-a")
        #expect(variables["earliest"] == "2030-09-12T14:00:00Z" && variables["time_zone"] == "America/Chicago")
        try await expectVoiceAbort(.notFound) { _ = try await service.details(owner: "owner-b", requestID: "request-a") }
        try await expectVoiceAbort(.conflict) { _ = try await service.start(owner: "owner-a", call: callRequest(reason: "Changed request")) }
        #expect(await mock.count == 1)
        let details = try await service.details(owner: "owner-a", requestID: "request-a")
        #expect(details.status == "done") // Completion is a conversation status, never appointment confirmation.
        #expect(details.transcript.contains("[0:02] User: Please ask the patient to call us."))
        #expect(!details.transcript.contains("null"))
        #expect(await mock.count == 2)
        #expect(try await service.start(owner: "owner-a", call: callRequest()).status == "done")
        #expect(await mock.count == 2)
    }

    @Test func callGatesAndInvalidRequestsNeverDial() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([])
        var disabled = voiceEnvironment; disabled["REVA_ENABLE_LIVE_CALLS"] = "false"
        for configuration in [try voiceConfiguration([:]), try voiceConfiguration(disabled), try voiceConfiguration(allowed: false)] {
            let service = VoiceCallService(configuration: configuration, directory: directory, transport: mock.transport)
            try await expectVoiceAbort(.serviceUnavailable) { _ = try await service.start(owner: "owner-a", call: callRequest()) }
        }
        let service = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        for call in [callRequest(consent: false), callRequest(phone: "(312) 555-0123"), callRequest(phone: "+13125550123\n"),
                     callRequest(phone: "+0123"), callRequest(id: "../unsafe"), callRequest(reason: " "),
                     callRequest(earliest: "2030-09-21T20:00:00Z"), callRequest(zone: "Wrong/Zone")] {
            try await expectVoiceAbort(.badRequest) { _ = try await service.start(owner: "owner-a", call: call) }
        }
        #expect(await mock.count == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func uncertainCallSurvivesRestartAndNeverRedials() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([.failure])
        var first: VoiceCallService? = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        try await expectVoiceAbort(.badGateway) { _ = try await first!.start(owner: "owner-a", call: callRequest()) }
        first = nil
        let restarted = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        try await expectVoiceAbort(.conflict) { _ = try await restarted.start(owner: "owner-a", call: callRequest()) }
        let details = try await restarted.details(owner: "owner-a", requestID: "request-a")
        #expect(details.status == "uncertain" && details.conversationID.isEmpty && details.transcript.isEmpty)
        #expect(await mock.count == 1)
    }

    @Test func submittedReceiptSurvivesRestartAndDirectoryLockExcludesSecondInstance() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([.response(200, outboundJSON)])
        var first: VoiceCallService? = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        _ = try await first!.start(owner: "owner-a", call: callRequest())
        let another = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        try await expectVoiceAbort(.serviceUnavailable) { _ = try await another.start(owner: "owner-a", call: callRequest()) }
        first = nil
        #expect(try await another.start(owner: "owner-a", call: callRequest()).conversationID == "conv_mock")
        #expect(await mock.count == 1)
    }

    @Test func concurrentSameRequestDoesNotRedial() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([.response(200, outboundJSON)], delay: .milliseconds(250))
        let service = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        async let first = service.start(owner: "owner-a", call: callRequest())
        for _ in 0..<30 {
            if await mock.count > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await expectVoiceAbort(.conflict) { _ = try await service.start(owner: "owner-a", call: callRequest()) }
        #expect(try await first.conversationID == "conv_mock")
        #expect(await mock.count == 1)
    }

    @Test func corruptReceiptAndUnavailableStorageFailClosed() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([.failure])
        let service = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        try await expectVoiceAbort(.badGateway) { _ = try await service.start(owner: "owner-a", call: callRequest()) }
        try Data("broken receipt".utf8).write(to: directory.appendingPathComponent("voice-call-receipts/owner-a/request-a.json"))
        try await expectVoiceAbort(.serviceUnavailable) { _ = try await service.start(owner: "owner-a", call: callRequest()) }
        #expect(await mock.count == 1)
        let unavailable = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: unavailable) }
        try Data("not a directory".utf8).write(to: unavailable)
        let blocked = VoiceCallService(configuration: try voiceConfiguration(), directory: unavailable, transport: mock.transport)
        try await expectVoiceAbort(.serviceUnavailable) { _ = try await blocked.start(owner: "owner-a", call: callRequest()) }
        #expect(await mock.count == 1)
    }

    @Test func providerFailureAndMalformedSuccessRemainUncertain() async throws {
        for outcome in [VoiceMockHTTP.Outcome.response(422, #"{"error":"private-provider-data"}"#), .response(200, #"{"success":true}"#), .response(200, "bad JSON")] {
            let directory = temporaryVoiceDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let mock = VoiceMockHTTP([outcome])
            let service = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
            do { _ = try await service.start(owner: "owner-a", call: callRequest()); Issue.record("Expected uncertain provider outcome") }
            catch let error as Abort { #expect(error.status == .badGateway); #expect(!error.reason.contains("private-provider-data")) }
            try await expectVoiceAbort(.conflict) { _ = try await service.start(owner: "owner-a", call: callRequest()) }
            #expect(await mock.count == 1)
        }
    }

    @Test func pollingIsOwnerScopedBoundedAndAllowedAfterDisablingNewCalls() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let longMessage = String(repeating: "Fictional transcript. ", count: 11_000)
        let payload: [String: Any] = ["conversation_id": "conv_mock", "status": "done", "transcript": [["role": "user", "time_in_call_secs": 1, "message": longMessage]]]
        let longJSON = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let mock = VoiceMockHTTP([.response(200, outboundJSON), .response(200, longJSON)])
        var initial: VoiceCallService? = VoiceCallService(configuration: try voiceConfiguration(), directory: directory, transport: mock.transport)
        _ = try await initial!.start(owner: "owner-a", call: callRequest())
        initial = nil
        var disabled = voiceEnvironment; disabled["REVA_ENABLE_LIVE_CALLS"] = "false"
        let polling = VoiceCallService(configuration: try voiceConfiguration(disabled), directory: directory, transport: mock.transport)
        let details = try await polling.details(owner: "owner-a", requestID: "request-a")
        #expect(details.transcript.count <= VoiceProviderLimits.transcriptCharacters)
        #expect(details.transcript.contains("Transcript shortened"))
        try await expectVoiceAbort(.notFound) { _ = try await polling.details(owner: "owner-b", requestID: "request-a") }
        try await expectVoiceAbort(.serviceUnavailable) { _ = try await polling.start(owner: "owner-a", call: callRequest(id: "new-request")) }
        #expect(await mock.count == 2)
    }

    @Test func routesEnforceAuthenticationAndExactWireKeys() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([.response(200, whisperJSON), .response(200, outboundJSON), .response(200, conversationJSON)])
        let configuration = try voiceConfiguration()
        try await withApp(configure: { app in
            registerVoiceProviderRoutes(app.grouped(VoiceTestOwnerMiddleware()).grouped("v1"), configuration: configuration,
                                        directory: directory, transport: mock.transport)
        }) { app in
            for route in ["v1/audio/transcribe", "v1/booking/call"] {
                try await app.testing().test(.POST, route) { response async in #expect(response.status == .unauthorized) }
            }
            let audioHeaders: HTTPHeaders = ["Authorization": "Bearer owner-a", "Content-Type": "audio/mp4", "X-Filename": "synthetic.m4a"]
            try await app.testing().test(.POST, "v1/audio/transcribe", headers: audioHeaders, body: ByteBuffer(bytes: [0, 1, 2])) { response async throws in
                #expect(response.status == .ok)
                let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                #expect(Set(json.keys) == ["text", "segments", "model"])
                let segments = try #require(json["segments"] as? [[String: Any]])
                #expect(Set(segments[0].keys) == ["id", "start", "end", "speaker", "text"])
            }
            try await app.testing().test(.POST, "v1/booking/call", headers: ["Authorization": "Bearer owner-a"], beforeRequest: { request in
                try request.content.encode(callRequest())
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                #expect(Set(json.keys) == ["conversationID", "status", "provider"])
            })
            try await app.testing().test(.GET, "v1/booking/call/request-a", headers: ["Authorization": "Bearer owner-b"]) { response async in
                #expect(response.status == .notFound)
            }
            try await app.testing().test(.GET, "v1/booking/call/request-a", headers: ["Authorization": "Bearer owner-a"]) { response async throws in
                #expect(response.status == .ok)
                let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                #expect(Set(json.keys) == ["conversationID", "status", "provider", "transcript"])
            }
            #expect(await mock.count == 3)
        }
    }

    @Test func disabledVoiceRoutesReturnServiceUnavailable() async throws {
        let directory = temporaryVoiceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = VoiceMockHTTP([])
        let configuration = try voiceConfiguration([:])
        try await withApp(configure: { app in
            registerVoiceProviderRoutes(app.grouped(VoiceTestOwnerMiddleware()).grouped("v1"), configuration: configuration,
                                        directory: directory, transport: mock.transport)
        }) { app in
            try await app.testing().test(.POST, "v1/audio/transcribe", headers: ["Authorization": "Bearer owner-a", "Content-Type": "audio/wav", "X-Filename": "synthetic.wav"], body: ByteBuffer(bytes: [1])) { response async in
                #expect(response.status == .serviceUnavailable)
            }
            try await app.testing().test(.POST, "v1/booking/call", headers: ["Authorization": "Bearer owner-a"], beforeRequest: { request in
                try request.content.encode(callRequest())
            }, afterResponse: { response async in #expect(response.status == .serviceUnavailable) })
        }
        #expect(await mock.count == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

private struct VoiceTestOwnerMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let owner = request.headers.bearerAuthorization?.token, ["owner-a", "owner-b"].contains(owner) {
            request.auth.login(OwnerIdentity(id: owner))
        }
        return try await next.respond(to: request)
    }
}
