// Purpose: Distinguish permanent Gemini request/configuration failures from retryable outages.
// Inputs: Bounded upstream status/body bytes, never a trusted provider message.
// Outputs: Fixed sanitized HTTP errors; upstream credentials/source text are never exposed.
// Side effects: None. Only documented status and API-key reason codes influence classification.

import Foundation
import Vapor

// MARK: - Safe failure categories shared by every Gemini operation
func geminiFailure(_ response: GeminiHTTPResponse) -> Abort {
    if response.status == 429 {
        return Abort(
            .tooManyRequests, headers: ["Retry-After": "60"],
            reason: "Gemini's rate or quota limit was reached. Try again later.")
    }
    if response.status == 408 || response.status >= 500 {
        return Abort(
            .serviceUnavailable,
            reason: "Gemini is temporarily unavailable. Your saved data is unchanged.")
    }
    let details =
        response.data.count <= 65_536
        ? try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: response.data) : nil
    let keyReasons = [
        "API_KEY_INVALID", "API_KEY_EXPIRED", "API_KEY_SERVICE_BLOCKED",
        "API_KEY_HTTP_REFERRER_BLOCKED", "API_KEY_IP_ADDRESS_BLOCKED",
    ]
    if details?.error?.details?.contains(where: { keyReasons.contains($0.reason ?? "") }) == true {
        return Abort(
            .failedDependency,
            reason:
                "Gemini rejected the server API key or its restrictions. Update the server's provider configuration."
        )
    }
    if details?.error?.status == "FAILED_PRECONDITION" {
        return Abort(
            .failedDependency,
            reason:
                "Gemini's setup requirements are not met. Check the server project's region and billing configuration."
        )
    }
    if response.status == 401 || response.status == 403 {
        return Abort(
            .failedDependency,
            reason:
                "The server's Gemini credentials do not have access to this operation. Check the API key and its permissions."
        )
    }
    if response.status == 404 {
        return Abort(
            .failedDependency,
            reason: "The configured Gemini model is unavailable. Check the server's model configuration.")
    }
    if [400, 413, 415, 422].contains(response.status) {
        return Abort(
            .unprocessableEntity,
            reason:
                "Gemini could not process this request (HTTP \(response.status)). Check the request format and model settings."
        )
    }
    return Abort(
        .failedDependency,
        reason:
            "Gemini rejected this operation (HTTP \(response.status)). Check the server's provider configuration."
    )
}

// MARK: - Intentionally omit raw messages and metadata from decoding
private struct GeminiErrorEnvelope: Decodable {
    struct Failure: Decodable {
        struct Detail: Decodable { let reason: String? }
        let status: String?
        let details: [Detail]?
    }
    let error: Failure?
}
