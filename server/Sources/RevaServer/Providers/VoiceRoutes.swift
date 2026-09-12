// Purpose: Translate authenticated audio requests into timestamped transcription.
// Inputs: Raw audio with safe filename and content-type headers.
// Outputs: Timestamped transcription DTOs with an explicit request-body limit.
// Side effects: Sends audio to the configured transcription provider; no audio is persisted here.
// Ownership: The route group must authenticate owners before audio reaches the provider.

import Foundation
import Vapor

// MARK: - Authenticated service composition
func registerVoiceProviderRoutes(
    _ secured: any RoutesBuilder, configuration: ProviderConfiguration,
    transport: VoiceHTTPTransport = .live
) {
    let transcription = VoiceTranscriptionService(configuration: configuration, transport: transport)
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
