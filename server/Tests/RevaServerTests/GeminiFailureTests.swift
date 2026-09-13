// Purpose: Verify Gemini HTTP classification preserves permanent failures and sanitizes provider detail.
// Inputs: Mocked upstream codes and synthetic error bodies with deliberately sensitive-looking text.
// Outputs: Assertions on 422/424/429/503 and request compatibility without external requests.
// Side effects: None; no server storage, credentials or network access is needed.

import Foundation
import Testing
import Vapor

@testable import RevaServer

// MARK: - Permanent provider failures never trigger session expiry or outage retries
@Suite("Gemini failure categories — mocked HTTP only")
struct GeminiFailureTests {
    @Test func classifiesPermanentAndTransientResponsesWithoutExposingRawBody() throws {
        let secret = "source-text-and-provider-secret"
        let cases: [(Int, HTTPResponseStatus)] = [
            (400, .unprocessableEntity), (401, .failedDependency), (403, .failedDependency),
            (404, .failedDependency), (413, .unprocessableEntity), (415, .unprocessableEntity),
            (422, .unprocessableEntity), (429, .tooManyRequests), (408, .serviceUnavailable),
            (500, .serviceUnavailable), (503, .serviceUnavailable), (504, .serviceUnavailable),
        ]
        for (code, expected) in cases {
            let error = geminiFailure(.init(status: code, data: Data(secret.utf8)))
            #expect(error.status == expected)
            #expect(!error.reason.contains(secret))
            #expect(!error.reason.contains("credits"))
            if code == 429 { #expect(error.headers.first(name: .retryAfter) == "60") }
        }
    }

    @Test func usesOnlyDocumentedStatusAndKeyCodesFromErrorBody() throws {
        for (fields, expectedText) in [
            (["status": "FAILED_PRECONDITION"] as [String: Any], "region and billing"),
            (["details": [["reason": "API_KEY_INVALID"]]] as [String: Any], "API key"),
        ] {
            var error = fields
            error["message"] = "source-text-and-provider-secret"
            let data = try JSONSerialization.data(withJSONObject: ["error": error])
            let result = geminiFailure(.init(status: 400, data: data))
            #expect(result.status == .failedDependency)
            #expect(result.reason.contains(expectedText))
            #expect(!result.reason.contains("source-text-and-provider-secret"))
        }
        let data = Data(String(repeating: "x", count: 65_537).utf8)
        #expect(geminiFailure(.init(status: 400, data: data)).status == .unprocessableEntity)
    }
}
