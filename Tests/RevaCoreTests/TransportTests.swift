import Foundation
import XCTest
@testable import RevaCore

private struct SyntheticResponse {
    var status: Int? = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var body: Data = Data()
}

/// Every synthetic request is intercepted; no test can contact a server.
private final class SyntheticURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> SyntheticResponse
    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]

    static func install(token: String, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers["Bearer " + token] = handler
    }
    static func remove(token: String) {
        lock.lock(); defer { lock.unlock() }
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
            let response: URLResponse
            if let status = result.status {
                response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: result.headers)!
            } else {
                response = URLResponse(url: request.url!, mimeType: "application/json", expectedContentLength: result.body.count, textEncodingName: "utf-8")
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class SyntheticTransport {
    let client: ServerClient
    private let session: URLSession
    private let token: String
    init(base: String = "https://reva.example.test/", handler: @escaping SyntheticURLProtocol.Handler) throws {
        token = "synthetic-test-" + UUID().uuidString
        SyntheticURLProtocol.install(token: token, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = try ServerClient(baseURL: URL(string: base)!, token: token, session: session)
    }
    deinit {
        session.invalidateAndCancel()
        SyntheticURLProtocol.remove(token: token)
    }
}

private final class SyntheticRequestCount {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

final class TransportTests: XCTestCase {
    private func fixture() throws -> AppSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("demo/seed.json")))
    }

    private func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
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

    private func expectFailure<T>(_ operation: () async throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  inspect: (Error) -> Void) async {
        do {
            _ = try await operation()
            XCTFail("Expected the transport operation to fail.", file: file, line: line)
        } catch { inspect(error) }
    }

    func testSnapshotPushPullRoundtripUsesContractHeadersAndJSONEnvelope() async throws {
        var snapshot = try fixture()
        snapshot.records[0].notes = "Synthetic edited note with Unicode: café."
        snapshot.visits[0].questions.append("Synthetic additional question?")
        let original = snapshot
        let calls = SyntheticRequestCount()
        let transport = try SyntheticTransport(base: "https://reva.example.test/proxy/") { request in
            calls.increment()
            XCTAssertEqual(request.url?.path, "/proxy/v1/state")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer synthetic-test-") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            if request.httpMethod == "PUT" {
                let bytes = try self.body(request)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                XCTAssertEqual(Set(json.keys), Set(["baseRevision", "snapshot"]))
                XCTAssertEqual(json["baseRevision"] as? Int, 7)
                let pushedBytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(json["snapshot"]))
                let pushed = try JSONDecoder().decode(AppSnapshot.self, from: pushedBytes)
                XCTAssertEqual(pushed, original)
                return SyntheticResponse(body: Data("{\"revision\":8}".utf8))
            }
            XCTAssertEqual(request.httpMethod, "GET")
            return SyntheticResponse(body: try JSONEncoder().encode(ServerState(revision: 8, snapshot: original)))
        }
        let revision = try await transport.client.push(snapshot, revision: 7)
        XCTAssertEqual(revision, 8)
        let pulled = try await transport.client.pull()
        XCTAssertEqual(pulled.revision, 8)
        XCTAssertEqual(pulled.snapshot, original)
        XCTAssertEqual(snapshot, original)
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(pulled.snapshot.records.first { $0.id == "demo-record-tibia-procedure" }?.pageTexts?.count, 2)
    }

    func testMissingStatePreservesTombstoneRevisionAndDefaultsToZero() async throws {
        for header in ["14", "0", nil] as [String?] {
            let transport = try SyntheticTransport { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/state")
                return SyntheticResponse(status: 404, headers: header.map { ["X-State-Revision": $0] } ?? [:])
            }
            await expectFailure({ try await transport.client.pull() }) { error in
                guard case ServerFailure.empty(let revision) = error else { return XCTFail("Expected empty state, got \(error)") }
                XCTAssertEqual(revision, header.flatMap(Int.init) ?? 0)
            }
        }
    }

    func testConflictDoesNotRetryOrModifySnapshot() async throws {
        let snapshot = try fixture()
        let original = snapshot
        let calls = SyntheticRequestCount()
        let transport = try SyntheticTransport { request in
            calls.increment()
            XCTAssertEqual(request.httpMethod, "PUT")
            return SyntheticResponse(status: 409, headers: ["X-State-Revision": "11"], body: Data("{\"error\":true}".utf8))
        }
        await expectFailure({ try await transport.client.push(snapshot, revision: 9) }) { error in
            guard case ServerFailure.conflict = error else { return XCTFail("Expected conflict, got \(error)") }
        }
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(snapshot, original)
    }

    func testRejectedHTTPStatusesNeverDecodeAsSuccess() async throws {
        for status in [301, 401, 413, 500] {
            let transport = try SyntheticTransport { _ in
                SyntheticResponse(status: status, body: Data("{\"revision\":99}".utf8))
            }
            await expectFailure({ try await transport.client.push(self.fixture(), revision: 0) }) { error in
                guard case ServerFailure.response(let actual) = error else { return XCTFail("Expected HTTP \(status), got \(error)") }
                XCTAssertEqual(actual, status)
            }
        }
    }

    func testInvalidSuccessfulStateCannotEnterLocalRepository() async throws {
        var invalid = try fixture()
        invalid.records.append(invalid.records[0])
        let payloads = [Data("not-json".utf8), try JSONEncoder().encode(ServerState(revision: 1, snapshot: invalid))]
        for payload in payloads {
            let transport = try SyntheticTransport { _ in SyntheticResponse(body: payload) }
            await expectFailure({ try await transport.client.pull() }) { error in
                XCTAssertTrue(error is DecodingError || error is RevaError)
            }
        }
    }

    func testNonHTTPResponseAndConnectionFailureRemainErrors() async throws {
        let nonHTTP = try SyntheticTransport { _ in SyntheticResponse(status: nil, body: Data("{}".utf8)) }
        await expectFailure({ try await nonHTTP.client.pull() }) { error in XCTAssertTrue(error is RevaError) }
        let disconnected = try SyntheticTransport { _ in throw URLError(.notConnectedToInternet) }
        await expectFailure({ try await disconnected.client.pull() }) { error in
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testAttachmentUploadDownloadAndDeletionPreserveExactBinaryBytes() async throws {
        let filename = "Synthetic source (1).pdf"
        let id = ServerClient.attachmentID(for: filename)
        let bytes = Data([0, 255, 128, 10, 13, 37, 80, 68, 70, 0, 254])
        let calls = SyntheticRequestCount()
        let transport = try SyntheticTransport { request in
            calls.increment()
            XCTAssertEqual(request.url?.path, "/v1/attachments/" + id)
            switch request.httpMethod {
            case "PUT":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/pdf")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Filename"), filename)
                XCTAssertEqual(try self.body(request), bytes)
                return SyntheticResponse(status: 204)
            case "GET":
                return SyntheticResponse(headers: ["Content-Type": "application/pdf", "X-Filename": filename], body: bytes)
            case "DELETE": return SyntheticResponse(status: 204)
            default: throw URLError(.badURL)
            }
        }
        try await transport.client.uploadAttachment(id: id, filename: filename, data: bytes, type: "application/pdf")
        let downloaded = try await transport.client.attachment(id: id)
        XCTAssertEqual(downloaded, bytes)
        try await transport.client.deleteAttachment(id: id)
        XCTAssertEqual(calls.value, 3)
    }

    func testAttachment404IsNotAnEmptyStateRevision() async throws {
        let transport = try SyntheticTransport { _ in SyntheticResponse(status: 404, headers: ["X-State-Revision": "27"]) }
        await expectFailure({ try await transport.client.attachment(id: "missing-synthetic-source") }) { error in
            guard case ServerFailure.response(let code) = error else { return XCTFail("Attachment 404 was misclassified: \(error)") }
            XCTAssertEqual(code, 404)
        }
    }

    func testDeletionPreservesMonotonicStateRevisionResponse() async throws {
        let transport = try SyntheticTransport { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/state")
            return SyntheticResponse(body: Data("{\"revision\":18}".utf8))
        }
        let revision = try await transport.client.deleteState()
        XCTAssertEqual(revision, 18)
    }

    func testHealthDisplaysStorageReportedByTheServer() async throws {
        let transport = try SyntheticTransport { request in
            XCTAssertEqual(request.url?.path, "/health")
            XCTAssertEqual(request.httpMethod, "GET")
            return SyntheticResponse(body: Data("{\"status\":\"ok\",\"storage\":\"local\",\"isDemo\":true}".utf8))
        }
        let health = try await transport.client.health()
        XCTAssertEqual(health, "Connected · local")
    }

    func testServerURLValidationRequiresHTTPSOrExplicitLoopback() throws {
        for address in ["https://reva.example.test", "https://reva.example.test:8443/api", "http://localhost:8080", "http://127.0.0.1:8080", "http://[::1]:8080"] {
            XCTAssertNoThrow(try ServerClient(baseURL: XCTUnwrap(URL(string: address)), token: "synthetic-token"), address)
        }
        for address in ["http://reva.example.test", "http://192.168.1.8:8080", "http://localhost.example.test", "https://name:secret@reva.example.test", "https://reva.example.test?token=secret", "https://reva.example.test#fragment", "file:///private/tmp/state.json", "ftp://reva.example.test"] {
            XCTAssertThrowsError(try ServerClient(baseURL: XCTUnwrap(URL(string: address)), token: "synthetic-token"), address)
        }
        XCTAssertThrowsError(try ServerClient(baseURL: XCTUnwrap(URL(string: "https://reva.example.test")), token: ""))
    }

    func testAttachmentIDHashesExactUTF8AndMetadataFitsBackendContract() throws {
        // Fixed vectors independently produced with Python hashlib, not the helper under test.
        XCTAssertEqual(ServerClient.attachmentID(for: "source.pdf"), "81d00dfc1279b8915e097d2678ba54b02235615be20d614b47920b898483795e")
        XCTAssertEqual(ServerClient.attachmentID(for: "résumé scan.png"), "af7fe415351068984a4a2ead28079d5f80b82b8e8ee02fad18e5270102e648e0")
        XCTAssertEqual(ServerClient.attachmentID(for: "re\u{301}sume\u{301} scan.png"), "a411da095136ec27563c1e0db213a6a3f78a9e3ebe54c2071084c7fb0b085155")
        let unusualNames = ["../secret.pdf", "résumé scan.png", ".hidden", "\r\nX-Header: injected", "  ", String(repeating: "long", count: 100) + ".pdf"]
        for filename in unusualNames {
            let id = ServerClient.attachmentID(for: filename)
            XCTAssertEqual(id.count, 64)
            XCTAssertNotNil(id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression))
            XCTAssertEqual(id, ServerClient.attachmentID(for: filename))
            let metadata = ServerClient.attachmentMetadataName(filename)
            XCTAssertNotNil(metadata.range(of: "^[A-Za-z0-9 ()_-][A-Za-z0-9 .()_-]{0,179}$", options: .regularExpression), metadata)
            XCTAssertEqual(metadata, metadata.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertLessThanOrEqual(metadata.utf8.count, 180)
        }
    }

    func testUnsafeAttachmentPathsAreRejectedBeforeTransport() async throws {
        let calls = SyntheticRequestCount()
        let transport = try SyntheticTransport { _ in calls.increment(); return SyntheticResponse(status: 204) }
        for id in ["../escape", "folder/source", "folder\\source", "", ".", ".."] {
            await expectFailure({ try await transport.client.attachment(id: id) }) { error in XCTAssertTrue(error is RevaError) }
            await expectFailure({ try await transport.client.deleteAttachment(id: id) }) { error in XCTAssertTrue(error is RevaError) }
        }
        await expectFailure({ try await transport.client.uploadAttachment(id: "synthetic-id", filename: "../escape.pdf", data: Data([1]), type: "application/pdf") }) { error in
            XCTAssertTrue(error is RevaError)
        }
        XCTAssertEqual(calls.value, 0)
    }
}
