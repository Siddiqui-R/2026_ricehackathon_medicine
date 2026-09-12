import Vapor

struct ProviderStatus: Content {
    struct Service: Codable, Sendable { let configured: Bool; let model: String }
    let gemini: Service
    let transcription: Service
    let booking: Service
    let liveCallsEnabled: Bool
}

func registerProviderRoutes(_ secured: any RoutesBuilder, configuration: ProviderConfiguration,
                            directory: URL, geminiTransport: GeminiHTTPTransport = .live) {
    secured.get("providers") { _ async -> ProviderStatus in
        ProviderStatus(gemini: .init(configured: configuration.geminiConfigured, model: configuration.geminiModel),
                       transcription: .init(configured: configuration.transcriptionConfigured, model: configuration.transcriptionModel),
                       booking: .init(configured: configuration.bookingConfigured, model: "elevenlabs-agent"),
                       liveCallsEnabled: configuration.liveCallsEnabled)
    }
    let gemini = GeminiService(configuration: configuration, transport: geminiTransport)
    secured.on(.POST, "ai", "summarize", body: .collect(maxSize: "256kb")) { request async throws -> GeminiSummaryResponse in
        try requireProviderJSON(request)
        let input: GeminiSummaryRequest
        do { input = try request.content.decode(GeminiSummaryRequest.self) }
        catch { throw Abort(.badRequest, reason: "Expected recordID, title and text strings for Gemini summary.") }
        return try await gemini.summarize(input)
    }
    secured.on(.POST, "ai", "prepare", body: .collect(maxSize: "1mb")) { request async throws -> GeminiPreparationResponse in
        try requireProviderJSON(request)
        let input: GeminiPreparationRequest
        do { input = try request.content.decode(GeminiPreparationRequest.self) }
        catch { throw Abort(.badRequest, reason: "Expected a visit object and candidate record objects for Gemini preparation.") }
        return try await gemini.prepare(input)
    }
    registerVoiceProviderRoutes(secured, configuration: configuration, directory: directory)
}

private func requireProviderJSON(_ request: Request) throws {
    guard let type = request.headers.contentType, type.type.lowercased() == "application", type.subType.lowercased() == "json" else {
        throw Abort(.unsupportedMediaType, reason: "Provider JSON requests require application/json.")
    }
}
