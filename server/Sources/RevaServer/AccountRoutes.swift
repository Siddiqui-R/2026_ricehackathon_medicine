// Purpose: Register the /v1/auth routes for sign-up, log-in, session inspection, logout, password change, and deletion.
// Inputs: Bounded application/json bodies (16 KiB), the account store, the bcrypt hasher, and authenticated identities.
// Outputs: Session envelopes with opaque rs_ tokens, 204 mutations, or exact policy/authentication/conflict errors.
// Side effects: Creates users and sessions, revokes sessions, rewrites password hashes, and hard-deletes accounts with their data.
// Ownership: Static workspace tokens can inspect their identity but cannot use the account mutation routes.

import Vapor

// MARK: - Route registration
/// Public routes live outside the bearer group; the remaining routes reuse the secured /v1 group.
func registerAccountRoutes(
    _ app: Application, secured: any RoutesBuilder, configuration: ServerConfiguration,
    accounts: any AccountStore, hasher: PasswordHasher
) {
    let throttle = LoginThrottle()
    let sessionLifetime = TimeInterval(configuration.sessionDays) * 24 * 60 * 60
    let bodyLimit = 16 * 1024
    let publicAuth = app.grouped("v1", "auth")

    // MARK: - Issue a session for a verified user
    @Sendable func issueSession(_ request: Request, user: UserRecord, status: HTTPStatus) async throws
        -> Response
    {
        let now = Date()
        let token = SessionToken.generate()
        let session = SessionRecord(
            id: UUID(), tokenHash: SessionToken.hash(token), userID: user.id,
            label: AccountPolicy.sessionLabel(userAgent: request.headers.first(name: .userAgent)),
            createdAt: now, lastUsedAt: now, expiresAt: now.addingTimeInterval(sessionLifetime),
            revokedAt: nil)
        try await accounts.createSession(session)
        let response = Response(status: status)
        try response.content.encode(
            AuthSessionEnvelope(token: token, expiresAt: session.expiresAt, user: AuthUser(user)))
        return response
    }

    // MARK: - Sign-up with policy validation and duplicate detection
    publicAuth.on(.POST, "signup", body: .collect(maxSize: "16kb")) { request async throws -> Response in
        guard configuration.signupOpen else {
            throw Abort(.forbidden, reason: "Sign-up is closed on this server.")
        }
        try requireAuthJSON(request, limit: bodyLimit)
        let input: SignupRequest
        do { input = try request.content.decode(SignupRequest.self) } catch {
            throw Abort(.badRequest, reason: "Expected JSON with email, password and name strings.")
        }
        let email = try AccountPolicy.normalizeEmail(input.email)
        let name = try AccountPolicy.normalizeName(input.name)
        try AccountPolicy.validatePassword(input.password, email: email)
        // Check before hashing so a duplicate costs no bcrypt work; the store still rejects a racing duplicate.
        guard try await accounts.user(email: email) == nil else { throw AccountError.emailTaken }
        let now = Date()
        let user = UserRecord(
            id: AccountIdentifiers.userID(), email: email, name: name,
            passwordHash: try await hasher.hash(input.password), createdAt: now, passwordUpdatedAt: now)
        try await accounts.createUser(user)
        return try await issueSession(request, user: user, status: .created)
    }

    // MARK: - Log-in with indistinguishable failures and a per-email throttle
    publicAuth.on(.POST, "login", body: .collect(maxSize: "16kb")) { request async throws -> Response in
        try requireAuthJSON(request, limit: bodyLimit)
        let input: LoginRequest
        do { input = try request.content.decode(LoginRequest.self) } catch {
            throw Abort(.badRequest, reason: "Expected JSON with email and password strings.")
        }
        let key = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let retryAfter = await throttle.retryAfter(key) {
            throw Abort(
                .tooManyRequests, headers: ["Retry-After": String(retryAfter)],
                reason: "Too many failed log-in attempts. Try again later.")
        }
        var record: UserRecord?
        if let email = try? AccountPolicy.normalizeEmail(input.email) {
            record = try await accounts.user(email: email)
        }
        let verified: Bool
        if let record, input.password.utf8.count <= AccountPolicy.maximumPasswordBytes {
            verified = try await hasher.verify(input.password, against: record.passwordHash)
        } else {
            // Unknown email or oversize password: pay the same bcrypt cost so timing does not reveal existence.
            await hasher.verifyAgainstDummy(
                String(
                    decoding: input.password.utf8.prefix(AccountPolicy.maximumPasswordBytes), as: UTF8.self))
            verified = false
        }
        guard verified, let record else {
            await throttle.recordFailure(key)
            throw Abort(.unauthorized, reason: "Email or password is incorrect.")
        }
        await throttle.clear(key)
        return try await issueSession(request, user: record, status: .ok)
    }

    // MARK: - Identity inspection for both bearer kinds
    let auth = secured.grouped("auth")
    auth.get("session") { request async throws -> AuthIdentityResponse in
        let identity = try request.auth.require(OwnerIdentity.self)
        return AuthIdentityResponse(
            kind: identity.session == nil ? "token" : "account", owner: identity.id,
            user: identity.user.map(AuthUser.init), session: identity.session.map(AuthSessionSummary.init))
    }

    // MARK: - Session revocation
    auth.post("logout") { request async throws -> HTTPStatus in
        let (session, _) = try requireAccount(request)
        try await accounts.revokeSession(id: session.id)
        return .noContent
    }
    auth.post("logout-all") { request async throws -> HTTPStatus in
        let (_, user) = try requireAccount(request)
        try await accounts.revokeSessions(userID: user.id, except: nil)
        return .noContent
    }

    // MARK: - Password change keeps only the presenting session
    auth.on(.PUT, "password", body: .collect(maxSize: "16kb")) { request async throws -> HTTPStatus in
        let (session, user) = try requireAccount(request)
        try requireAuthJSON(request, limit: bodyLimit)
        let input: PasswordChangeRequest
        do { input = try request.content.decode(PasswordChangeRequest.self) } catch {
            throw Abort(.badRequest, reason: "Expected JSON with currentPassword and newPassword strings.")
        }
        try AccountPolicy.validatePassword(input.newPassword, email: user.email)
        guard try await verifyCurrent(input.currentPassword, for: user, hasher: hasher) else {
            throw Abort(.unauthorized, reason: "Current password is incorrect.")
        }
        try await accounts.updatePassword(userID: user.id, hash: hasher.hash(input.newPassword), at: Date())
        try await accounts.revokeSessions(userID: user.id, except: session.id)
        return .noContent
    }

    // MARK: - Hard account deletion after password verification
    auth.on(.DELETE, "account", body: .collect(maxSize: "16kb")) { request async throws -> HTTPStatus in
        let (_, user) = try requireAccount(request)
        try requireAuthJSON(request, limit: bodyLimit)
        let input: AccountDeleteRequest
        do { input = try request.content.decode(AccountDeleteRequest.self) } catch {
            throw Abort(.badRequest, reason: "Expected JSON with a password string.")
        }
        guard try await verifyCurrent(input.password, for: user, hasher: hasher) else {
            throw Abort(.unauthorized, reason: "Password is incorrect.")
        }
        try await accounts.deleteUser(id: user.id)
        return .noContent
    }
}

// MARK: - Shared request guards
/// Auth bodies must be JSON and at most 16 KiB; the explicit size check also covers pre-collected bodies.
private func requireAuthJSON(_ request: Request, limit: Int) throws {
    guard (request.body.data?.readableBytes ?? 0) <= limit else {
        throw Abort(.payloadTooLarge, reason: "Auth requests are limited to 16 KiB.")
    }
    guard let type = request.headers.contentType, type.type.lowercased() == "application",
        type.subType.lowercased() == "json"
    else {
        throw Abort(.unsupportedMediaType, reason: "Auth requests require application/json.")
    }
}

/// Static workspace tokens have no session to revoke, password to change, or account to delete.
private func requireAccount(_ request: Request) throws -> (SessionRecord, UserRecord) {
    let identity = try request.auth.require(OwnerIdentity.self)
    guard let session = identity.session, let user = identity.user else {
        throw Abort(.badRequest, reason: "Static workspace tokens cannot be logged out.")
    }
    return (session, user)
}

private func verifyCurrent(_ password: String, for user: UserRecord, hasher: PasswordHasher) async throws
    -> Bool
{
    guard password.utf8.count <= AccountPolicy.maximumPasswordBytes, !password.isEmpty else { return false }
    return try await hasher.verify(password, against: user.passwordHash)
}
