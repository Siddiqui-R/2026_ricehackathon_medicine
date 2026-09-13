// Native account contracts use the same hosted authentication API as the browser.
import CryptoKit
import Foundation

struct NativeAccountUser: Codable, Equatable {
    var id: String
    var email: String
    var name: String
    var createdAt: String
}
struct NativeAccountSession: Codable, Equatable {
    var token: String
    var expiresAt: String
    var user: NativeAccountUser

    func validate() throws {
        guard !token.isEmpty, token.count <= 512, !token.contains(where: { $0.isNewline }),
            !user.id.isEmpty, user.id.count <= 80, !user.name.isEmpty, user.name.count <= 80,
            user.email.count <= 254, RevaDate.parse(expiresAt) > Date()
        else { throw RevaError.invalid("The session is invalid or expired. Please log in again.") }
    }
}
enum NativeAccount {
    static let origin = URL(string: "https://revamed.health")!
    static func directoryName(_ userID: String) -> String {
        "account-" + SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func emptySnapshot(_ user: NativeAccountUser) -> AppSnapshot {
        let words = user.name.split(whereSeparator: \.isWhitespace)
        let initials = [words.first?.first, words.count > 1 ? words.last?.first : nil]
            .compactMap { $0.map(String.init) }.joined().uppercased()
        return AppSnapshot(
            profile: PatientProfile(
                id: user.id, name: user.name, dateOfBirth: "", initials: initials,
                allergies: [], medications: [], conditions: [], isDemo: false), records: [], visits: [])
    }
    static func passwordProblem(_ password: String) -> String? {
        if password.unicodeScalars.count < 8 { return "Use at least 8 characters." }
        if password.utf8.count > 72 { return "Use at most 72 UTF-8 bytes." }
        if password.contains(where: \.isNewline) { return "A password cannot contain line breaks." }
        if password.range(of: "[A-Z]", options: .regularExpression) == nil {
            return "Include at least 1 capital letter."
        }
        if password.range(of: "[0-9]", options: .regularExpression) == nil {
            return "Include at least 1 number."
        }
        if !password.unicodeScalars.contains(where: {
            CharacterSet.punctuationCharacters.union(.symbols).contains($0)
        }) {
            return "Include at least 1 symbol."
        }
        return nil
    }
}
enum NativeAuthFailure: LocalizedError {
    case response(Int, String)
    var errorDescription: String? {
        if case .response(_, let message) = self { return message }
        return nil
    }
    var status: Int {
        if case .response(let status, _) = self { return status }
        return 0
    }
}
private final class NativeNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
enum NativeAccountTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: NativeNoRedirects(), delegateQueue: nil)
    }()
}
struct NativeAuthClient {
    var origin = NativeAccount.origin
    var token: String? = nil
    var session: URLSession = NativeAccountTransport.session

    private func send(_ route: String, method: String, body: [String: String]? = nil) async throws -> Data {
        guard
            origin.scheme == "https"
                || (origin.scheme == "http" && ["localhost", "127.0.0.1"].contains(origin.host ?? "")),
            origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil
        else { throw RevaError.invalid("Use a secure Reva server.") }
        var request = URLRequest(url: origin.appendingPathComponent("v1/auth/" + route))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            guard request.httpBody!.count <= 16 * 1024 else {
                throw RevaError.invalid("The request is too large.")
            }
        }
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse, data.count <= 64 * 1024 else {
            throw RevaError.invalid("The account server response was unreadable.")
        }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { var reason: String? }
            let reason = (try? JSONDecoder().decode(Failure.self, from: data))?.reason
            throw NativeAuthFailure.response(
                response.statusCode, reason ?? "The account request could not finish. Please try again.")
        }
        return data
    }
    func authenticate(email: String, password: String, name: String? = nil) async throws
        -> NativeAccountSession
    {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil,
            email.count <= 254, !password.isEmpty
        else { throw RevaError.invalid("Enter your email and password.") }
        var body = ["email": email, "password": password]
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 80 else {
                throw RevaError.invalid("Enter a name of up to 80 characters.")
            }
            if let problem = NativeAccount.passwordProblem(password) { throw RevaError.invalid(problem) }
            body["name"] = trimmed
        }
        let data = try await send(name == nil ? "login" : "signup", method: "POST", body: body)
        let result = try JSONDecoder().decode(NativeAccountSession.self, from: data)
        try result.validate()
        return result
    }
    func logout(all: Bool = false) async throws {
        _ = try await send(all ? "logout-all" : "logout", method: "POST")
    }
    func changePassword(current: String, new: String) async throws {
        if let problem = NativeAccount.passwordProblem(new) { throw RevaError.invalid(problem) }
        guard !current.isEmpty, current != new else {
            throw RevaError.invalid("Enter your current password and a different new password.")
        }
        _ = try await send("password", method: "PUT", body: ["currentPassword": current, "newPassword": new])
    }
    func deleteAccount(password: String) async throws {
        guard !password.isEmpty else {
            throw RevaError.invalid("Enter your password to delete your account.")
        }
        _ = try await send("account", method: "DELETE", body: ["password": password])
    }
}
