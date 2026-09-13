// Purpose: Translate authenticated audio requests into timestamped transcription.
// Inputs: Raw audio with safe filename and content-type headers.
// Outputs: Timestamped transcription DTOs with an explicit request-body limit.
// Side effects: Sends audio to the configured transcription provider; no audio is persisted here.
// Ownership: The route group must authenticate owners before audio reaches the provider.

import Foundation
import Vapor

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Authenticated service composition
func registerVoiceProviderRoutes(
    _ secured: any RoutesBuilder, configuration: ProviderConfiguration,
    transport: VoiceHTTPTransport = .live
) {
    let transcription = VoiceTranscriptionService(configuration: configuration, transport: transport)
    let realtime = RealtimeTranscriptionService(configuration: configuration, transport: transport)
    secured.on(.POST, "audio", "realtime-token", body: .collect(maxSize: "1kb")) {
        request async throws -> Response in
        _ = try request.auth.require(OwnerIdentity.self)
        guard request.body.data?.readableBytes ?? 0 == 0 else {
            throw Abort(.badRequest, reason: "This operation does not accept a request body.")
        }
        let token = try await realtime.createToken()
        let response = Response(status: .ok)
        try response.content.encode(token)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
    // MARK: - Raw audio intake with required metadata and a 16 MiB body limit
    secured.on(.POST, "audio", "transcribe", body: .collect(maxSize: "16mb")) {
        request async throws -> VoiceTranscriptionResponse in
        _ = try request.auth.require(OwnerIdentity.self)
        guard let bytes = request.body.data, let filename = request.headers.first(name: "X-Filename"),
            let rawType = request.headers.first(name: .contentType)
        else {
            throw Abort(.badRequest, reason: "Provide raw audio bytes, Content-Type, and X-Filename.")
        }
        let type = rawType.split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        return try await transcription.transcribe(
            audio: Data(bytes.readableBytesView), filename: filename, contentType: type)
    }
}

// MARK: - One-use browser access; the account's provider secret remains on the server
struct RealtimeTranscriptionToken: Content, Sendable {
    let token: String
}

struct RealtimeTranscriptionService: Sendable {
    let configuration: ProviderConfiguration
    let transport: VoiceHTTPTransport

    func createToken() async throws -> RealtimeTranscriptionToken {
        guard configuration.realtimeTranscriptionConfigured, let key = configuration.elevenLabsAPIKey else {
            throw Abort(.serviceUnavailable, reason: "Live transcription is not configured on the server.")
        }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let response: VoiceHTTPResponse
        do { response = try await transport.send(request) } catch {
            throw Abort(.badGateway, reason: "Live transcription is unavailable. Your recording can continue.")
        }
        let data = try VoiceProviderLimits.responseData(response)
        guard data.count <= 16_384,
            let result = try? JSONDecoder().decode(RealtimeTranscriptionToken.self, from: data),
            !result.token.isEmpty, result.token.utf8.count <= 8192,
            result.token.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw Abort(.badGateway, reason: "The live transcription service returned an invalid session.") }
        return result
    }
}
