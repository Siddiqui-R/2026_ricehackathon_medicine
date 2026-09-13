import Foundation
import XCTest

@testable import RevaCore

private final class NativeAuthStub: URLProtocol {
    static let lock = NSLock()
    static var handlers: [String: (URLRequest) throws -> (Int, Data)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.url!.host!]
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class NativeAuthTests: XCTestCase {
    private func withClient(
        _ handler: @escaping (URLRequest) throws -> (Int, Data), run: (NativeAuthClient) async throws -> Void
    ) async throws {
        let host = UUID().uuidString.lowercased() + ".example.test"
        NativeAuthStub.lock.withLock { NativeAuthStub.handlers[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeAuthStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            NativeAuthStub.lock.withLock { NativeAuthStub.handlers.removeValue(forKey: host) }
        }
        try await run(
            NativeAuthClient(
                origin: URL(string: "https://" + host)!, token: "synthetic-token", session: session))
    }
    private func body(_ request: URLRequest) throws -> [String: String] {
        if let data = request.httpBody { return try JSONDecoder().decode([String: String].self, from: data) }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode([String: String].self, from: bytes)
    }
    func testSignUpUsesRealPasswordPolicyAndServerContract() async throws {
        let expected = NativeAccountSession(
            token: "synthetic-session", expiresAt: "2099-01-01T00:00:00Z",
            user: .init(
                id: "judge", email: "judge@example.test", name: "Judge", createdAt: "2026-09-12T00:00:00Z"))
        try await withClient({ request in
            XCTAssertEqual(request.url?.path, "/v1/auth/signup")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                try self.body(request),
                ["name": "Judge", "email": "judge@example.test", "password": "Strong1!"])
            return (200, try JSONEncoder().encode(expected))
        }) { client in
            let result = try await client.authenticate(
                email: " Judge@example.test ", password: "Strong1!", name: " Judge ")
            XCTAssertEqual(result, expected)
            do {
                _ = try await client.authenticate(
                    email: "judge@example.test", password: "no-capital1!", name: "Judge")
                XCTFail("Weak password accepted")
            } catch { XCTAssertTrue(error is RevaError) }
        }
    }
    func testAccountActionsUseCorrectRoutesAndBearer() async throws {
        try await withClient({ request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
            switch request.url!.path {
            case "/v1/auth/password":
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(
                    try self.body(request), ["currentPassword": "Current1!", "newPassword": "Changed2!"])
            case "/v1/auth/account":
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(try self.body(request), ["password": "Current1!"])
            case "/v1/auth/logout", "/v1/auth/logout-all": XCTAssertEqual(request.httpMethod, "POST")
            default: XCTFail("Unexpected route")
            }
            return (204, Data())
        }) { client in
            try await client.changePassword(current: "Current1!", new: "Changed2!")
            try await client.deleteAccount(password: "Current1!")
            try await client.logout()
            try await client.logout(all: true)
        }
    }
    func testRejectedSessionsDoNotOpenAWorkspace() async throws {
        try await withClient({ _ in (401, Data(#"{"reason":"Invalid email or password"}"#.utf8)) }) {
            client in
            do {
                _ = try await client.authenticate(email: "judge@example.test", password: "Existing password")
                XCTFail("Rejected login accepted")
            } catch let failure as NativeAuthFailure { XCTAssertEqual(failure.status, 401) }
        }
        let expired = NativeAccountSession(
            token: "synthetic", expiresAt: "2000-01-01T00:00:00Z",
            user: .init(
                id: "judge", email: "judge@example.test", name: "Judge", createdAt: "2000-01-01T00:00:00Z"))
        XCTAssertThrowsError(try expired.validate())
    }
}
