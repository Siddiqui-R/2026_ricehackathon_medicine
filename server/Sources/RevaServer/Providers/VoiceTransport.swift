// Purpose: Share injectable voice HTTP I/O, audio input limits, and safe provider-response validation.
// Inputs: Adapter-built fixed-provider requests, or audio bytes with flat filename/content-type metadata.
// Outputs: HTTP status/body bytes or safe validation/provider errors for service callers.
// Side effects: Live transport creates an ephemeral URLSession and sends once without retry or redirect.
// Bounds: Timeouts constrain transport duration. Response byte limits are checked after URLSession collects the body.

import Foundation
import Vapor

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Injectable voice response contract
struct VoiceHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

/// A small injectable boundary. Tests replace send; the default never retries a provider request.
struct VoiceHTTPTransport: Sendable {
    let send: @Sendable (URLRequest) async throws -> VoiceHTTPResponse

    // MARK: - One ephemeral request with no automatic replay
    static let live = VoiceHTTPTransport { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(
            configuration: configuration, delegate: VoiceNoRedirectDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return VoiceHTTPResponse(statusCode: http.statusCode, body: data)
    }
}

// MARK: - Reject all provider redirects
/// Keep credentials on the fixed provider host even if its response contains a redirect.
private final class VoiceNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - Validate bounded audio metadata and provider responses
enum VoiceProviderLimits {
    static let audioBytes = 16 * 1024 * 1024
    static let responseBytes = 4 * 1024 * 1024
    static let transcriptCharacters = 200_000
    // Browser MediaRecorder originals keep their WebM/Ogg type through storage and Whisper upload.
    static let allowedAudioTypes: Set<String> = [
        "audio/mp4", "audio/m4a", "audio/wav", "audio/mpeg", "audio/webm", "audio/ogg",
    ]

    static func validateAudio(_ audio: Data, filename: String, contentType: String) throws {
        guard !audio.isEmpty else { throw Abort(.badRequest, reason: "Provide nonempty audio bytes.") }
        guard audio.count <= audioBytes else {
            throw Abort(.payloadTooLarge, reason: "Audio exceeds the 16 MiB transcription limit.")
        }
        guard allowedAudioTypes.contains(contentType) else {
            throw Abort(
                .unsupportedMediaType,
                reason:
                    "Transcription accepts audio/mp4, audio/m4a, audio/wav, audio/mpeg, audio/webm, or audio/ogg."
            )
        }
        guard !filename.isEmpty, filename.count <= 180, filename != ".", filename != "..",
            filename.utf8.allSatisfy({ byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                    || [32, 40, 41, 45, 46, 95].contains(byte)
            })
        else { throw Abort(.badRequest, reason: "X-Filename must be a safe flat ASCII audio filename.") }
    }

    // MARK: - Sanitize status errors before provider decoding
    // The body-size check is post-collection and is not a streaming transport memory cap.
    static func responseData(_ response: VoiceHTTPResponse) throws -> Data {
        guard (200..<300).contains(response.statusCode) else {
            throw Abort(
                .badGateway,
                reason: "The voice provider rejected the request. Check its configuration and account status."
            )
        }
        guard !response.body.isEmpty, response.body.count <= responseBytes else {
            throw Abort(.badGateway, reason: "The voice provider returned an empty or oversized response.")
        }
        return response.body
    }
}
