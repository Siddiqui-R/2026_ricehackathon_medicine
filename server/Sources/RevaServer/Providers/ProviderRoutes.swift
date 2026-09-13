// Purpose: Register authenticated provider discovery and Gemini JSON endpoints, then attach voice routes.
// Inputs: An already owner-authenticated /v1 route group, server provider settings, and injectable transports.
// Outputs: Public configuration flags or validated summary/preparation/profile DTOs with bounded request bodies.
// Side effects: Creates provider services and dispatches configured AI requests when their routes are invoked.
// Boundary: Discovery exposes configuration status only. JSON/media validation occurs before service dispatch.

import Vapor

// MARK: - Public discovery contract without provider credentials
struct ProviderStatus: Content {
    struct Service: Codable, Sendable {
        let configured: Bool
        let model: String
    }
    let gemini: Service
    let transcription: Service
    let realtimeTranscription: Service
}

// MARK: - Register discovery and bounded JSON operations
func registerProviderRoutes(
    _ secured: any RoutesBuilder, configuration: ProviderConfiguration,
    geminiTransport: GeminiHTTPTransport = .live
) {
    secured.get("providers") { _ async -> ProviderStatus in
        ProviderStatus(
            gemini: .init(configured: configuration.geminiConfigured, model: configuration.geminiModel),
            transcription: .init(
                configured: configuration.transcriptionConfigured, model: configuration.transcriptionModel),
            realtimeTranscription: .init(
                configured: configuration.realtimeTranscriptionConfigured, model: "scribe_v2_realtime"))
    }
    // MARK: - Decode requests before handing source data to Gemini
    let gemini = GeminiService(configuration: configuration, transport: geminiTransport)
    secured.on(.POST, "ai", "summarize", body: .collect(maxSize: "256kb")) {
        request async throws -> GeminiSummaryResponse in
        try requireProviderJSON(request)
        let fallbackOnly = try geminiFallbackHeader(request.headers)
        let input: GeminiSummaryRequest
        do { input = try request.content.decode(GeminiSummaryRequest.self) } catch {
            throw Abort(.badRequest, reason: "Expected recordID, title and text strings for Gemini summary.")
        }
        return try await gemini.summarize(input, fallbackOnly: fallbackOnly)
    }
    secured.on(.POST, "ai", "prepare", body: .collect(maxSize: "1mb")) {
        request async throws -> GeminiPreparationResponse in
        try requireProviderJSON(request)
        let fallbackOnly = try geminiFallbackHeader(request.headers)
        let input: GeminiPreparationRequest
        do { input = try request.content.decode(GeminiPreparationRequest.self) } catch {
            throw Abort(
                .badRequest,
                reason: "Expected a visit object and candidate record objects for Gemini preparation.")
        }
        return try await gemini.prepare(input, fallbackOnly: fallbackOnly)
    }
    secured.on(.POST, "ai", "profile", body: .collect(maxSize: "2mb")) {
        request async throws -> GeminiProfileResponse in
        try requireProviderJSON(request)
        let fallbackOnly = try geminiFallbackHeader(request.headers)
        let input: GeminiProfileRequest
        do { input = try request.content.decode(GeminiProfileRequest.self) } catch {
            throw Abort(
                .badRequest,
                reason: "Expected source report records with only id, version, title, date and text fields.")
        }
        return try await gemini.profile(input, fallbackOnly: fallbackOnly)
    }
    registerVoiceProviderRoutes(secured, configuration: configuration)
}

// MARK: - Require explicit JSON media type
private func requireProviderJSON(_ request: Request) throws {
    guard let type = request.headers.contentType, type.type.lowercased() == "application",
        type.subType.lowercased() == "json"
    else {
        throw Abort(.unsupportedMediaType, reason: "Provider JSON requests require application/json.")
    }
}

// MARK: - A bounded client flag selects only the fixed Lite fallback
func geminiFallbackHeader(_ headers: HTTPHeaders) throws -> Bool {
    let values = headers["X-Reva-Gemini-Fallback"]
    if values.isEmpty { return false }
    guard values == ["true"] else {
        throw Abort(.badRequest, reason: "X-Reva-Gemini-Fallback must be true when supplied.")
    }
    return true
}
