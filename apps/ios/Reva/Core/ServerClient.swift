// Purpose: Transfer owner-scoped snapshots and attachments over the Reva HTTP contract.
// Inputs: A server URL/token, snapshot revision and optional attachment data.
// Outputs: Validated snapshots, revisions, bytes or explicit transport/conflict errors.
// Side effects: HTTP requests; no automatic conflict resolution or local persistence.

import CryptoKit
import Foundation

// MARK: - Snapshot and health wire values
// Keep revision-bearing snapshots distinct from health/readiness information.
struct ServerState: Codable {
    var revision: Int
    var snapshot: AppSnapshot
}
struct ServerHealth: Decodable {
    var status: String
    var storage: String?
    var mode: String?
}
// MARK: - Transport outcome mapping
// Surface conflicts, empty state and server failures so the user controls resolution.
enum ServerFailure: LocalizedError {
    case response(Int)
    case conflict
    case empty(Int)
    var errorDescription: String? {
        switch self {
        case .conflict:
            return
                "The server has a newer revision. Pull it before pushing again. Your local data has not changed."
        case .empty: return "This server identity has no saved state. You can push the local demo."
        case .response(let code): return "The server returned HTTP \(code). Your local data is unchanged."
        }
    }
}
// MARK: - Snapshot transport
// This client exchanges bytes and revisions; AppStore owns local publication.
struct ServerClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared
    // MARK: - Attachment identity and metadata
    // Derive stable safe IDs and portable upload names without changing original bytes.
    static func attachmentID(for filename: String) -> String {
        SHA256.hash(data: Data(filename.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func attachmentMetadataName(_ filename: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-()")
        let safe = String(
            filename.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }.prefix(170)
        ).trimmingCharacters(in: .whitespaces)
        return safe.isEmpty || safe.hasPrefix(".") ? "document" : safe
    }
    static func uploadContentType(_ type: String?) -> String {
        let type = type?.lowercased() ?? "application/octet-stream"
        let accepted = [
            "application/pdf", "text/plain", "image/png", "image/jpeg", "image/heic", "image/heif",
            "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/mpeg", "audio/wav", "audio/x-wav",
            "application/octet-stream",
        ]
        return accepted.contains(type) ? type : "application/octet-stream"
    }
    // MARK: - Endpoint validation
    // Allow HTTPS or explicit loopback HTTP and reject missing credentials before network use.
    init(baseURL: URL, token: String, session: URLSession = .shared) throws {
        guard let host = baseURL.host, !token.isEmpty, baseURL.user == nil, baseURL.password == nil,
            baseURL.query == nil, baseURL.fragment == nil,
            baseURL.scheme == "https"
                || (baseURL.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host))
        else {
            throw RevaError.invalid(
                "Use an HTTPS server URL, or HTTP localhost for the demo, and a nonempty token.")
        }
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }
    // MARK: - HTTP boundary
    // Apply auth, a 20-second request timeout and explicit conflict/empty-state handling.
    private func send(
        path: String, method: String = "GET", data: Data? = nil, type: String = "application/json",
        filename: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = data
        request.timeoutInterval = 20
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        if let filename { request.setValue(filename, forHTTPHeaderField: "X-Filename") }
        let (bytes, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RevaError.invalid("The server response was unreadable.")
        }
        if response.statusCode == 409 { throw ServerFailure.conflict }
        if response.statusCode == 404 && path == "v1/state" {
            throw ServerFailure.empty(Int(response.value(forHTTPHeaderField: "X-State-Revision") ?? "0") ?? 0)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ServerFailure.response(response.statusCode)
        }
        return (bytes, response)
    }
    // MARK: - Health and snapshot exchange
    // Read or mutate owner state through the revision-bearing API contract.
    func health() async throws -> String {
        let (data, _) = try await send(path: "health")
        let health = try JSONDecoder().decode(ServerHealth.self, from: data)
        guard health.status == "ok", let storage = health.storage, ["local", "postgres"].contains(storage)
        else { throw RevaError.invalid("The server did not report a healthy supported storage mode.") }
        return "Connected · \(storage)"
    }
    func pull() async throws -> ServerState {
        let (data, _) = try await send(path: "v1/state")
        let state = try JSONDecoder().decode(ServerState.self, from: data)
        try state.snapshot.validate()
        return state
    }
    func push(_ snapshot: AppSnapshot, revision: Int) async throws -> Int {
        struct Body: Encodable {
            let baseRevision: Int
            let snapshot: AppSnapshot
        }
        let body = try JSONEncoder().encode(Body(baseRevision: revision, snapshot: snapshot))
        let (data, _) = try await send(path: "v1/state", method: "PUT", data: body)
        struct Revision: Decodable { let revision: Int }
        return try JSONDecoder().decode(Revision.self, from: data).revision
    }
    // MARK: - Original-file transfer
    // Handle attachment operations separately from the snapshot transaction.
    func uploadAttachment(id: String, filename: String, data: Data, type: String) async throws {
        guard AppSnapshot.safeFilename(id), AppSnapshot.safeFilename(filename) else {
            throw RevaError.invalid("Invalid attachment identifier.")
        }
        _ = try await send(
            path: "v1/attachments/" + id, method: "PUT", data: data, type: type, filename: filename)
    }
    func attachment(id: String) async throws -> Data {
        guard AppSnapshot.safeFilename(id) else { throw RevaError.invalid("Invalid attachment identifier.") }
        return try await send(path: "v1/attachments/" + id).0
    }
    func deleteAttachment(id: String) async throws {
        guard AppSnapshot.safeFilename(id) else { throw RevaError.invalid("Invalid attachment identifier.") }
        _ = try await send(path: "v1/attachments/" + id, method: "DELETE")
    }
    func deleteState() async throws -> Int {
        let (data, _) = try await send(path: "v1/state", method: "DELETE")
        struct Revision: Decodable { let revision: Int }
        return try JSONDecoder().decode(Revision.self, from: data).revision
    }
}
