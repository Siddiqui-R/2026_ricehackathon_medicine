import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

struct VoiceHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

/// A small injectable boundary. Tests replace send; the default never retries a provider request.
struct VoiceHTTPTransport: Sendable {
    let send: @Sendable (URLRequest) async throws -> VoiceHTTPResponse

    static let live = VoiceHTTPTransport { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: VoiceNoRedirectDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return VoiceHTTPResponse(statusCode: http.statusCode, body: data)
    }
}

/// Keep credentials on the fixed provider host even if its response contains a redirect.
private final class VoiceNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum VoiceProviderLimits {
    static let audioBytes = 16 * 1024 * 1024
    static let responseBytes = 4 * 1024 * 1024
    static let transcriptCharacters = 200_000
    static let allowedAudioTypes: Set<String> = ["audio/mp4", "audio/m4a", "audio/wav", "audio/mpeg"]

    static func validateAudio(_ audio: Data, filename: String, contentType: String) throws {
        guard !audio.isEmpty else { throw Abort(.badRequest, reason: "Provide nonempty audio bytes.") }
        guard audio.count <= audioBytes else { throw Abort(.payloadTooLarge, reason: "Audio exceeds the 16 MiB transcription limit.") }
        guard allowedAudioTypes.contains(contentType) else {
            throw Abort(.unsupportedMediaType, reason: "Transcription accepts audio/mp4, audio/m4a, audio/wav, or audio/mpeg.")
        }
        guard !filename.isEmpty, filename.count <= 180, filename != ".", filename != "..",
              filename.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [32, 40, 41, 45, 46, 95].contains(byte)
              }) else { throw Abort(.badRequest, reason: "X-Filename must be a safe flat ASCII audio filename.") }
    }

    static func responseData(_ response: VoiceHTTPResponse) throws -> Data {
        guard (200..<300).contains(response.statusCode) else {
            throw Abort(.badGateway, reason: "The voice provider rejected the request. Check its configuration and account status.")
        }
        guard !response.body.isEmpty, response.body.count <= responseBytes else {
            throw Abort(.badGateway, reason: "The voice provider returned an empty or oversized response.")
        }
        return response.body
    }
}
