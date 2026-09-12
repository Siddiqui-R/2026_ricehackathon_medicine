import Foundation

struct ProviderCapability: Codable, Equatable {
    var configured: Bool
    var model: String
}
struct ProviderStatus: Codable, Equatable {
    var gemini: ProviderCapability
    var transcription: ProviderCapability
    var booking: ProviderCapability
    var liveCallsEnabled: Bool
}
struct AISummary: Codable { var summary: String; var model: String }
struct AIPreparation: Codable {
    var overview: String
    var questions: [String]
    var selectedRecordIDs: [String]
    var model: String
}
struct AudioTranscription: Codable {
    var text: String
    var segments: [TranscriptSegment]
    var model: String
}
struct LiveCallResult: Codable {
    var conversationID: String
    var status: String
    var provider: String
    var transcript: String?
}
struct LiveCallInput: Encodable {
    var requestID: String
    var clinic: String
    var phone: String
    var reason: String
    var earliest: String
    var latest: String
    var timeZone: String
    var preferences: String
    var patientName: String
    var consent: Bool
}
private struct ProviderErrorBody: Decodable { var reason: String? }

enum ProviderFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// Shared wire boundary. Provider secrets and provider-specific SDKs stay on the Swift server.
struct ProviderClient {
    let baseURL: URL
    let token: String
    var session: URLSession
    init(url: String, token: String, session: URLSession = .shared) throws {
        guard let base = URL(string: url) else { throw RevaError.invalid("Enter a valid server URL.") }
        _ = try ServerClient(baseURL: base, token: token, session: session)
        self.baseURL = base; self.token = token; self.session = session
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", bytes: Data? = nil,
                                       contentType: String = "application/json", filename: String? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/" + path))
        request.httpMethod = method; request.httpBody = bytes; request.timeoutInterval = 110
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let filename { request.setValue(ServerClient.attachmentMetadataName(filename), forHTTPHeaderField: "X-Filename") }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw ProviderFailure.message("The provider server response was unreadable.") }
        guard (200..<300).contains(response.statusCode) else {
            let reason = (try? JSONDecoder().decode(ProviderErrorBody.self, from: data))?.reason
            throw ProviderFailure.message(reason ?? "The connected service returned HTTP \(response.statusCode). Your local source is unchanged.")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ProviderFailure.message("The connected service returned an unsupported response. Your original source is unchanged.") }
    }
    func status() async throws -> ProviderStatus { try await request("providers") }
    func summarize(_ record: MedicalRecord) async throws -> AISummary {
        struct Input: Encodable { let recordID: String; let title: String; let text: String }
        return try await request("ai/summarize", method: "POST", bytes: JSONEncoder().encode(Input(recordID: record.id, title: record.title, text: record.text)))
    }
    func prepare(_ visit: Visit, records: [MedicalRecord]) async throws -> AIPreparation {
        struct VisitInput: Encodable { let id: String; let type: String; let concern: String; let goal: String; let questions: [String] }
        struct RecordInput: Encodable { let id: String; let title: String; let date: String; let text: String; let summary: String; let version: Int }
        struct Input: Encodable { let visit: VisitInput; let records: [RecordInput] }
        let input = Input(visit: .init(id: visit.id, type: visit.type, concern: visit.concern, goal: visit.goal, questions: visit.questions),
                          records: records.map { .init(id: $0.id, title: $0.title, date: $0.date, text: $0.text, summary: $0.summary, version: $0.version) })
        return try await request("ai/prepare", method: "POST", bytes: JSONEncoder().encode(input))
    }
    func transcribe(bytes: Data, filename: String) async throws -> AudioTranscription {
        guard !bytes.isEmpty, bytes.count <= 16 * 1024 * 1024 else { throw RevaError.invalid("Choose a nonempty recording under 16 MiB.") }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let type = ext == "wav" ? "audio/wav" : ext == "mp3" ? "audio/mpeg" : "audio/mp4"
        return try await request("audio/transcribe", method: "POST", bytes: bytes, contentType: type, filename: filename)
    }
    func startCall(_ input: LiveCallInput) async throws -> LiveCallResult {
        try await request("booking/call", method: "POST", bytes: JSONEncoder().encode(input))
    }
    func callStatus(requestID: String) async throws -> LiveCallResult {
        guard AppSnapshot.safeFilename(requestID) else { throw RevaError.invalid("Invalid call identifier.") }
        return try await request("booking/call/" + requestID)
    }
}
