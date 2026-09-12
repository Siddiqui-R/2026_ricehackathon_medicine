// Purpose: Exercise sign-up, log-in, sessions, password change, deletion, throttling, CORS, and account configuration.
// Inputs: Synthetic emails/passwords, a private static token, bcrypt cost 4, and temporary actor-backed local storage.
// Outputs: Swift Testing assertions on the exact /v1/auth contract, bearer behaviour, and local account persistence.
// Side effects: Writes temporary .accounts.json/owner files and launches VaporTesting applications with cleanup. No network.

import Foundation
import Testing
import VaporTesting

@testable import RevaServer

// MARK: - Fixtures: static identity, sample snapshot, and a temporary account-enabled server
private let staticToken = "static-workspace-token-123456789"
private let goodPassword = "correct-horse-battery"
private let wrongReason = "Email or password is incorrect."
private let sample: JSONValue = .object([
    "schemaVersion": .integer(1),
    "profile": .object(["id": .string("ignored"), "name": .string("Synthetic account holder")]),
    "records": .array([]), "visits": .array([]), "bookings": .array([]), "recordings": .array([]),
])

/// An empty override value removes that variable so tests can reach the loopback demo identity.
private func withAccountServer(
    environment overrides: [String: String] = [:], store existing: LocalFileStore? = nil,
    _ test: (Application, LocalFileStore, ServerConfiguration) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "reva-account-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var environment = ["REVA_TOKENS": "{\"\(staticToken)\":\"static-owner\"}"]
    for (key, value) in overrides { environment[key] = value.isEmpty ? nil : value }
    let configuration = try ServerConfiguration(environment: environment)
    let store = try existing ?? LocalFileStore(directory: directory)
    try await withApp(configure: { app in
        configure(app, configuration: configuration, store: store, accounts: store, passwordCost: 4)
    }) { app in
        try await test(app, store, configuration)
    }
}

private func temporaryDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
}

private func bearer(_ token: String) -> HTTPHeaders { ["Authorization": "Bearer \(token)"] }

private func send(
    _ app: Application, _ method: HTTPMethod, _ path: String, _ body: [String: String],
    headers: HTTPHeaders = [:], check: (TestingHTTPResponse) async throws -> Void
) async throws {
    try await app.testing().test(
        method, path, headers: headers,
        beforeRequest: { request in try request.content.encode(body, as: .json) }, afterResponse: check)
}

private func signup(
    _ app: Application, email: String, password: String = goodPassword, name: String = "Synthetic Person"
) async throws -> AuthSessionEnvelope {
    var envelope: AuthSessionEnvelope?
    try await send(app, .POST, "v1/auth/signup", ["email": email, "password": password, "name": name]) {
        response in
        #expect(response.status == .created)
        envelope = try response.content.decode(AuthSessionEnvelope.self)
    }
    return try #require(envelope)
}

private func login(_ app: Application, email: String, password: String = goodPassword) async throws
    -> AuthSessionEnvelope
{
    var envelope: AuthSessionEnvelope?
    try await send(app, .POST, "v1/auth/login", ["email": email, "password": password]) { response in
        #expect(response.status == .ok)
        envelope = try response.content.decode(AuthSessionEnvelope.self)
    }
    return try #require(envelope)
}

private func reason(_ response: TestingHTTPResponse) -> String {
    (try? response.content.decode(ErrorResponse.self).reason) ?? ""
}

private func stateStatus(_ app: Application, token: String) async throws -> HTTPStatus {
    var status = HTTPStatus.imATeapot
    try await app.testing().test(.GET, "v1/state", headers: bearer(token)) { response async in
        status = response.status
    }
    return status
}

private func storedUser(email: String, password: String = goodPassword) throws -> UserRecord {
    let now = Date()
    return UserRecord(
        id: AccountIdentifiers.userID(), email: email, name: "Stored Person",
        passwordHash: try Bcrypt.hash(password, cost: 4), createdAt: now, passwordUpdatedAt: now)
}

private func storedSession(
    user: UserRecord, token: String, createdAt: Date = Date(), lastUsedAt: Date? = nil,
    expiresAt: Date? = nil,
    revokedAt: Date? = nil
) -> SessionRecord {
    SessionRecord(
        id: UUID(), tokenHash: SessionToken.hash(token), userID: user.id, label: "test", createdAt: createdAt,
        lastUsedAt: lastUsedAt ?? createdAt, expiresAt: expiresAt ?? createdAt.addingTimeInterval(86_400),
        revokedAt: revokedAt)
}

// MARK: - Sign-up, log-in, and session lifecycle over HTTP
@Suite("Accounts and sessions")
struct AccountTests {
    @Test func signupIssuesWorkingSessionWithOwnerIsolation() async throws {
        try await withAccountServer { app, store, _ async throws in
            let first = try await signup(app, email: "First@Example.com", name: "  First Person ")
            #expect(first.token.hasPrefix("rs_") && first.token.count == 46)
            #expect(SessionToken.isWellFormed(first.token))
            #expect(
                first.user.id.hasPrefix("u_") && first.user.id.count == 26 && Validation.safeID(first.user.id)
            )
            #expect(first.user.email == "first@example.com")
            #expect(first.user.name == "First Person")
            #expect(first.expiresAt > Date().addingTimeInterval(29 * 86_400))
            #expect(first.expiresAt < Date().addingTimeInterval(31 * 86_400))
            try await app.testing().test(
                .PUT, "v1/state", headers: bearer(first.token),
                beforeRequest: { request in
                    try request.content.encode(StateWrite(baseRevision: 0, snapshot: sample))
                },
                afterResponse: { response async throws in
                    #expect(response.status == .ok)
                    #expect(try response.content.decode(RevisionResponse.self).revision == 1)
                })
            try await app.testing().test(.GET, "v1/state", headers: bearer(first.token)) {
                response async throws in
                #expect(response.status == .ok)
                #expect(try response.content.decode(StateEnvelope.self).snapshot == sample)
            }
            // The owner of the stored snapshot is the user ID, never a profile field from the snapshot.
            #expect(try await store.getState(owner: first.user.id).revision == 1)
            let second = try await signup(app, email: "second@example.com")
            #expect(try await stateStatus(app, token: second.token) == .notFound)
            #expect(
                try await stateStatus(app, token: "rs_" + String(repeating: "x", count: 43)) == .unauthorized)
            let altered = String(first.token.dropLast()) + (first.token.hasSuffix("0") ? "1" : "0")
            #expect(try await stateStatus(app, token: altered) == .unauthorized)
            // The stored session carries only the SHA-256 hex of the token and the user only a bcrypt hash.
            let pair = try await store.session(tokenHash: SessionToken.hash(first.token))
            let stored = try #require(pair)
            #expect(stored.0.tokenHash.count == 64 && !stored.0.tokenHash.contains("rs_"))
            #expect(stored.1.passwordHash.hasPrefix("$2") && stored.1.passwordHash != goodPassword)
        }
    }

    @Test func duplicateEmailIsRejectedCaseInsensitively() async throws {
        try await withAccountServer { app, _, _ async throws in
            let created = try await signup(app, email: "Person@Example.COM")
            #expect(created.user.email == "person@example.com")
            try await send(
                app, .POST, "v1/auth/signup",
                ["email": " person@example.com ", "password": goodPassword, "name": "Twin"]
            ) { response in
                #expect(response.status == .conflict)
                #expect(reason(response) == "An account with this email already exists.")
            }
        }
    }

    @Test func loginFailuresAreIdenticalAndEmailIsCaseInsensitive() async throws {
        try await withAccountServer { app, _, _ async throws in
            _ = try await signup(app, email: "person@example.com")
            for (email, password) in [
                ("person@example.com", "wrong-password-value"), ("nobody@example.com", goodPassword),
                ("not an email", goodPassword),
            ] {
                try await send(app, .POST, "v1/auth/login", ["email": email, "password": password]) {
                    response in
                    #expect(response.status == .unauthorized)
                    #expect(reason(response) == wrongReason)
                }
            }
            let session = try await login(app, email: "PERSON@EXAMPLE.COM ")
            #expect(try await stateStatus(app, token: session.token) == .notFound)
            try await app.testing().test(.POST, "v1/auth/login", body: ByteBuffer(string: "email=x")) {
                response async in
                #expect(response.status == .unsupportedMediaType)
            }
            try await app.testing().test(
                .POST, "v1/auth/login", headers: ["Content-Type": "application/json"],
                body: ByteBuffer(string: "{\"email\":1}")
            ) { response async in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func loginLocksAfterEightFailuresAndSuccessClearsCounter() async throws {
        try await withAccountServer { app, _, _ async throws in
            _ = try await signup(app, email: "locked@example.com")
            func attempt(_ email: String, password: String = "not-the-password", expected: HTTPStatus)
                async throws
            {
                try await send(app, .POST, "v1/auth/login", ["email": email, "password": password]) {
                    response in
                    #expect(response.status == expected)
                    if expected == .tooManyRequests {
                        let retry = Int(response.headers.first(name: .retryAfter) ?? "") ?? -1
                        #expect((1...900).contains(retry))
                    } else {
                        #expect(response.headers.first(name: .retryAfter) == nil)
                    }
                }
            }
            for _ in 0..<7 { try await attempt("locked@example.com", expected: .unauthorized) }
            _ = try await login(app, email: "locked@example.com")
            // The counter restarted: eight more failures are still 401, the ninth attempt is throttled,
            // and the key is the normalized email so case/whitespace variants share one counter.
            for index in 0..<8 {
                let email = index.isMultiple(of: 2) ? "locked@example.com" : " LOCKED@Example.com "
                try await attempt(email, expected: .unauthorized)
            }
            try await attempt("locked@example.com", expected: .tooManyRequests)
            try await attempt("Locked@example.com", password: goodPassword, expected: .tooManyRequests)
            _ = try await signup(app, email: "free@example.com")
        }
    }

    @Test func sessionEndpointDescribesAccountAndStaticIdentities() async throws {
        try await withAccountServer { app, _, _ async throws in
            let session = try await signup(app, email: "who@example.com")
            try await app.testing().test(.GET, "v1/auth/session", headers: bearer(session.token)) {
                response async throws in
                #expect(response.status == .ok)
                let identity = try response.content.decode(AuthIdentityResponse.self)
                #expect(identity.kind == "account")
                #expect(identity.owner == session.user.id)
                #expect(identity.user == session.user)
                #expect(identity.session?.expiresAt == session.expiresAt)
                #expect(identity.session?.lastUsedAt != nil && identity.session?.createdAt != nil)
            }
            try await app.testing().test(.GET, "v1/auth/session", headers: bearer(staticToken)) {
                response async throws in
                #expect(response.status == .ok)
                let identity = try response.content.decode(AuthIdentityResponse.self)
                #expect(identity.kind == "token")
                #expect(identity.owner == "static-owner")
                #expect(identity.user == nil && identity.session == nil)
            }
            try await app.testing().test(.GET, "v1/auth/session") { response async in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test func logoutRevokesPresentingSessionAndStaticTokensGet400() async throws {
        try await withAccountServer { app, _, _ async throws in
            let first = try await signup(app, email: "out@example.com")
            let second = try await login(app, email: "out@example.com")
            try await app.testing().test(.POST, "v1/auth/logout", headers: bearer(first.token)) {
                response async in
                #expect(response.status == .noContent)
            }
            #expect(try await stateStatus(app, token: first.token) == .unauthorized)
            #expect(try await stateStatus(app, token: second.token) == .notFound)
            try await app.testing().test(.POST, "v1/auth/logout", headers: bearer(first.token)) {
                response async in
                #expect(response.status == .unauthorized)
            }
            for (method, path) in [
                (HTTPMethod.POST, "v1/auth/logout"), (.POST, "v1/auth/logout-all"),
                (.PUT, "v1/auth/password"),
                (.DELETE, "v1/auth/account"),
            ] {
                try await app.testing().test(method, path, headers: bearer(staticToken)) { response async in
                    #expect(response.status == .badRequest)
                    #expect(reason(response) == "Static workspace tokens cannot be logged out.")
                }
            }
        }
    }

    @Test func logoutAllRevokesEverySession() async throws {
        try await withAccountServer { app, _, _ async throws in
            let first = try await signup(app, email: "all@example.com")
            let second = try await login(app, email: "all@example.com")
            try await app.testing().test(.POST, "v1/auth/logout-all", headers: bearer(second.token)) {
                response async in #expect(response.status == .noContent)
            }
            #expect(try await stateStatus(app, token: first.token) == .unauthorized)
            #expect(try await stateStatus(app, token: second.token) == .unauthorized)
            #expect(try await stateStatus(app, token: staticToken) == .notFound)
        }
    }

    @Test func passwordChangeRevokesOtherSessionsAndOldPasswordStopsWorking() async throws {
        try await withAccountServer { app, _, _ async throws in
            let first = try await signup(app, email: "change@example.com")
            let second = try await login(app, email: "change@example.com")
            let newPassword = "a-brand-new-secret-phrase"
            try await send(
                app, .PUT, "v1/auth/password",
                ["currentPassword": "not-it-at-all", "newPassword": newPassword], headers: bearer(first.token)
            ) { response in #expect(response.status == .unauthorized) }
            try await send(
                app, .PUT, "v1/auth/password", ["currentPassword": goodPassword, "newPassword": "short"],
                headers: bearer(first.token)
            ) { response in
                #expect(response.status == .badRequest)
                #expect(reason(response).contains("password"))
            }
            #expect(try await stateStatus(app, token: second.token) == .notFound)
            try await send(
                app, .PUT, "v1/auth/password", ["currentPassword": goodPassword, "newPassword": newPassword],
                headers: bearer(first.token)
            ) { response in #expect(response.status == .noContent) }
            #expect(try await stateStatus(app, token: second.token) == .unauthorized)
            #expect(try await stateStatus(app, token: first.token) == .notFound)
            try await send(
                app, .POST, "v1/auth/login", ["email": "change@example.com", "password": goodPassword]
            ) {
                response in #expect(response.status == .unauthorized)
            }
            _ = try await login(app, email: "change@example.com", password: newPassword)
        }
    }

    @Test func accountDeletionRemovesStateAndSessions() async throws {
        try await withAccountServer { app, store, _ async throws in
            let session = try await signup(app, email: "gone@example.com")
            #expect(try await store.putState(owner: session.user.id, baseRevision: 0, snapshot: sample) == 1)
            try await send(
                app, .DELETE, "v1/auth/account", ["password": "wrong-password-value"],
                headers: bearer(session.token)
            ) { response in #expect(response.status == .unauthorized) }
            #expect(try await store.getState(owner: session.user.id).revision == 1)
            try await send(
                app, .DELETE, "v1/auth/account", ["password": goodPassword], headers: bearer(session.token)
            ) { response in #expect(response.status == .noContent) }
            await #expect(throws: StoreError.self) { try await store.getState(owner: session.user.id) }
            #expect(try await store.user(email: "gone@example.com") == nil)
            #expect(try await store.session(tokenHash: SessionToken.hash(session.token)) == nil)
            #expect(try await stateStatus(app, token: session.token) == .unauthorized)
            try await send(
                app, .POST, "v1/auth/login", ["email": "gone@example.com", "password": goodPassword]
            ) {
                response in #expect(response.status == .unauthorized)
            }
            // The email is free again after a hard delete.
            _ = try await signup(app, email: "gone@example.com")
        }
    }

    // MARK: - Policy, configuration switches, and body limits
    @Test func closedSignupStillAllowsLogin() async throws {
        let directory = temporaryDirectory("reva-closed-signup-")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFileStore(directory: directory)
        try await withAccountServer(store: store) { app, _, _ async throws in
            _ = try await signup(app, email: "early@example.com")
        }
        try await withAccountServer(environment: ["REVA_SIGNUP": "closed"], store: store) {
            app, _, _ async throws in
            try await send(
                app, .POST, "v1/auth/signup",
                ["email": "late@example.com", "password": goodPassword, "name": "Late"]
            ) { response in
                #expect(response.status == .forbidden)
                #expect(reason(response) == "Sign-up is closed on this server.")
            }
            _ = try await login(app, email: "early@example.com")
        }
    }

    @Test func disabledAccountsRemoveRoutesAndRejectSessions() async throws {
        try await withAccountServer(environment: ["REVA_ACCOUNTS": "disabled"]) {
            app, store, configuration async throws in
            #expect(!configuration.accountsEnabled)
            let user = try storedUser(email: "stored@example.com")
            try await store.createUser(user)
            let token = SessionToken.generate()
            try await store.createSession(storedSession(user: user, token: token))
            #expect(try await store.session(tokenHash: SessionToken.hash(token)) != nil)
            #expect(try await stateStatus(app, token: token) == .unauthorized)
            #expect(try await stateStatus(app, token: staticToken) == .notFound)
            try await send(
                app, .POST, "v1/auth/signup",
                ["email": "new@example.com", "password": goodPassword, "name": "New"]
            ) { response in #expect(response.status == .notFound) }
            try await send(
                app, .POST, "v1/auth/login", ["email": "stored@example.com", "password": goodPassword]
            ) {
                response in #expect(response.status == .notFound)
            }
            try await app.testing().test(.GET, "v1/auth/session", headers: bearer(staticToken)) {
                response async in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test func demoModeAlsoServesAccounts() async throws {
        try await withAccountServer(environment: ["REVA_TOKENS": ""]) { app, _, configuration async throws in
            #expect(
                configuration.isDemo && configuration.accountsEnabled
                    && !configuration.providers.paidAccessAllowed)
            let session = try await signup(app, email: "demo-user@example.com")
            #expect(try await stateStatus(app, token: session.token) == .notFound)
            #expect(try await stateStatus(app, token: ServerConfiguration.demoToken) == .notFound)
        }
    }

    @Test func passwordEmailAndNamePolicyBounds() async throws {
        try await withAccountServer { app, _, _ async throws in
            func rejected(_ body: [String: String], field: String) async throws {
                try await send(app, .POST, "v1/auth/signup", body) { response in
                    #expect(response.status == .badRequest)
                    #expect(reason(response).contains(field), "\(field): \(reason(response))")
                }
            }
            func body(password: String, email: String = "policy@example.com", name: String = "Policy")
                -> [String: String]
            {
                ["email": email, "password": password, "name": name]
            }
            try await rejected(body(password: String(repeating: "p", count: 9)), field: "password")
            try await rejected(body(password: String(repeating: "p", count: 73)), field: "password")
            try await rejected(body(password: "line\nbreak-password"), field: "password")
            try await rejected(body(password: "return\rpassword"), field: "password")
            try await rejected(body(password: "Policy@Example.com"), field: "password")
            try await rejected(body(password: goodPassword, email: "not-an-email"), field: "email")
            try await rejected(body(password: goodPassword, email: "a@b"), field: "email")
            try await rejected(body(password: goodPassword, email: "two@@example.com"), field: "email")
            try await rejected(
                body(password: goodPassword, email: String(repeating: "a", count: 250) + "@x.com"),
                field: "email")
            try await rejected(body(password: goodPassword, name: "   "), field: "name")
            try await rejected(
                body(password: goodPassword, name: String(repeating: "n", count: 81)), field: "name")
            try await rejected(body(password: goodPassword, name: "tab\tname"), field: "name")
            // Ten bytes and seventy-two bytes are accepted; multi-byte characters count in bytes.
            _ = try await signup(app, email: "ten@example.com", password: String(repeating: "p", count: 10))
            _ = try await signup(
                app, email: "seventytwo@example.com", password: String(repeating: "p", count: 72))
            try await rejected(
                body(password: String(repeating: "é", count: 37), email: "bytes@example.com"),
                field: "password")
            let oversize =
                "{\"email\":\"policy@example.com\",\"name\":\"P\",\"password\":\""
                + String(repeating: "x", count: 16 * 1024) + "\"}"
            try await app.testing().test(
                .POST, "v1/auth/signup", headers: ["Content-Type": "application/json"],
                body: ByteBuffer(string: oversize)
            ) { response async in
                #expect(response.status == .payloadTooLarge)
            }
            try await app.testing().test(
                .POST, "v1/auth/signup", headers: ["Content-Type": "text/plain"],
                body: ByteBuffer(string: "{}")
            ) { response async in
                #expect(response.status == .unsupportedMediaType)
            }
        }
    }

    @Test func accountConfigurationRules() throws {
        let database = "postgres://user:secret@db.example/reva?sslmode=verify-full"
        let accountsOnly = try ServerConfiguration(environment: [
            "REVA_STORAGE": "postgres", "DATABASE_URL": database,
        ])
        #expect(accountsOnly.tokens.isEmpty && !accountsOnly.isDemo && accountsOnly.accountsEnabled)
        #expect(accountsOnly.postgres != nil && accountsOnly.providers.paidAccessAllowed)
        #expect(throws: ConfigurationError.self) {
            try ServerConfiguration(environment: [
                "REVA_STORAGE": "postgres", "DATABASE_URL": database, "REVA_ACCOUNTS": "disabled",
            ])
        }
        let demo = try ServerConfiguration(environment: [:])
        #expect(demo.isDemo && demo.accountsEnabled && demo.signupOpen && demo.sessionDays == 30)
        #expect(demo.tokens == [ServerConfiguration.demoToken: "demo-user"] && demo.allowedOrigins.isEmpty)
        let tuned = try ServerConfiguration(environment: [
            "REVA_ACCOUNTS": "disabled", "REVA_SIGNUP": "closed", "REVA_SESSION_DAYS": "365",
            "REVA_ALLOWED_ORIGINS":
                " https://reva.example , http://localhost:5173,http://127.0.0.1,https://reva.example",
        ])
        #expect(!tuned.accountsEnabled && !tuned.signupOpen && tuned.sessionDays == 365)
        #expect(
            tuned.allowedOrigins == ["https://reva.example", "http://localhost:5173", "http://127.0.0.1"])
        #expect(try ServerConfiguration(environment: ["REVA_ALLOWED_ORIGINS": " "]).allowedOrigins.isEmpty)
        for environment in [
            ["REVA_ACCOUNTS": "yes"], ["REVA_SIGNUP": "maybe"], ["REVA_SESSION_DAYS": "0"],
            ["REVA_SESSION_DAYS": "366"], ["REVA_SESSION_DAYS": "thirty"], ["REVA_ALLOWED_ORIGINS": "*"],
            ["REVA_ALLOWED_ORIGINS": "http://example.com"], ["REVA_ALLOWED_ORIGINS": "https://example.com/"],
            ["REVA_ALLOWED_ORIGINS": "https://user@example.com"],
            ["REVA_ALLOWED_ORIGINS": "https://Example.com"],
            ["REVA_ALLOWED_ORIGINS": "https://a.example,,https://b.example"],
            ["REVA_ALLOWED_ORIGINS": "example.com"],
            ["REVA_ALLOWED_ORIGINS": "https://example.com?x=1"],
            ["REVA_ALLOWED_ORIGINS": "http://localhost:99999"],
            ["REVA_ALLOWED_ORIGINS": "https://example.com/app#x"],
        ] {
            #expect(throws: ConfigurationError.self, "\(environment)") {
                try ServerConfiguration(environment: environment)
            }
        }
    }

    @Test func corsEchoesOnlyListedOrigins() async throws {
        try await withAccountServer(environment: [
            "REVA_ALLOWED_ORIGINS": "https://reva.example,http://localhost:5173"
        ]) {
            app, _, _ async throws in
            try await app.testing().test(
                .OPTIONS, "v1/state",
                headers: ["Origin": "https://reva.example", "Access-Control-Request-Method": "PUT"]
            ) { response async in
                #expect(response.status == .noContent)
                #expect(response.headers.first(name: .accessControlAllowOrigin) == "https://reva.example")
                #expect(
                    response.headers.first(name: .accessControlAllowMethods)
                        == "GET, PUT, POST, DELETE, OPTIONS")
                #expect(
                    response.headers.first(name: .accessControlAllowHeaders)
                        == "Authorization, Content-Type, X-Filename")
                #expect(response.headers.first(name: .accessControlMaxAge) == "600")
                #expect(response.headers[.vary].contains("Origin"))
                #expect(response.headers.first(name: .accessControlAllowCredentials) == nil)
            }
            try await app.testing().test(.GET, "health", headers: ["Origin": "http://localhost:5173"]) {
                response async in
                #expect(response.status == .ok)
                #expect(response.headers.first(name: .accessControlAllowOrigin) == "http://localhost:5173")
                #expect(response.headers.first(name: .accessControlExpose) == "X-State-Revision, X-Filename")
                #expect(response.headers[.vary].contains("Origin"))
            }
            // Error responses for an allowed origin still carry the CORS headers so the browser can read them.
            try await app.testing().test(.GET, "v1/state", headers: ["Origin": "https://reva.example"]) {
                response async in
                #expect(response.status == .unauthorized)
                #expect(response.headers.first(name: .accessControlAllowOrigin) == "https://reva.example")
            }
            for origin in [
                "https://evil.example", "https://reva.example.attacker.test", "http://reva.example", "*",
            ] {
                try await app.testing().test(.GET, "health", headers: ["Origin": origin]) { response async in
                    #expect(response.status == .ok)
                    #expect(response.headers.first(name: .accessControlAllowOrigin) == nil)
                    #expect(response.headers.first(name: .accessControlExpose) == nil)
                    #expect(!response.headers[.vary].contains("Origin"))
                }
                try await app.testing().test(
                    .OPTIONS, "v1/state", headers: ["Origin": origin, "Access-Control-Request-Method": "PUT"]
                ) { response async in
                    #expect(response.status != .noContent)
                    #expect(response.headers.first(name: .accessControlAllowOrigin) == nil)
                }
            }
        }
        try await withAccountServer { app, _, _ async throws in
            try await app.testing().test(.GET, "health", headers: ["Origin": "https://reva.example"]) {
                response async in
                #expect(response.headers.first(name: .accessControlAllowOrigin) == nil)
            }
        }
    }

    // MARK: - Bearer session checks, local persistence, and bounds
    @Test func sessionExpiryRevocationAndLastUsedTouch() async throws {
        try await withAccountServer { app, store, _ async throws in
            let user = try storedUser(email: "touch@example.com")
            try await store.createUser(user)
            let now = Date()
            let stale = SessionToken.generate()
            try await store.createSession(
                storedSession(
                    user: user, token: stale, createdAt: now.addingTimeInterval(-3600),
                    lastUsedAt: now.addingTimeInterval(-600)))
            let fresh = SessionToken.generate()
            try await store.createSession(
                storedSession(
                    user: user, token: fresh, createdAt: now, lastUsedAt: now.addingTimeInterval(-60)))
            let expired = SessionToken.generate()
            try await store.createSession(
                storedSession(
                    user: user, token: expired, createdAt: now, expiresAt: now.addingTimeInterval(-1)))
            let revoked = SessionToken.generate()
            try await store.createSession(
                storedSession(user: user, token: revoked, createdAt: now, revokedAt: now))
            #expect(try await stateStatus(app, token: stale) == .notFound)
            #expect(try await stateStatus(app, token: fresh) == .notFound)
            #expect(try await stateStatus(app, token: expired) == .unauthorized)
            #expect(try await stateStatus(app, token: revoked) == .unauthorized)
            let touchedPair = try await store.session(tokenHash: SessionToken.hash(stale))
            #expect(try #require(touchedPair).0.lastUsedAt > now.addingTimeInterval(-5))
            let untouchedPair = try await store.session(tokenHash: SessionToken.hash(fresh))
            #expect(
                abs(try #require(untouchedPair).0.lastUsedAt.timeIntervalSince(now.addingTimeInterval(-60)))
                    < 1)
            // The session label keeps only printable ASCII from the User-Agent, at most 120 characters.
            let agent = "Reva-Test/1.0 \u{1F600}\u{7} " + String(repeating: "a", count: 200)
            var token: String?
            try await app.testing().test(
                .POST, "v1/auth/login", headers: ["Content-Type": "application/json", "User-Agent": agent],
                body: ByteBuffer(string: "{\"email\":\"touch@example.com\",\"password\":\"\(goodPassword)\"}")
            ) { response async throws in
                #expect(response.status == .ok)
                token = try response.content.decode(AuthSessionEnvelope.self).token
            }
            let labelledPair = try await store.session(tokenHash: SessionToken.hash(try #require(token)))
            let label = try #require(labelledPair).0.label
            #expect(label.count == 120 && label.hasPrefix("Reva-Test/1.0  aaa"))
            #expect(label.unicodeScalars.allSatisfy { (32...126).contains($0.value) })
        }
    }

    @Test func localAccountsPersistAcrossStoreInstancesWithPrivatePermissions() async throws {
        let directory = temporaryDirectory("reva-account-restart-")
        defer { try? FileManager.default.removeItem(at: directory) }
        let user = try storedUser(email: "persist@example.com")
        let token = SessionToken.generate()
        let session = storedSession(user: user, token: token)
        let file = directory.appendingPathComponent(".accounts.json")
        func writeOriginal() async throws {
            let original = try LocalFileStore(directory: directory)
            try await original.createUser(user)
            try await original.createSession(session)
            await #expect(throws: AccountError.self) {
                try await original.createUser(try storedUser(email: "PERSIST@example.com"))
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((attributes[.posixPermissions] as? Int) == 0o600)
            let raw = try String(contentsOf: file, encoding: .utf8)
            #expect(
                raw.contains("\"formatVersion\":1") && !raw.contains(token) && !raw.contains(goodPassword))
        }
        try await writeOriginal()
        let restarted = try LocalFileStore(directory: directory)
        #expect(try await restarted.user(email: "persist@example.com") == user)
        #expect(try await restarted.user(id: user.id) == user)
        let foundPair = try await restarted.session(tokenHash: SessionToken.hash(token))
        let found = try #require(foundPair)
        #expect(found.0 == session && found.1 == user)
        try await restarted.updatePassword(
            userID: user.id, hash: try Bcrypt.hash("replacement-secret", cost: 4), at: Date())
        #expect(try await restarted.user(id: user.id)?.passwordHash != user.passwordHash)
        await #expect(throws: AccountError.self) {
            try await restarted.updatePassword(userID: "u_missing", hash: "$2b$04$x", at: Date())
        }
        await #expect(throws: AccountError.self) { try await restarted.touchSession(id: UUID(), at: Date()) }
        await #expect(throws: AccountError.self) { try await restarted.revokeSession(id: UUID()) }
        await #expect(throws: AccountError.self) { try await restarted.deleteUser(id: "u_missing") }
        try Data("broken accounts JSON".utf8).write(to: file)
        await #expect(throws: StoreError.self) { try await restarted.user(email: "persist@example.com") }
        await #expect(throws: StoreError.self) {
            try await restarted.createUser(try storedUser(email: "x@example.com"))
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "broken accounts JSON")
    }

    @Test func twentySessionCapRevokesOldestAndPrunesStaleRows() async throws {
        let directory = temporaryDirectory("reva-session-cap-")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFileStore(directory: directory)
        try await withAccountServer(store: store) { app, _, _ async throws in
            let user = try storedUser(email: "cap@example.com")
            try await store.createUser(user)
            let base = Date().addingTimeInterval(-600)
            var tokens: [String] = []
            for index in 0..<21 {
                let token = SessionToken.generate()
                tokens.append(token)
                try await store.createSession(
                    storedSession(user: user, token: token, createdAt: base.addingTimeInterval(Double(index)))
                )
            }
            #expect(try await store.session(tokenHash: SessionToken.hash(tokens[0])) == nil)
            for token in tokens.dropFirst() {
                #expect(try await store.session(tokenHash: SessionToken.hash(token)) != nil)
            }
            // Logging in over HTTP is the 22nd session, so the second oldest goes as well.
            let http = try await login(app, email: "cap@example.com")
            #expect(try await store.session(tokenHash: SessionToken.hash(tokens[1])) == nil)
            #expect(try await store.session(tokenHash: SessionToken.hash(tokens[2])) != nil)
            #expect(try await stateStatus(app, token: http.token) == .notFound)
            // A session revoked more than 30 days ago disappears from .accounts.json on the next write.
            let ancient = SessionToken.generate()
            try await store.createSession(
                storedSession(
                    user: user, token: ancient, createdAt: Date().addingTimeInterval(-40 * 86_400),
                    revokedAt: Date().addingTimeInterval(-31 * 86_400)))
            try await store.revokeSessions(userID: user.id, except: nil)
            let document = try JSONDecoder().decode(
                AccountsDocument.self,
                from: Data(contentsOf: directory.appendingPathComponent(".accounts.json")))
            #expect(!document.sessions.contains { $0.tokenHash == SessionToken.hash(ancient) })
            #expect(document.sessions.filter { $0.userID == user.id }.count == 22)
            #expect(document.sessions.allSatisfy { $0.revokedAt != nil })
            #expect(try await stateStatus(app, token: http.token) == .unauthorized)
        }
    }

    // MARK: - Primitive units: tokens, identifiers, and the throttle table
    @Test func tokensIdentifiersAndThrottleBounds() async throws {
        var seen: Set<String> = []
        for _ in 0..<64 {
            let token = SessionToken.generate()
            #expect(SessionToken.isWellFormed(token))
            #expect(SessionToken.hash(token).range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
            seen.insert(token)
            let id = AccountIdentifiers.userID()
            #expect(
                id.range(of: "^u_[0-9a-f]{24}$", options: .regularExpression) != nil && Validation.safeID(id))
        }
        #expect(seen.count == 64)
        for bad in [
            "rs_short", "xx_" + String(repeating: "a", count: 43),
            "rs_" + String(repeating: "a", count: 42) + "+",
            "rs_" + String(repeating: "a", count: 44), "",
        ] {
            #expect(!SessionToken.isWellFormed(bad))
        }
        #expect(AccountPolicy.sessionLabel(userAgent: nil) == "")
        #expect(AccountPolicy.sessionLabel(userAgent: "ok\u{1F600}\n!") == "ok!")
        let throttle = LoginThrottle()
        let start = Date()
        for _ in 0..<7 { await throttle.recordFailure("a@example.com", now: start) }
        #expect(await throttle.retryAfter("a@example.com", now: start) == nil)
        await throttle.recordFailure("a@example.com", now: start)
        #expect(await throttle.retryAfter("a@example.com", now: start.addingTimeInterval(60)) == 840)
        #expect(await throttle.retryAfter("a@example.com", now: start.addingTimeInterval(901)) == nil)
        for index in 0..<LoginThrottle.maximumKeys + 50 {
            await throttle.recordFailure(
                "user\(index)@example.com", now: start.addingTimeInterval(Double(index) / 1000))
        }
        #expect(await throttle.trackedKeyCount <= LoginThrottle.maximumKeys)
        #expect(
            await throttle.retryAfter("user\(LoginThrottle.maximumKeys + 49)@example.com", now: start) == nil)
        for _ in 0..<8 { await throttle.recordFailure("b@example.com", now: start) }
        #expect(await throttle.retryAfter("b@example.com", now: start) != nil)
        await throttle.clear("b@example.com")
        #expect(await throttle.retryAfter("b@example.com", now: start) == nil)
    }
}
