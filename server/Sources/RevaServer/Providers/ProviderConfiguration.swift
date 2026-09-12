// Purpose: Validate server-only provider secrets/model IDs and derive which integrations may be used.
// Inputs: Injected environment values and the private-authentication paidAccessAllowed decision.
// Outputs: Immutable settings and configuration flags, never a successful live credential probe.
// Side effects: None. Configuration neither contacts providers nor discloses keys to clients.
// Boundary: Public demo authentication cannot enable paid providers, even when provider keys are present.

import Foundation

// MARK: - Server-only provider configuration and public capability flags
/// Derived only from the environment supplied to ServerConfiguration; never sent to a client.
public struct ProviderConfiguration: Sendable {
    public let geminiAPIKey: String?
    public let geminiModel: String
    public let openAIAPIKey: String?
    public let transcriptionModel: String
    public let paidAccessAllowed: Bool

    public var geminiConfigured: Bool { paidAccessAllowed && geminiAPIKey != nil }
    public var transcriptionConfigured: Bool {
        paidAccessAllowed && openAIAPIKey != nil && transcriptionModel == "whisper-1"
    }
    // MARK: - Validate supported summary and transcription models
    public init(environment: [String: String], paidAccessAllowed: Bool) throws {
        self.paidAccessAllowed = paidAccessAllowed
        geminiAPIKey = try Self.secret(environment["GEMINI_API_KEY"], name: "GEMINI_API_KEY")
        openAIAPIKey = try Self.secret(environment["OPENAI_API_KEY"], name: "OPENAI_API_KEY")
        geminiModel = environment["GEMINI_MODEL"] ?? "gemini-3.8-flash"
        guard geminiModel.hasPrefix("gemini-"), geminiModel.utf8.count <= 100,
            geminiModel.utf8.allSatisfy({ Self.identifierByte($0) || $0 == 46 })
        else {
            throw ConfigurationError(
                "GEMINI_MODEL must be a Gemini model ID using only letters, digits, hyphens, underscores and dots."
            )
        }
        transcriptionModel = environment["OPENAI_TRANSCRIPTION_MODEL"] ?? "whisper-1"
        guard transcriptionModel == "whisper-1" else {
            throw ConfigurationError(
                "OPENAI_TRANSCRIPTION_MODEL must be whisper-1 for the MVP timestamped transcript contract.")
        }

    }

    // MARK: - Reject unsafe secret and model-ID encodings
    private static func secret(_ value: String?, name: String) throws -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard value.utf8.count <= 2048, value.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ConfigurationError(
                "\(name) must contain visible ASCII characters without whitespace (maximum 2048 bytes).")
        }
        return value
    }

    private static func identifierByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
            || byte == 95
    }
}
