// Purpose: Adapt saved audio to Whisper multipart input and return a reviewable timed transcript.
// Inputs: Audio bytes, safe filename/content type, private provider configuration, and an injectable transport.
// Outputs: Nonempty bounded transcript segments with recording-relative times and neutral speaker labels.
// Side effects: Sends one configured OpenAI transcription request. Original audio and client state are untouched.
// Boundary: Only whisper-1 verbose_json is supported. Invalid timestamps or empty speech fail without invented content.

import Foundation
import Vapor

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Native transcript response and recording-relative segment times
struct VoiceTranscriptSegment: Content, Sendable, Equatable {
    let id: String
    let start: Double
    let end: Double
    let speaker: String
    let text: String
}

struct VoiceTranscriptionResponse: Content, Sendable, Equatable {
    let text: String
    let segments: [VoiceTranscriptSegment]
    let model: String
}

// MARK: - Whisper service boundary
/// Official schema: https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create
/// This adapter deliberately preserves whisper-1 and its verbose_json segment timestamps.
struct VoiceTranscriptionService: Sendable {
    let configuration: ProviderConfiguration
    let transport: VoiceHTTPTransport

    init(configuration: ProviderConfiguration, transport: VoiceHTTPTransport = .live) {
        self.configuration = configuration
        self.transport = transport
    }

    // MARK: - Gate provider access and build exact multipart audio input
    func transcribe(audio: Data, filename: String, contentType: String) async throws
        -> VoiceTranscriptionResponse
    {
        guard configuration.paidAccessAllowed, let key = configuration.openAIAPIKey, !key.isEmpty,
            configuration.transcriptionModel == "whisper-1"
        else {
            throw Abort(
                .serviceUnavailable,
                reason:
                    "Transcription is not configured. Set private server tokens, OPENAI_API_KEY, and OPENAI_TRANSCRIPTION_MODEL=whisper-1."
            )
        }
        try VoiceProviderLimits.validateAudio(audio, filename: filename, contentType: contentType)
        try Task.checkCancellation()
        let boundary = "RevaAudio-" + UUID().uuidString
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (name, value) in [
            ("model", "whisper-1"), ("response_format", "verbose_json"),
            ("timestamp_granularities[]", "segment"),
        ] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n"
        )
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        // MARK: - Send once and validate transcript shape before returning any result
        let response: VoiceHTTPResponse
        do { response = try await transport.send(request) } catch {
            throw Abort(
                .badGateway,
                reason: "The transcription provider could not be reached. Your saved audio remains available."
            )
        }
        let data = try VoiceProviderLimits.responseData(response)
        let decoded: WhisperResponse
        do { decoded = try JSONDecoder().decode(WhisperResponse.self, from: data) } catch {
            throw Abort(.badGateway, reason: "The transcription provider returned invalid transcript data.")
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw Abort(
                .unprocessableEntity,
                reason: "No speech was transcribed. Review the saved audio before trying again.")
        }
        guard text.count <= VoiceProviderLimits.transcriptCharacters,
            decoded.duration.isFinite, decoded.duration > 0, decoded.duration <= 24 * 60 * 60,
            let segments = decoded.segments, !segments.isEmpty, segments.count <= 10_000,
            Set(segments.map(\.id)).count == segments.count
        else {
            throw Abort(
                .badGateway,
                reason: "The transcription provider did not return usable bounded segment timestamps.")
        }
        // MARK: - Validate ordered source offsets without inventing speaker identity
        var previousStart: Double = 0
        var totalCharacters = 0
        var result: [VoiceTranscriptSegment] = []
        for segment in segments {
            let words = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            totalCharacters += words.count
            guard segment.id >= 0, segment.start.isFinite, segment.end.isFinite,
                segment.start >= previousStart, segment.end >= segment.start,
                segment.end <= decoded.duration + 1,
                !words.isEmpty, totalCharacters <= VoiceProviderLimits.transcriptCharacters
            else {
                throw Abort(
                    .badGateway,
                    reason: "The transcription provider returned invalid segment text or timestamps.")
            }
            previousStart = segment.start
            result.append(
                VoiceTranscriptSegment(
                    id: "whisper-segment-\(segment.id)", start: segment.start, end: segment.end,
                    speaker: "Speaker", text: words))
        }
        // Whisper does not identify speakers; a neutral label avoids inventing diarization.
        return VoiceTranscriptionResponse(text: text, segments: result, model: "whisper-1")
    }
}

// MARK: - Minimal verbose-json provider schema
private struct WhisperResponse: Decodable {
    let text: String
    let duration: Double
    let segments: [WhisperSegment]?
}

private struct WhisperSegment: Decodable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}
