import Foundation
import Testing
import VaporTesting
@testable import RevaServer

private let providerToken = "gemini-provider-test-token-123456789"
private let fakeGeminiKey = "fake-gemini-key-for-mocked-tests-only"

private actor GeminiRequests {
    var values: [URLRequest] = []
    func append(_ request: URLRequest) { values.append(request) }
}

private func providerEnvelope(_ object: [String: Any], finishReason: String = "STOP") throws -> Data {
    let output = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": finishReason, "content": ["parts": [["text": output]]]]]])
}

private func withGeminiServer(environment overrides: [String: String] = [:], demoIdentity: Bool = false,
                              transport: GeminiHTTPTransport,
                              test: (Application, ServerConfiguration) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reva-gemini-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var environment = ["REVA_DATA_DIRECTORY": directory.path]
    if !demoIdentity { environment["REVA_TOKENS"] = "{\"\(providerToken)\":\"provider-owner\"}" }
    environment.merge(overrides) { _, new in new }
    let configuration = try ServerConfiguration(environment: environment)
    let store = try LocalFileStore(directory: directory)
    try await withApp(configure: { app in configure(app, configuration: configuration, store: store, geminiTransport: transport) }) { app in
        try await test(app, configuration)
    }
}

private func providerHeaders(demo: Bool = false) -> HTTPHeaders {
    ["Authorization": "Bearer " + (demo ? ServerConfiguration.demoToken : providerToken)]
}

private let summaryInput = GeminiSummaryRequest(recordID: "synthetic-record", title: "Synthetic source", text: "Synthetic laboratory document. The source records a hemoglobin value of 12.8 g/dL.")
private let preparationInput = GeminiPreparationRequest(
    visit: .init(id: "synthetic-visit", type: "Primary care", concern: "Review source records", goal: "Organize questions", questions: []),
    records: [.init(id: "synthetic-record", title: "Synthetic source", date: "2026-09-01", text: "Synthetic source says no medication changes were documented.", summary: "Synthetic summary", version: 1)]
)

@Suite("Gemini providers — mocked HTTP only")
struct GeminiProviderTests {
    @Test func providerStatusIsAuthenticatedAndNeverContainsSecrets() async throws {
        let requests = GeminiRequests()
        let mock = GeminiHTTPTransport { request in await requests.append(request); return .init(status: 500, data: Data()) }
        try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey, "OPENAI_API_KEY": "fake-openai-key",
                                                "ELEVENLABS_API_KEY": "fake-elevenlabs-key", "ELEVENLABS_AGENT_ID": "agent_test",
                                                "ELEVENLABS_PHONE_NUMBER_ID": "phone_test"], transport: mock) { app, configuration in
            #expect(configuration.providers.geminiConfigured)
            try await app.testing().test(.GET, "v1/providers") { response async in #expect(response.status == .unauthorized) }
            try await app.testing().test(.GET, "v1/providers", headers: providerHeaders()) { response async throws in
                #expect(response.status == .ok)
                let status = try response.content.decode(ProviderStatus.self)
                #expect(status.gemini.configured)
                #expect(status.gemini.model == "gemini-2.5-flash")
                #expect(status.transcription.configured)
                #expect(status.transcription.model == "whisper-1")
                #expect(status.booking.configured)
                #expect(!status.liveCallsEnabled)
                #expect(!response.body.string.contains("fake-"))
                #expect(!response.body.string.contains("agent_test"))
                #expect(response.headers.first(name: .cacheControl) == "no-store")
            }
            #expect(await requests.values.isEmpty)
        }
    }

    @Test func missingKeyAndPublicDemoTokenDisableProviderCalls() async throws {
        let requests = GeminiRequests()
        let mock = GeminiHTTPTransport { request in await requests.append(request); return .init(status: 500, data: Data()) }
        for demo in [false, true] {
            let environment = demo ? ["GEMINI_API_KEY": fakeGeminiKey, "OPENAI_API_KEY": "fake-openai", "REVA_ENABLE_LIVE_CALLS": "true"] : [:]
            try await withGeminiServer(environment: environment, demoIdentity: demo, transport: mock) { app, configuration in
                #expect(!configuration.providers.geminiConfigured)
                try await app.testing().test(.GET, "v1/providers", headers: providerHeaders(demo: demo)) { response async throws in
                    let status = try response.content.decode(ProviderStatus.self)
                    #expect(!status.gemini.configured)
                    #expect(!status.transcription.configured)
                    #expect(!status.liveCallsEnabled)
                }
                try await app.testing().test(.POST, "v1/ai/summarize", headers: providerHeaders(demo: demo), beforeRequest: { request in
                    try request.content.encode(summaryInput)
                }, afterResponse: { response async in
                    #expect(response.status == .serviceUnavailable)
                    #expect(!response.body.string.contains(fakeGeminiKey))
                })
            }
        }
        #expect(await requests.values.isEmpty)
    }

    @Test func summaryUsesOfficialEndpointHeaderAndStructuredOutput() async throws {
        let requests = GeminiRequests()
        let body = try providerEnvelope(["summary": "The synthetic source records hemoglobin 12.8 g/dL."])
        let mock = GeminiHTTPTransport { request in await requests.append(request); return .init(status: 200, data: body) }
        try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey], transport: mock) { app, _ in
            try await app.testing().test(.POST, "v1/ai/summarize", beforeRequest: { request in try request.content.encode(summaryInput) }) { response async in
                #expect(response.status == .unauthorized)
            }
            try await app.testing().test(.POST, "v1/ai/summarize", headers: providerHeaders(), beforeRequest: { request in
                try request.content.encode(summaryInput)
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let summary = try response.content.decode(GeminiSummaryResponse.self)
                #expect(summary.summary == "The synthetic source records hemoglobin 12.8 g/dL.")
                #expect(summary.model == "gemini-2.5-flash")
            })
        }
        let recorded = await requests.values
        #expect(recorded.count == 1)
        let request = try #require(recorded.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == fakeGeminiKey)
        let requestBody = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let generation = try #require(payload["generationConfig"] as? [String: Any])
        #expect(generation["responseMimeType"] as? String == "application/json")
        #expect(generation["responseJsonSchema"] != nil)
        #expect(payload["tools"] == nil)
        #expect(!String(decoding: requestBody, as: UTF8.self).contains(fakeGeminiKey))
    }

    @Test func preparationPreservesSelectedCandidateIDsAndModel() async throws {
        let body = try providerEnvelope(["overview": "Organize the synthetic source for review.", "questions": ["What remains undocumented?"], "selectedRecordIDs": ["synthetic-record"]])
        let requests = GeminiRequests()
        let mock = GeminiHTTPTransport { request in await requests.append(request); return .init(status: 200, data: body) }
        try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey, "GEMINI_MODEL": "gemini-2.5-flash-lite"], transport: mock) { app, _ in
            try await app.testing().test(.POST, "v1/ai/prepare", headers: providerHeaders(), beforeRequest: { request in
                try request.content.encode(preparationInput)
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let prepared = try response.content.decode(GeminiPreparationResponse.self)
                #expect(prepared.selectedRecordIDs == ["synthetic-record"])
                #expect(prepared.questions == ["What remains undocumented?"])
                #expect(prepared.model == "gemini-2.5-flash-lite")
            })
        }
        #expect(await requests.values.count == 1)
    }

    @Test func malformedAndOversizedRequestsFailBeforeProviderTransport() async throws {
        let requests = GeminiRequests()
        let mock = GeminiHTTPTransport { request in await requests.append(request); return .init(status: 500, data: Data()) }
        try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey], transport: mock) { app, _ in
            for input in [GeminiSummaryRequest(recordID: "bad/id", title: "source", text: "source"),
                          .init(recordID: "id", title: "source", text: "   "),
                          .init(recordID: "id", title: "source", text: String(repeating: "x", count: 120_001))] {
                try await app.testing().test(.POST, "v1/ai/summarize", headers: providerHeaders(), beforeRequest: { request in
                    try request.content.encode(input)
                }, afterResponse: { response async in #expect(response.status == .badRequest) })
            }
            var duplicate = preparationInput.records
            duplicate.append(duplicate[0])
            let invalid = GeminiPreparationRequest(visit: preparationInput.visit, records: duplicate)
            try await app.testing().test(.POST, "v1/ai/prepare", headers: providerHeaders(), beforeRequest: { request in
                try request.content.encode(invalid)
            }, afterResponse: { response async in #expect(response.status == .badRequest) })
            try await app.testing().test(.POST, "v1/ai/prepare", headers: providerHeaders(), body: ByteBuffer(string: "not-json")) { response async in
                #expect(response.status == .unsupportedMediaType)
            }
        }
        #expect(await requests.values.isEmpty)
    }

    @Test func unknownDuplicateOrInvalidGeneratedIDsAreRejected() async throws {
        for ids in [["not-a-candidate"], ["synthetic-record", "synthetic-record"]] {
            let body = try providerEnvelope(["overview": "Synthetic overview", "questions": [], "selectedRecordIDs": ids])
            let mock = GeminiHTTPTransport { _ in .init(status: 200, data: body) }
            try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey], transport: mock) { app, _ in
                try await app.testing().test(.POST, "v1/ai/prepare", headers: providerHeaders(), beforeRequest: { request in
                    try request.content.encode(preparationInput)
                }, afterResponse: { response async in #expect(response.status == .serviceUnavailable) })
            }
        }
    }

    @Test func providerErrorsBlockedPartialAndEmptyOutputsFailSafely() async throws {
        let cases: [GeminiHTTPResponse] = [
            .init(status: 429, data: Data(("provider-error-secret:" + fakeGeminiKey).utf8)),
            .init(status: 200, data: Data("invalid JSON".utf8)),
            .init(status: 200, data: try providerEnvelope(["summary": ""])),
            .init(status: 200, data: try providerEnvelope(["summary": "Partial result"], finishReason: "MAX_TOKENS")),
            .init(status: 200, data: Data("{\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}".utf8))
        ]
        for result in cases {
            let mock = GeminiHTTPTransport { _ in result }
            try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey], transport: mock) { app, _ in
                try await app.testing().test(.POST, "v1/ai/summarize", headers: providerHeaders(), beforeRequest: { request in
                    try request.content.encode(summaryInput)
                }, afterResponse: { response async in
                    #expect(response.status == .serviceUnavailable)
                    #expect(!response.body.string.contains(fakeGeminiKey))
                    #expect(!response.body.string.contains("provider-error-secret"))
                })
            }
        }
        let unreachable = GeminiHTTPTransport { _ in throw URLError(.notConnectedToInternet) }
        try await withGeminiServer(environment: ["GEMINI_API_KEY": fakeGeminiKey], transport: unreachable) { app, _ in
            try await app.testing().test(.POST, "v1/ai/summarize", headers: providerHeaders(), beforeRequest: { request in
                try request.content.encode(summaryInput)
            }, afterResponse: { response async in #expect(response.status == .serviceUnavailable) })
        }
    }

    @Test func providerConfigurationUsesInjectedEnvironmentAndRejectsUnsafeOverrides() throws {
        let empty = try ServerConfiguration(environment: [:])
        #expect(empty.providers.geminiAPIKey == nil)
        #expect(!empty.providers.paidAccessAllowed)
        for environment in [["GEMINI_MODEL": "gemini-test/../../unexpected"], ["GEMINI_API_KEY": "header\r\ninjection"],
                            ["OPENAI_TRANSCRIPTION_MODEL": "unsupported-model"], ["REVA_ENABLE_LIVE_CALLS": "yes"]] {
            #expect(throws: ConfigurationError.self) { try ProviderConfiguration(environment: environment, paidAccessAllowed: true) }
        }
    }
}
