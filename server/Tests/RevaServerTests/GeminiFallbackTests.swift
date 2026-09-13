// Purpose: Verify fixed Flash/Lite sequencing, cancellation, retry headers and optional source-based titles.
// Inputs: Fictional text, injected configuration and mocked Gemini HTTP responses.
// Outputs: Assertions on request count/model, terminal validation and generated title byte limits.
// Side effects: None; all transport is mocked and no data is persisted.

import Foundation
import Testing
import Vapor

@testable import RevaServer

// MARK: - Synthetic transport fixtures shared by sequencing and title checks
private actor FallbackRequests {
    var values: [URLRequest] = []
    func append(_ request: URLRequest) -> Int {
        values.append(request)
        return values.count
    }
}
private func fallbackEnvelope(_ object: [String: String]) throws -> Data {
    let value = String(decoding: try JSONEncoder().encode(object), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: [
        "candidates": [["finishReason": "STOP", "content": ["parts": [["text": value]]]]]
    ])
}
private func fallbackService(_ transport: GeminiHTTPTransport) throws -> GeminiService {
    .init(
        configuration: try ProviderConfiguration(
            environment: ["GEMINI_API_KEY": "fictional-key"], paidAccessAllowed: true), transport: transport)
}
private let fallbackInput = GeminiSummaryRequest(
    recordID: "source", title: "Fictional note", text: "No fever was reported.", date: "2026-09-12")

// MARK: - Only transient failures cause one immediate Lite attempt
@Suite("Gemini Flash and Lite fallback - mocked HTTP")
struct GeminiFallbackTests {
    @Test func primaryTransientFailureReturnsSuccessfulLiteModel() async throws {
        for status in [408, 429, 500, 503] {
            let requests = FallbackRequests()
            let body = try fallbackEnvelope(["summary": "No fever was reported."])
            let service = try fallbackService(
                .init { request in
                    let count = await requests.append(request)
                    return .init(status: count == 1 ? status : 200, data: count == 1 ? Data() : body)
                })
            let result = try await service.summarize(fallbackInput)
            #expect(result.model == "gemini-flash-lite-latest")
            let sent = await requests.values
            #expect(sent.count == 2)
            #expect(sent[0].url?.path.hasSuffix("gemini-flash-latest:generateContent") == true)
            #expect(sent[1].url?.path.hasSuffix("gemini-flash-lite-latest:generateContent") == true)
            #expect(sent.allSatisfy { $0.timeoutInterval == 35 })
        }
    }

    @Test func exhaustedLiteIsMarkedAndLiteOnlyRetrySendsOneCall() async throws {
        for fallbackOnly in [false, true] {
            for status in [429, 503] {
                let requests = FallbackRequests()
                let service = try fallbackService(
                    .init { request in
                        _ = await requests.append(request)
                        return .init(status: status, data: Data("private upstream detail".utf8))
                    })
                do {
                    _ = try await service.summarize(fallbackInput, fallbackOnly: fallbackOnly)
                    Issue.record("Expected provider failure")
                } catch let error as Abort {
                    #expect(error.status.code == UInt(status))
                    #expect(error.headers.first(name: "X-Reva-Gemini-Fallback") == "true")
                    #expect(error.headers.first(name: .retryAfter) == "60")
                    #expect(!error.reason.contains("private upstream detail"))
                }
                let sent = await requests.values
                #expect(sent.count == (fallbackOnly ? 1 : 2))
                #expect(sent.last?.url?.path.hasSuffix("gemini-flash-lite-latest:generateContent") == true)
            }
        }
    }

    @Test func permanentAndStructuredOutputFailuresDoNotFallback() async throws {
        let invalidBody = try fallbackEnvelope(["summary": "No fever — was reported."])
        for status in [400, 401, 403, 404, 200] {
            let requests = FallbackRequests()
            let service = try fallbackService(
                .init { request in
                    _ = await requests.append(request)
                    return .init(status: status, data: invalidBody)
                })
            do {
                _ = try await service.summarize(fallbackInput)
                Issue.record("Expected terminal failure")
            } catch let error as Abort {
                #expect([.unprocessableEntity, .failedDependency].contains(error.status))
                #expect(error.headers.first(name: "X-Reva-Gemini-Fallback") == nil)
            }
            #expect(await requests.values.count == 1)
        }
    }

    @Test func cancellationNeverTriggersFallback() async throws {
        let requests = FallbackRequests()
        let service = try fallbackService(
            .init { request in
                _ = await requests.append(request)
                throw CancellationError()
            })
        await #expect(throws: CancellationError.self) { try await service.summarize(fallbackInput) }
        #expect(await requests.values.count == 1)
    }

    // MARK: - Optional titles are strict generated prose; source punctuation stays untouched
    @Test func titlesRequireExplicitRequestAndPlainBoundedOutput() async throws {
        let input = GeminiSummaryRequest(
            recordID: "source", title: "Source title", text: "Original source — no fever.",
            generateTitle: true, date: "2026-09-12")
        let requests = FallbackRequests()
        let body = try fallbackEnvelope(["summary": "No fever was reported.", "title": "Fever discussion"])
        let service = try fallbackService(
            .init { request in
                _ = await requests.append(request)
                return .init(status: 200, data: body)
            })
        let result = try await service.summarize(input)
        #expect(result.title == "Fever discussion")
        #expect(result.model == "gemini-flash-latest")
        let sent = try #require(await requests.values.first?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        let contents = try #require(payload["contents"] as? [[String: Any]])
        let sourceJSON = try #require((contents.first?["parts"] as? [[String: String]])?.first?["text"])
        let decoded = try JSONDecoder().decode(GeminiSummaryRequest.self, from: Data(sourceJSON.utf8))
        #expect(decoded.text == input.text && decoded.date == input.date && decoded.generateTitle == true)
        for title in [
            "", String(repeating: "é", count: 61), "First\nSecond", "**Decorated**", "Fever — discussion",
        ] {
            let invalid = try fallbackEnvelope(["summary": "No fever was reported.", "title": title])
            let invalidService = try fallbackService(.init { _ in .init(status: 200, data: invalid) })
            await #expect(throws: Abort.self) { try await invalidService.summarize(input) }
        }
        await #expect(throws: Abort.self) { try await service.summarize(fallbackInput) }
        let missing = try fallbackEnvelope(["summary": "No fever was reported."])
        let missingService = try fallbackService(.init { _ in .init(status: 200, data: missing) })
        await #expect(throws: Abort.self) { try await missingService.summarize(input) }
    }

    @Test func boundedFallbackHeaderNeverAcceptsArbitraryModels() throws {
        #expect(try geminiFallbackHeader([:]) == false)
        #expect(try geminiFallbackHeader(["X-Reva-Gemini-Fallback": "true"]) == true)
        for value in ["false", "gemini-custom", "true,true", "TRUE", "true "] {
            #expect(throws: Abort.self) { try geminiFallbackHeader(["X-Reva-Gemini-Fallback": value]) }
        }
        #expect(throws: Abort.self) {
            try GeminiSummaryRequest(
                recordID: "source", title: "Title", text: "Text", date: String(repeating: "x", count: 41)
            ).validate()
        }
    }
}
