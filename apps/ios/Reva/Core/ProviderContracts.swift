// Purpose: Define the native wire values exchanged with the Reva provider API.
// Inputs: Encoded request fields and decoded provider responses.
// Outputs: Typed capabilities, summaries, preparation, transcripts.
// Side effects: None; provider credentials never belong in these values.

import Foundation

// MARK: - Service configuration values
// Capabilities report server setup flags, not a successful live credential probe.
struct ProviderCapability: Codable, Equatable {
    var configured: Bool
    var model: String
}
struct ProviderStatus: Codable, Equatable {
    var gemini: ProviderCapability
    var transcription: ProviderCapability
}
// MARK: - AI results
// Summaries and preparation results carry model labels and supplied source IDs.
struct AISummary: Codable {
    var summary: String
    var model: String
}
struct AIPreparation: Codable {
    var overview: String
    var questions: [String]
    var selectedRecordIDs: [String]
    var model: String
}
// MARK: - Speech results
// Reconcile transcript segments against the saved recording before accepting them.
struct AudioTranscription: Codable {
    var text: String
    var segments: [TranscriptSegment]
    var model: String
}
