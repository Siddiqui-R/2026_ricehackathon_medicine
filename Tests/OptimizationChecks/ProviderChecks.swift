// Purpose: Exercise the real ProviderClient's request-budget checks with intercepted HTTP.
// Inputs: Synthetic records, visits, and an ephemeral URLSession.
// Outputs: Boundary assertions and upload counts.
// Side effects: No network; URLProtocol responds locally. Endpoint validation is not tested here.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Unrelated server endpoint utilities
// Avoid requiring CryptoKit just for the server client's filename hash, which this suite never uses.
struct ServerClient {
    init(baseURL: URL, token: String, session: URLSession) throws {}
    static func attachmentMetadataName(_ value: String) -> String { value }
    // The harness compiles audioContentType verbatim from production in a separate extension.
}

// MARK: - Intercept every request; never forward to the network
final class LocalProtocol: URLProtocol {
    static let lock = NSLock()
    static var uploads = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.uploads += 1
        Self.lock.unlock()
        let body =
            request.url!.path.hasSuffix("summarize")
            ? #"{"summary":"Synthetic","model":"test"}"#
            : #"{"overview":"Synthetic","questions":[],"selectedRecordIDs":[],"model":"test"}"#
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return uploads
    }
}

// MARK: - Budget boundaries and zero-network rejection
@main struct ProviderChecks {
    static func rejected(_ operation: () async throws -> Void) async {
        let before = LocalProtocol.count()
        do {
            try await operation()
            assertionFailure("R9: oversized request was accepted")
        } catch {
            assert(LocalProtocol.count() == before, "R9: rejected input was uploaded")
        }
    }
    static func main() async throws {
        let fixture = try JSONDecoder().decode(
            AppSnapshot.self,
            from: Data(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = try ProviderClient(
            url: "https://synthetic.invalid", token: "synthetic", session: session)
        var record = fixture.records[0]
        record.text = String(repeating: "a", count: 120_000)
        _ = try await client.summarize(record)
        record.text += "a"
        let tooLong = record
        await rejected { _ = try await client.summarize(tooLong) }
        record.text = String(repeating: "é", count: 60_000)
        _ = try await client.summarize(record)
        record.text += "a"
        let multibyte = record
        await rejected { _ = try await client.summarize(multibyte) }
        record.text = "Synthetic"
        record.summary = ""
        var records = (0..<100).map { i -> MedicalRecord in
            var copy = record
            copy.id = "synthetic-\(i)"
            return copy
        }
        let visit = fixture.visits[0]
        _ = try await client.prepare(visit, records: records)
        var extra = record
        extra.id = "extra"
        let tooMany = records + [extra]
        await rejected { _ = try await client.prepare(visit, records: tooMany) }
        records = Array(records.prefix(5))
        for i in records.indices { records[i].text = String(repeating: "a", count: 100_000) }
        _ = try await client.prepare(visit, records: records)
        records[0].summary = "a"
        let overTotal = records
        await rejected { _ = try await client.prepare(visit, records: overTotal) }
        assert(fixture.records[0].text != tooLong.text, "Original fixture must remain unchanged")
        print(
            "PASS R9: source bytes, multibyte input, candidate count, total bytes; rejected input never uploaded"
        )
    }
}
