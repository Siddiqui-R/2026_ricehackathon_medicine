// Purpose: Send authenticated provider operations through the configured Reva server.
// Inputs: A validated server URL/token, domain values and optional audio bytes.
// Outputs: Decoded responses with the actual provider model, or user-readable transport errors.
// Side effects: URLSession requests and cancellable Gemini retry waits; callers decide whether to persist results.

// MARK: - Wire error handling
// Decode only the server error reason needed by the UI.
import Foundation

/// Shared wire boundary. Provider secrets and provider-specific SDKs stay on the Swift server.
// MARK: - Authenticated provider transport
// All paid operations go through Reva rather than exposing provider credentials on the phone.
private struct ProviderErrorBody: Decodable { var reason: String? }
enum ProviderFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return nil
    }
}
struct ProviderClient {
    let baseURL: URL
    let token: String
    var session: URLSession
    private let retrySleep: @Sendable (UInt64) async throws -> Void
    init(
        url: String, token: String, session: URLSession = .shared,
        retrySleep: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        }
    ) throws {
        guard let base = URL(string: url) else { throw RevaError.invalid("Enter a valid server URL.") }
        _ = try ServerClient(baseURL: base, token: token, session: session)
        self.baseURL = base
        self.token = token
        self.session = session
        self.retrySleep = retrySleep
    }
    // MARK: - Bounded HTTP request and decoding
    // Set a 110-second timeout, check HTTP status and reject unsupported JSON before returning values.
    private func request<T: Decodable>(
        _ path: String, method: String = "GET", bytes: Data? = nil,
        contentType: String = "application/json", filename: String? = nil, uploadID: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/" + path))
        request.httpMethod = method
        request.httpBody = bytes
        request.timeoutInterval = 110
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let uploadID { request.setValue(uploadID, forHTTPHeaderField: "X-Reva-Upload") }
        if let filename {
            request.setValue(ServerClient.attachmentMetadataName(filename), forHTTPHeaderField: "X-Filename")
        }
        let gemini = ["ai/summarize", "ai/prepare", "ai/profile"].contains(path)
        var fallbackOnly = false
        var nextDelay: UInt64? = 60_000_000_000
        while true {
            try Task.checkCancellation()
            request.setValue(fallbackOnly ? "true" : nil, forHTTPHeaderField: "X-Reva-Gemini-Fallback")
            let data: Data
            let rawResponse: URLResponse
            do { (data, rawResponse) = try await session.data(for: request) } catch {
                try Task.checkCancellation()
                guard gemini, Self.temporaryNetworkFailure(error) else { throw error }
                // A transport failure might hide the server's pair of attempts. Give the fallback its first
                // direct chance, then back off rather than repeatedly returning to the primary model.
                if fallbackOnly {
                    guard try await pauseForGemini(&nextDelay) else { throw error }
                }
                fallbackOnly = true
                continue
            }
            try Task.checkCancellation()
            guard let response = rawResponse as? HTTPURLResponse else {
                throw ProviderFailure.message("The provider server response was unreadable.")
            }
            guard (200..<300).contains(response.statusCode) else {
                let reason = (try? JSONDecoder().decode(ProviderErrorBody.self, from: data))?.reason
                let failure = ProviderFailure.message(
                    reason
                        ?? "The connected service returned HTTP \(response.statusCode). Your local source is unchanged."
                )
                guard gemini, [408, 429, 500, 502, 503, 504].contains(response.statusCode) else {
                    throw failure
                }
                let exhausted = response.value(forHTTPHeaderField: "X-Reva-Gemini-Fallback") == "true"
                if fallbackOnly || exhausted || response.statusCode == 429 {
                    let minimum = Self.retryAfterNanoseconds(
                        response.value(forHTTPHeaderField: "Retry-After"))
                    guard try await pauseForGemini(&nextDelay, minimum: minimum) else { throw failure }
                }
                fallbackOnly = true
                continue
            }
            do { return try JSONDecoder().decode(T.self, from: data) } catch {
                throw ProviderFailure.message(
                    "The connected service returned an unsupported response. Your original source is unchanged."
                )
            }
        }
    }

    // MARK: - Match browser fallback delays without keeping a server request open
    private func pauseForGemini(_ nextDelay: inout UInt64?, minimum: UInt64 = 0) async throws -> Bool {
        guard let delay = nextDelay else { return false }
        let (following, overflow) = delay.multipliedReportingOverflow(by: 2)
        nextDelay = overflow ? nil : following
        try Task.checkCancellation()
        try await retrySleep(max(delay, minimum))
        try Task.checkCancellation()
        return true
    }
    private static func temporaryNetworkFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            URLError.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .dnsLookupFailed, .notConnectedToInternet,
        ].contains(error.code)
    }
    private static func retryAfterNanoseconds(_ value: String?) -> UInt64 {
        guard let value else { return 0 }
        let seconds: TimeInterval
        if let numeric = TimeInterval(value) {
            seconds = numeric
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            seconds = formatter.date(from: value)?.timeIntervalSinceNow ?? 0
        }
        let nanoseconds = seconds * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds > 0, nanoseconds < Double(UInt64.max) else { return 0 }
        return UInt64(nanoseconds)
    }
    // MARK: - Configuration read
    // Use discovery to decide which feature controls can be offered.
    func status() async throws -> ProviderStatus { try await request("providers") }
    func medicalProfile(_ sources: [NativeProfileSource]) async throws -> NativeProfileResult {
        try NativeMedicalProfile.validateSources(sources)
        struct Input: Encodable { var records: [NativeProfileSource] }
        let result: NativeProfileResult = try await request(
            "ai/profile", method: "POST", bytes: JSONEncoder().encode(Input(records: sources)))
        try NativeMedicalProfile.validate(result, sources: sources)
        return result
    }
    // MARK: - Server request budgets
    // Match GeminiModels' UTF-8 limits before uploading; never truncate original evidence.
    private static func checkBudget(_ text: String, maximum: Int, field: String) throws {
        guard text.utf8.count <= maximum else {
            throw RevaError.invalid(
                "\(field) exceeds the connected AI limit of \(maximum) UTF-8 bytes. Use a smaller reviewed source or local preparation. The original is unchanged."
            )
        }
    }
    private static func checkSourceBudget(_ record: MedicalRecord) throws {
        try checkBudget(record.title, maximum: 240, field: "Source title")
        try checkBudget(record.text, maximum: 120_000, field: "Source text for \(record.title.prefix(80))")
    }
    // MARK: - Document summary request
    // Send the selected source unchanged, keeping unknown date provenance explicit.
    func summarize(_ record: MedicalRecord) async throws -> AISummary {
        try Self.checkSourceBudget(record)
        let sourceDate = record.providerDateContext
        try Self.checkBudget(sourceDate, maximum: 40, field: "Source date")
        struct Input: Encodable {
            let recordID: String
            let title: String
            let text: String
            let date: String
        }
        return try await request(
            "ai/summarize", method: "POST",
            bytes: JSONEncoder().encode(
                Input(recordID: record.id, title: record.title, text: record.text, date: sourceDate)))
    }
    // MARK: - Visit preparation request
    // Send explicit candidate records and visit context; profile health fields are not part of this contract.
    func prepare(_ visit: Visit, records: [MedicalRecord]) async throws -> AIPreparation {
        guard (1...100).contains(records.count), visit.questions.count <= 20 else {
            throw RevaError.invalid(
                "Connected preparation accepts 1–100 sources and at most 20 questions. Choose fewer sources/questions or use local preparation."
            )
        }
        try Self.checkBudget(visit.type, maximum: 80, field: "Visit type")
        try Self.checkBudget(visit.concern, maximum: 6000, field: "Visit concern")
        try Self.checkBudget(visit.goal, maximum: 6000, field: "Visit goal")
        for question in visit.questions {
            try Self.checkBudget(question, maximum: 1000, field: "Discussion question")
        }
        var total = 0
        for record in records {
            try Self.checkSourceBudget(record)
            try Self.checkBudget(record.providerDateContext, maximum: 40, field: "Source date")
            try Self.checkBudget(record.summary, maximum: 8000, field: "Source summary")
            total += record.text.utf8.count + record.summary.utf8.count
        }
        guard total <= 500_000 else {
            throw RevaError.invalid(
                "Connected preparation accepts at most 500000 UTF-8 bytes of source text and summaries. Choose fewer sources or use local preparation. Your originals are unchanged."
            )
        }
        struct VisitInput: Encodable {
            let id: String
            let type: String
            let concern: String
            let goal: String
            let questions: [String]
        }
        struct RecordInput: Encodable {
            let id: String
            let title: String
            let date: String
            let text: String
            let summary: String
            let version: Int
        }
        struct Input: Encodable {
            let visit: VisitInput
            let records: [RecordInput]
        }
        let input = Input(
            visit: .init(
                id: visit.id, type: visit.type, concern: visit.concern, goal: visit.goal,
                questions: visit.questions),
            records: records.map {
                .init(
                    id: $0.id, title: $0.title, date: $0.providerDateContext, text: $0.text,
                    summary: $0.summary,
                    version: $0.version)
            })
        return try await request("ai/prepare", method: "POST", bytes: JSONEncoder().encode(input))
    }
    // MARK: - Audio upload request
    // Require nonempty audio under 16 MiB and supply a sanitized filename header.
    func transcribe(bytes: Data, filename: String) async throws -> AudioTranscription {
        guard !bytes.isEmpty, bytes.count <= 16 * 1024 * 1024 else {
            throw RevaError.invalid("Choose a nonempty recording under 16 MiB.")
        }
        let type = ServerClient.audioContentType(filename: filename)
        let upload = try await HostedTransfers.stage(bytes, origin: baseURL, token: token, session: session)
        return try await request(
            "audio/transcribe", method: "POST", bytes: upload == nil ? bytes : nil, contentType: type,
            filename: filename, uploadID: upload)
    }
}
