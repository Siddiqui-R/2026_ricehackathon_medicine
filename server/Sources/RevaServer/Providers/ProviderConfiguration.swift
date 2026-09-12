import Foundation

/// Derived only from the environment supplied to ServerConfiguration; never sent to a client.
public struct ProviderConfiguration: Sendable {
    public let geminiAPIKey: String?
    public let geminiModel: String
    public let openAIAPIKey: String?
    public let transcriptionModel: String
    public let elevenLabsAPIKey: String?
    public let elevenLabsAgentID: String?
    public let elevenLabsPhoneNumberID: String?
    public let liveCallsEnabled: Bool
    public let paidAccessAllowed: Bool

    public var geminiConfigured: Bool { paidAccessAllowed && geminiAPIKey != nil }
    public var transcriptionConfigured: Bool { paidAccessAllowed && openAIAPIKey != nil && transcriptionModel == "whisper-1" }
    public var bookingConfigured: Bool {
        paidAccessAllowed && elevenLabsAPIKey != nil && elevenLabsAgentID != nil && elevenLabsPhoneNumberID != nil
    }

    public init(environment: [String: String], paidAccessAllowed: Bool) throws {
        self.paidAccessAllowed = paidAccessAllowed
        geminiAPIKey = try Self.secret(environment["GEMINI_API_KEY"], name: "GEMINI_API_KEY")
        openAIAPIKey = try Self.secret(environment["OPENAI_API_KEY"], name: "OPENAI_API_KEY")
        elevenLabsAPIKey = try Self.secret(environment["ELEVENLABS_API_KEY"], name: "ELEVENLABS_API_KEY")
        elevenLabsAgentID = try Self.identifier(environment["ELEVENLABS_AGENT_ID"], name: "ELEVENLABS_AGENT_ID")
        elevenLabsPhoneNumberID = try Self.identifier(environment["ELEVENLABS_PHONE_NUMBER_ID"], name: "ELEVENLABS_PHONE_NUMBER_ID")
        geminiModel = environment["GEMINI_MODEL"] ?? "gemini-2.5-flash"
        guard geminiModel.hasPrefix("gemini-"), geminiModel.utf8.count <= 100,
              geminiModel.utf8.allSatisfy({ Self.identifierByte($0) || $0 == 46 }) else {
            throw ConfigurationError("GEMINI_MODEL must be a Gemini model ID using only letters, digits, hyphens, underscores and dots.")
        }
        transcriptionModel = environment["OPENAI_TRANSCRIPTION_MODEL"] ?? "whisper-1"
        guard transcriptionModel == "whisper-1" else {
            throw ConfigurationError("OPENAI_TRANSCRIPTION_MODEL must be whisper-1 for the MVP timestamped transcript contract.")
        }
        let enabled = environment["REVA_ENABLE_LIVE_CALLS"] ?? "false"
        guard ["true", "false"].contains(enabled) else { throw ConfigurationError("REVA_ENABLE_LIVE_CALLS must be exactly true or false.") }
        liveCallsEnabled = enabled == "true" && paidAccessAllowed
    }

    private static func secret(_ value: String?, name: String) throws -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard value.utf8.count <= 2048, value.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ConfigurationError("\(name) must contain visible ASCII characters without whitespace (maximum 2048 bytes).")
        }
        return value
    }

    private static func identifier(_ value: String?, name: String) throws -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard value.utf8.count <= 200, value.utf8.allSatisfy(identifierByte) else {
            throw ConfigurationError("\(name) must be a provider ID using letters, digits, hyphens and underscores.")
        }
        return value
    }

    private static func identifierByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }
}
