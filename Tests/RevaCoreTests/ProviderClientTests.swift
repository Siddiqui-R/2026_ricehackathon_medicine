// Purpose: Verify provider-client wire contracts and failure handling without invoking external services.
// Inputs: Synthetic documents, visits, audio bytes, reviewed call requests, and stubbed responses.
// Outputs: XCTest assertions for exact request fields, decoded results, safe errors, and request counts.
// Side effects: Installs token-scoped URLProtocol handlers and ephemeral sessions, then releases them; no provider is contacted.

import Foundation
import XCTest

@testable import RevaCore

// MARK: - Intercepted provider responses and request routing

private struct ProviderStubResponse {
    var status = 200
    var body: Data
    init(status: Int = 200, json: String) {
        self.status = status
        self.body = Data(json.utf8)
    }
}

/// Intercepts every request, including unexpected ones; these tests never contact a provider.
private final class ProviderStubProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> ProviderStubResponse
    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]

    static func install(token: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers["Bearer " + token] = handler
    }
    static func remove(token: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: "Bearer " + token)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.value(forHTTPHeaderField: "Authorization") ?? ""]
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.userAuthenticationRequired) }
            let result = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: result.status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

// MARK: - Session lifetime and request counting

private final class ProviderTestTransport {
    let client: ProviderClient
    private let token: String
    private let session: URLSession

    init(
        token: String = "synthetic-provider-" + UUID().uuidString,
        handler: @escaping ProviderStubProtocol.Handler
    ) throws {
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderStubProtocol.self]
        session = URLSession(configuration: configuration)
        ProviderStubProtocol.install(token: token, handler: handler)
        do {
            client = try ProviderClient(
                url: "https://reva.example.test/gateway/", token: token, session: session)
        } catch {
            session.invalidateAndCancel()
            ProviderStubProtocol.remove(token: token)
            throw error
        }
    }
    deinit {
        session.invalidateAndCancel()
        ProviderStubProtocol.remove(token: token)
    }
}

private final class ProviderRequestCount {
    private let lock = NSLock()
    private var count = 0
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class ProviderClientTests: XCTestCase {
    // MARK: - Synthetic domain inputs and assertion helpers

    private let transcriptJSON =
        #"{"text":"SYNTHETIC conversation only.","segments":[{"id":"segment-a","start":0,"end":0.625,"speaker":"Speaker","text":"SYNTHETIC opening."},{"id":"segment-b","start":5.25,"end":9.875,"speaker":"Speaker","text":"Fictional follow-up."}],"model":"synthetic-transcription-model"}"#

    private func record() -> MedicalRecord {
        MedicalRecord(
            id: "synthetic-record-a", title: "SYNTHETIC café note", kind: "Notes",
            provider: "Fictional source", date: "2026-09-07",
            text: "SYNTHETIC — not a real medical record.\r\nValue 0.25 mg; no change documented.\n"
                + String(repeating: "Exact later source line: café / µg / 10:30.\n", count: 50),
            summary: "Synthetic local excerpt.", sourceFilename: "synthetic-note.txt",
            notes: "Independent notes must not enter this wire DTO.", isDemo: true, version: 7)
    }
    private func visit() -> Visit {
        Visit(
            id: "synthetic-visit-a", title: "SYNTHETIC preparation", type: "Primary care",
            provider: "Fictional clinician", clinic: "Fictional clinic", date: "2026-09-15T09:30:00-05:00",
            concern: "Synthetic concern, exactly as entered.", goal: "Review the documented history.",
            questions: ["Keep my edited question?", "Preserve café and 0.25 exactly?"],
            notes: "Private-to-this-fixture notes excluded from the preparation DTO.")
    }
    private func callInput() -> LiveCallInput {
        LiveCallInput(
            requestID: "synthetic-request-42", clinic: "Fictional clinic", phone: "+12025550123",
            reason: "SYNTHETIC scheduling demonstration", earliest: "2026-09-15T09:00:00-05:00",
            latest: "2026-09-18T16:30:00-05:00", timeZone: "America/Chicago",
            preferences: "Fictional office; weekday afternoon preferred.",
            patientName: "Jordan Avery (Synthetic)", consent: true)
    }
    private func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: body(request)) as? [String: Any])
    }
    private func expectFailure<T>(
        _ operation: () async throws -> T,
        file: StaticString = #filePath, line: UInt = #line,
        inspect: (Error) -> Void
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected the synthetic provider operation to fail.", file: file, line: line)
        } catch { inspect(error) }
    }
    private func assertProviderMessage(
        _ error: Error, equals expected: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case ProviderFailure.message(let message) = error else {
            return XCTFail("Expected ProviderFailure, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(message, expected, file: file, line: line)
        XCTAssertEqual(error.localizedDescription, expected, file: file, line: line)
    }

    // MARK: - Capability discovery and document AI contracts

    func testStatusUsesBearerAndPrefixedGETAndDecodesIndependentCapabilities() async throws {
        let token = "synthetic-provider-" + UUID().uuidString
        let calls = ProviderRequestCount()
        let transport = try ProviderTestTransport(token: token) { request in
            calls.increment()
            XCTAssertEqual(request.url?.path, "/gateway/v1/providers")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
            XCTAssertTrue(try self.body(request).isEmpty)
            return ProviderStubResponse(
                json:
                    #"{"gemini":{"configured":true,"model":"synthetic-summary-model"},"transcription":{"configured":false,"model":"synthetic-speech-model"},"booking":{"configured":true,"model":"synthetic-agent"},"liveCallsEnabled":false}"#
            )
        }
        let result = try await transport.client.status()
        XCTAssertEqual(result.gemini, ProviderCapability(configured: true, model: "synthetic-summary-model"))
        XCTAssertEqual(
            result.transcription, ProviderCapability(configured: false, model: "synthetic-speech-model"))
        XCTAssertEqual(result.booking, ProviderCapability(configured: true, model: "synthetic-agent"))
        XCTAssertFalse(result.liveCallsEnabled)
        XCTAssertEqual(calls.value, 1)
    }

    func testSummarySendsExactFullSourceTextAndOnlyContractFields() async throws {
        let source = record()
        let unchanged = source
        let transport = try ProviderTestTransport { request in
            XCTAssertEqual(request.url?.path, "/gateway/v1/ai/summarize")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let input = try self.json(request)
            XCTAssertEqual(Set(input.keys), Set(["recordID", "title", "text"]))
            XCTAssertEqual(input["recordID"] as? String, "synthetic-record-a")
            XCTAssertEqual(input["title"] as? String, "SYNTHETIC café note")
            XCTAssertEqual(input["text"] as? String, source.text)
            return ProviderStubResponse(
                json:
                    #"{"summary":"Synthetic returned summary; no change documented.","model":"synthetic-summary-model"}"#
            )
        }
        let result = try await transport.client.summarize(source)
        XCTAssertEqual(result.summary, "Synthetic returned summary; no change documented.")
        XCTAssertEqual(result.model, "synthetic-summary-model")
        XCTAssertEqual(source, unchanged)
    }

    func testPreparationMapsEditedQuestionsCandidatesFullTextAndVersions() async throws {
        let appointment = visit()
        let first = record()
        var second = first
        second.id = "synthetic-record-b"
        second.title = "SYNTHETIC second record"
        second.date = "2026-08-03"
        second.text = "Second synthetic full source.\nExact ending."
        second.summary = "Second local excerpt."
        second.version = 2
        let candidates = [first, second]
        let transport = try ProviderTestTransport { request in
            XCTAssertEqual(request.url?.path, "/gateway/v1/ai/prepare")
            XCTAssertEqual(request.httpMethod, "POST")
            let input = try self.json(request)
            XCTAssertEqual(Set(input.keys), Set(["visit", "records"]))
            let sentVisit = try XCTUnwrap(input["visit"] as? [String: Any])
            XCTAssertEqual(Set(sentVisit.keys), Set(["id", "type", "concern", "goal", "questions"]))
            XCTAssertEqual(sentVisit["id"] as? String, appointment.id)
            XCTAssertEqual(sentVisit["type"] as? String, appointment.type)
            XCTAssertEqual(sentVisit["concern"] as? String, appointment.concern)
            XCTAssertEqual(sentVisit["goal"] as? String, appointment.goal)
            XCTAssertEqual(sentVisit["questions"] as? [String], appointment.questions)
            let sentRecords = try XCTUnwrap(input["records"] as? [[String: Any]])
            XCTAssertEqual(sentRecords.count, candidates.count)
            for (sent, expected) in zip(sentRecords, candidates) {
                XCTAssertEqual(Set(sent.keys), Set(["id", "title", "date", "text", "summary", "version"]))
                XCTAssertEqual(sent["id"] as? String, expected.id)
                XCTAssertEqual(sent["title"] as? String, expected.title)
                XCTAssertEqual(sent["date"] as? String, expected.date)
                XCTAssertEqual(sent["text"] as? String, expected.text)
                XCTAssertEqual(sent["summary"] as? String, expected.summary)
                XCTAssertEqual(sent["version"] as? Int, expected.version)
            }
            return ProviderStubResponse(
                json:
                    #"{"overview":"Synthetic overview.","questions":["Synthetic returned question?"],"selectedRecordIDs":["synthetic-record-b"],"model":"synthetic-preparation-model"}"#
            )
        }
        let result = try await transport.client.prepare(appointment, records: candidates)
        XCTAssertEqual(result.selectedRecordIDs, ["synthetic-record-b"])
        XCTAssertEqual(result.questions, ["Synthetic returned question?"])
        XCTAssertEqual(result.overview, "Synthetic overview.")
        XCTAssertEqual(result.model, "synthetic-preparation-model")
        XCTAssertEqual(
            appointment.questions, ["Keep my edited question?", "Preserve café and 0.25 exactly?"])
    }

    // MARK: - Audio transfer and relative transcript times

    func testAudioPreservesRawBytesMIMEFilenameAndRelativeTimesAndRejectsSizeErrors() async throws {
        let bytes = Data([0, 255, 128, 13, 10, 32, 0, 254])
        let formats = [
            ("Fictional café.M4A", "audio/mp4", "Fictional caf_.M4A"),
            ("synthetic.wav", "audio/wav", "synthetic.wav"),
            ("synthetic.mp3", "audio/mpeg", "synthetic.mp3"),
        ]
        for (filename, type, metadata) in formats {
            let transport = try ProviderTestTransport { request in
                XCTAssertEqual(request.url?.path, "/gateway/v1/audio/transcribe")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), type)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Filename"), metadata)
                XCTAssertEqual(try self.body(request), bytes)
                return ProviderStubResponse(json: self.transcriptJSON)
            }
            let result = try await transport.client.transcribe(bytes: bytes, filename: filename)
            XCTAssertEqual(result.text, "SYNTHETIC conversation only.")
            XCTAssertEqual(result.model, "synthetic-transcription-model")
            XCTAssertEqual(
                result.segments,
                [
                    TranscriptSegment(
                        id: "segment-a", speaker: "Speaker", start: 0, end: 0.625, text: "SYNTHETIC opening."),
                    TranscriptSegment(
                        id: "segment-b", speaker: "Speaker", start: 5.25, end: 9.875,
                        text: "Fictional follow-up."),
                ])
        }
        let calls = ProviderRequestCount()
        let transport = try ProviderTestTransport { request in
            calls.increment()
            XCTAssertEqual(try self.body(request).count, 16 * 1024 * 1024)
            return ProviderStubResponse(json: self.transcriptJSON)
        }
        _ = try await transport.client.transcribe(
            bytes: Data(repeating: 0x53, count: 16 * 1024 * 1024), filename: "synthetic-limit.m4a")
        for invalid in [Data(), Data(repeating: 0x53, count: 16 * 1024 * 1024 + 1)] {
            await expectFailure({
                try await transport.client.transcribe(bytes: invalid, filename: "synthetic-invalid.m4a")
            }) { error in
                XCTAssertTrue(error is RevaError)
            }
        }
        XCTAssertEqual(calls.value, 1, "Rejected input must not reach transport.")
    }

    // MARK: - Reviewed call requests and status lookup

    func testCallStartPreservesReviewedFieldsConsentAndStableRequestIdentity() async throws {
        let reviewed = callInput()
        let calls = ProviderRequestCount()
        let transport = try ProviderTestTransport { request in
            calls.increment()
            XCTAssertEqual(request.url?.path, "/gateway/v1/booking/call")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let input = try self.json(request)
            XCTAssertEqual(
                Set(input.keys),
                Set([
                    "requestID", "clinic", "phone", "reason", "earliest", "latest", "timeZone", "preferences",
                    "patientName", "consent",
                ]))
            XCTAssertEqual(input["requestID"] as? String, "synthetic-request-42")
            XCTAssertEqual(input["clinic"] as? String, reviewed.clinic)
            XCTAssertEqual(input["phone"] as? String, "+12025550123")
            XCTAssertEqual(input["reason"] as? String, reviewed.reason)
            XCTAssertEqual(input["earliest"] as? String, reviewed.earliest)
            XCTAssertEqual(input["latest"] as? String, reviewed.latest)
            XCTAssertEqual(input["timeZone"] as? String, "America/Chicago")
            XCTAssertEqual(input["preferences"] as? String, reviewed.preferences)
            XCTAssertEqual(input["patientName"] as? String, "Jordan Avery (Synthetic)")
            let consent = try XCTUnwrap(input["consent"] as? Bool)
            if !consent {
                return ProviderStubResponse(status: 400, json: #"{"reason":"Explicit consent is required."}"#)
            }
            return ProviderStubResponse(
                json:
                    #"{"conversationID":"synthetic-conversation-42","status":"initiated","provider":"synthetic-call-provider"}"#
            )
        }
        // Two explicit attempts keep the identity; server receipts, not this stub, enforce replay safety.
        for _ in 0..<2 {
            let result = try await transport.client.startCall(reviewed)
            XCTAssertEqual(result.conversationID, "synthetic-conversation-42")
            XCTAssertEqual(result.status, "initiated")
            XCTAssertEqual(result.provider, "synthetic-call-provider")
            XCTAssertNil(result.transcript)
        }
        var notConsented = reviewed
        notConsented.consent = false
        await expectFailure({ try await transport.client.startCall(notConsented) }) { error in
            self.assertProviderMessage(error, equals: "Explicit consent is required.")
        }
        XCTAssertEqual(calls.value, 3, "The client must not retry or silently grant consent.")
    }

    func testCallStatusUsesRequestIDRouteAndRejectsUnsafePaths() async throws {
        let token = "synthetic-provider-" + UUID().uuidString
        let calls = ProviderRequestCount()
        let transport = try ProviderTestTransport(token: token) { request in
            calls.increment()
            XCTAssertEqual(request.url?.path, "/gateway/v1/booking/call/synthetic-request-42")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
            XCTAssertTrue(try self.body(request).isEmpty)
            return ProviderStubResponse(
                json:
                    #"{"conversationID":"synthetic-conversation-42","status":"done","provider":"synthetic-call-provider","transcript":"SYNTHETIC call ended; no appointment confirmed."}"#
            )
        }
        let result = try await transport.client.callStatus(requestID: "synthetic-request-42")
        XCTAssertEqual(result.conversationID, "synthetic-conversation-42")
        XCTAssertEqual(result.status, "done")
        XCTAssertEqual(result.provider, "synthetic-call-provider")
        XCTAssertEqual(result.transcript, "SYNTHETIC call ended; no appointment confirmed.")
        for id in ["", ".", "..", "../another-owner", "folder/id", "folder\\id", "nul\0id"] {
            await expectFailure({ try await transport.client.callStatus(requestID: id) }) { error in
                XCTAssertTrue(error is RevaError)
            }
        }
        XCTAssertEqual(calls.value, 1)
    }

    // MARK: - Safe failures and malformed provider results

    func testServiceAndAuthFailuresSurfaceSafeMessagesWithoutBodyLeakOrRetry() async throws {
        let source = record()
        let cases = [
            (
                503, #"{"reason":"Document summarization is not configured."}"#,
                "Document summarization is not configured."
            ),
            (
                401, "<html>SYNTHETIC-UPSTREAM-BODY-MUST-NOT-LEAK</html>",
                "The connected service returned HTTP 401. Your local source is unchanged."
            ),
        ]
        for (status, payload, expected) in cases {
            let token = "synthetic-provider-" + UUID().uuidString
            let calls = ProviderRequestCount()
            let transport = try ProviderTestTransport(token: token) { _ in
                calls.increment()
                return ProviderStubResponse(status: status, json: payload)
            }
            await expectFailure({ try await transport.client.summarize(source) }) { error in
                self.assertProviderMessage(error, equals: expected)
                XCTAssertFalse(error.localizedDescription.contains("SYNTHETIC-UPSTREAM-BODY-MUST-NOT-LEAK"))
                XCTAssertFalse(error.localizedDescription.contains(token))
            }
            XCTAssertEqual(calls.value, 1)
            XCTAssertEqual(source.text, self.record().text)
        }
    }

    func testMalformedSuccessfulResponsesFailInsteadOfCreatingUsableProviderResults() async throws {
        let cases = [
            ("summary", "not JSON"),
            ("summary", #"{"summary":"SYNTHETIC missing model"}"#),
            (
                "status",
                #"{"gemini":{"configured":"yes","model":"synthetic"},"transcription":{"configured":false,"model":"synthetic"},"booking":{"configured":false,"model":"synthetic"},"liveCallsEnabled":false}"#
            ),
            (
                "prepare",
                #"{"overview":"SYNTHETIC","questions":[],"selectedRecordIDs":"synthetic-record-a","model":"synthetic"}"#
            ),
            (
                "audio",
                #"{"text":"SYNTHETIC","segments":[{"id":"segment-a","start":"tomorrow","end":1,"speaker":"Speaker","text":"SYNTHETIC"}],"model":"synthetic"}"#
            ),
            ("call", #"{"status":"done","provider":"synthetic"}"#),
        ]
        for (kind, payload) in cases {
            let calls = ProviderRequestCount()
            let transport = try ProviderTestTransport { _ in
                calls.increment()
                return ProviderStubResponse(json: payload)
            }
            await expectFailure({
                switch kind {
                case "summary": _ = try await transport.client.summarize(self.record())
                case "status": _ = try await transport.client.status()
                case "prepare": _ = try await transport.client.prepare(self.visit(), records: [self.record()])
                case "audio":
                    _ = try await transport.client.transcribe(bytes: Data([0x53]), filename: "synthetic.m4a")
                default: _ = try await transport.client.startCall(self.callInput())
                }
            }) { error in
                self.assertProviderMessage(
                    error,
                    equals:
                        "The connected service returned an unsupported response. Your original source is unchanged."
                )
            }
            XCTAssertEqual(calls.value, 1)
        }
    }
}
