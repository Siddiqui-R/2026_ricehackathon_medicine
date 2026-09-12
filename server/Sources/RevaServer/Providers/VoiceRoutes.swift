import Foundation
import Vapor

func registerVoiceProviderRoutes(_ secured: any RoutesBuilder, configuration: ProviderConfiguration, directory: URL,
                                 transport: VoiceHTTPTransport = .live) {
    let transcription = VoiceTranscriptionService(configuration: configuration, transport: transport)
    let calls = VoiceCallService(configuration: configuration, directory: directory, transport: transport)
    secured.on(.POST, "audio", "transcribe", body: .collect(maxSize: "16mb")) { request async throws -> VoiceTranscriptionResponse in
        _ = try request.auth.require(OwnerIdentity.self)
        guard let bytes = request.body.data, let filename = request.headers.first(name: "X-Filename"),
              let rawType = request.headers.first(name: .contentType) else {
            throw Abort(.badRequest, reason: "Provide raw audio bytes, Content-Type, and X-Filename.")
        }
        let type = rawType.split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        return try await transcription.transcribe(audio: Data(bytes.readableBytesView), filename: filename, contentType: type)
    }
    secured.on(.POST, "booking", "call", body: .collect(maxSize: "32kb")) { request async throws -> VoiceBookingCallResponse in
        let owner = try request.auth.require(OwnerIdentity.self).id
        guard request.headers.contentType?.type == "application", request.headers.contentType?.subType == "json" else {
            throw Abort(.unsupportedMediaType, reason: "Call requests require application/json.")
        }
        let call: VoiceBookingCallRequest
        do { call = try request.content.decode(VoiceBookingCallRequest.self) }
        catch { throw Abort(.badRequest, reason: "Provide the complete call request and explicit consent.") }
        return try await calls.start(owner: owner, call: call)
    }
    secured.get("booking", "call", ":requestID") { request async throws -> VoiceBookingCallDetails in
        let owner = try request.auth.require(OwnerIdentity.self).id
        guard let id = request.parameters.get("requestID") else { throw Abort(.badRequest, reason: "A call request ID is required.") }
        return try await calls.details(owner: owner, requestID: id)
    }
}
