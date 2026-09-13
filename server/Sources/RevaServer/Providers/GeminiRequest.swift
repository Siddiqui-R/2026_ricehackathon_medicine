// Purpose: Send Flash requests with one immediate fixed Lite fallback after technical failure.
// Inputs: Server-generated payload, a server key and the bounded Lite-only request flag.
// Outputs: Response bytes with the successful model, or sanitized errors with Lite retry metadata.
// Side effects: At most two 35-second provider calls. Caller cancellation prevents fallback.

import Foundation
import Vapor

// MARK: - The server owns both model choices; a client can only request the Lite fallback
extension GeminiService {
    static let fallbackModel = "gemini-flash-lite-latest"

    func sendGemini(payload: JSONValue, key: String, fallbackOnly: Bool) async throws
        -> (response: GeminiHTTPResponse, model: String)
    {
        let models = fallbackOnly ? [Self.fallbackModel] : [configuration.geminiModel, Self.fallbackModel]
        let body = try JSONEncoder().encode(payload)
        for (index, model) in models.enumerated() {
            try Task.checkCancellation()
            do {
                let response = try await sendGeminiAttempt(model: model, key: key, body: body)
                try Task.checkCancellation()
                return (response, model)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                guard let failure = error as? Abort,
                    [.serviceUnavailable, .tooManyRequests].contains(failure.status)
                else { throw error }
                if index + 1 < models.count { continue }
                var headers = failure.headers
                let delay = Int(headers.first(name: .retryAfter) ?? "") ?? 60
                headers.replaceOrAdd(name: .retryAfter, value: String(max(60, delay)))
                headers.replaceOrAdd(name: "X-Reva-Gemini-Fallback", value: "true")
                throw Abort(failure.status, headers: headers, reason: failure.reason)
            }
        }
        throw invalidResponse()
    }

    // MARK: - One fixed-host attempt; malformed successful content remains a terminal validation error
    private func sendGeminiAttempt(model: String, key: String, body: Data) async throws -> GeminiHTTPResponse
    {
        guard
            let url = URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        else { throw invalidResponse() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body
        let response: GeminiHTTPResponse
        do { response = try await transport.send(request) } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if error is GeminiResponseTooLarge { throw invalidResponse() }
            throw Abort(
                .serviceUnavailable, reason: "Gemini could not be reached. Your saved data is unchanged.")
        }
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw geminiFailure(response) }
        return response
    }
}
