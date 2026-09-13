// Purpose: Expose storage/provider/account routes behind owner authentication, optional CORS, and consistent safe errors.
// Inputs: HTTP requests, validated server settings, a store, an optional account store, and an optional mock Gemini transport.
// Outputs: Bounded JSON/binary responses with no-store headers and explicit revision/conflict metadata.
// Side effects: Registers routes/middleware, then delegates storage changes and configured provider requests.
// Ownership: The bearer mapping chooses the owner. Client snapshot contents cannot choose another owner.

import Vapor

// MARK: - Bearer matching for static tokens and account sessions
/// Static tokens are compared in constant time first; otherwise a well-formed rs_ token is looked up by its SHA-256 hex.
struct BearerMiddleware: AsyncMiddleware {
    let tokens: [String: String]
    let accounts: (any AccountStore)?

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let supplied = request.headers.bearerAuthorization?.token, supplied.utf8.count <= 256 else {
            throw Self.unauthorized
        }
        if let owner = tokens.first(where: { constantTimeEqual($0.key, supplied) })?.value {
            request.auth.login(OwnerIdentity(id: owner))
            return try await next.respond(to: request)
        }
        guard let accounts, SessionToken.isWellFormed(supplied),
            let (session, user) = try await accounts.session(tokenHash: SessionToken.hash(supplied))
        else { throw Self.unauthorized }
        let now = Date()
        guard session.isLive(at: now), Validation.safeID(user.id) else { throw Self.unauthorized }
        // Update lastUsedAt at most once per five minutes so reads do not rewrite the session on every request.
        if now.timeIntervalSince(session.lastUsedAt) > AccountPolicy.sessionTouchInterval {
            try await accounts.touchSession(id: session.id, at: now)
        }
        request.auth.login(OwnerIdentity(id: user.id, session: session, user: user))
        return try await next.respond(to: request)
    }

    private static var unauthorized: Abort {
        Abort(
            .unauthorized, headers: ["WWW-Authenticate": "Bearer"],
            reason: "A valid bearer token is required.")
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8)
        let right = Array(b.utf8)
        var difference = left.count ^ right.count
        for index in 0..<max(left.count, right.count) {
            difference |= Int(
                (index < left.count ? left[index] : 0) ^ (index < right.count ? right[index] : 0))
        }
        return difference == 0
    }
}

// MARK: - Exact-origin CORS for the browser client
/// Only configured origins are echoed; there is no wildcard and no credentials flag because bearer tokens are used.
struct CORSPolicyMiddleware: AsyncMiddleware {
    let origins: Set<String>

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let origin = request.headers.first(name: .origin), origins.contains(origin) else {
            return try await next.respond(to: request)
        }
        if request.method == .OPTIONS, request.headers.contains(name: .accessControlRequestMethod) {
            let response = Response(status: .noContent)
            apply(origin: origin, to: response)
            response.headers.replaceOrAdd(
                name: .accessControlAllowMethods, value: "GET, PUT, POST, DELETE, OPTIONS")
            response.headers.replaceOrAdd(
                name: .accessControlAllowHeaders,
                value: "Authorization, Content-Type, X-Filename, X-Reva-Gemini-Fallback")
            response.headers.replaceOrAdd(name: .accessControlMaxAge, value: "600")
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return response
        }
        let response = try await next.respond(to: request)
        apply(origin: origin, to: response)
        return response
    }

    private func apply(origin: String, to response: Response) {
        response.headers.replaceOrAdd(name: .accessControlAllowOrigin, value: origin)
        response.headers.replaceOrAdd(
            name: .accessControlExpose,
            value: "X-State-Revision, X-Filename, Retry-After, X-Reva-Gemini-Fallback")
        response.headers.add(name: .vary, value: "Origin")
    }
}

// MARK: - Public error mapping and response privacy headers
// Never pass raw database/provider failures into an HTTP response.
private struct SafeErrors: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response: Response
        do { response = try await next.respond(to: request) } catch {
            let status: HTTPResponseStatus
            let reason: String
            var headers = HTTPHeaders()
            switch error {
            case StoreError.conflict(let revision):
                status = .conflict
                reason = "State changed on the server. Fetch and review before retrying."
                headers.replaceOrAdd(name: "X-State-Revision", value: String(revision))
            case StoreError.missing(let revision):
                status = .notFound
                reason = "No snapshot exists for this owner."
                headers.replaceOrAdd(name: "X-State-Revision", value: String(revision))
            case StoreError.attachmentMissing:
                status = .notFound
                reason = "Attachment not found."
            case StoreError.quota:
                status = .payloadTooLarge
                reason = "Owner attachment limit is 64 MiB and 128 files."
            case AccountError.emailTaken:
                status = .conflict
                reason = "An account with this email already exists."
            case AccountError.userMissing:
                status = .notFound
                reason = "Account not found."
            case AccountError.sessionMissing:
                status = .unauthorized
                reason = "Session not found."
            case let abort as any AbortError:
                status = abort.status
                reason = abort.reason
                headers = abort.headers
            default:
                status = .internalServerError
                reason =
                    "Storage is unavailable. No fallback was used; retry or inspect server configuration."
                // Do not log raw database errors: they can include SQL bind parameters.
                request.logger.error(
                    "Reva request failed with a storage/internal error; sensitive details suppressed.")
            }
            response = Response(status: status, headers: headers)
            try response.content.encode(ErrorResponse(error: true, reason: reason))
        }
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        return response
    }
}

// MARK: - Compose listener, middleware, and routes
/// Accounts are active only when a store is supplied and REVA_ACCOUNTS is enabled; otherwise no auth routes exist
/// and session tokens are rejected. Tests lower passwordCost; production keeps bcrypt cost 12.
public func configure(
    _ app: Application, configuration: ServerConfiguration, store: any RevaStore,
    geminiTransport: GeminiHTTPTransport? = nil, accounts: (any AccountStore)? = nil, passwordCost: Int = 12
) {
    app.http.server.configuration.hostname = configuration.hostname
    app.http.server.configuration.port = configuration.port
    app.routes.defaultMaxBodySize = "4mb"
    app.middleware = Middlewares()
    // CORS wraps error mapping so browsers can read error bodies from allowed origins.
    if !configuration.allowedOrigins.isEmpty {
        app.middleware.use(CORSPolicyMiddleware(origins: Set(configuration.allowedOrigins)))
    }
    app.middleware.use(SafeErrors())
    let activeAccounts = configuration.accountsEnabled ? accounts : nil

    // MARK: - Public storage health
    // The health endpoint checks the chosen store without granting access to any owner data.
    app.get("health") { _ async throws -> HealthResponse in
        try await store.health()
        return HealthResponse(status: "ok", storage: configuration.mode, isDemo: configuration.isDemo)
    }

    // MARK: - Authenticated provider and snapshot operations
    let secured = app.grouped(BearerMiddleware(tokens: configuration.tokens, accounts: activeAccounts))
        .grouped("v1")
    if let activeAccounts {
        registerAccountRoutes(
            app, secured: secured, configuration: configuration, accounts: activeAccounts,
            hasher: PasswordHasher(cost: passwordCost, threadPool: app.threadPool))
    }
    registerProviderRoutes(
        secured, configuration: configuration.providers,
        geminiTransport: geminiTransport ?? .live)
    secured.get("state") { request async throws -> StateEnvelope in
        try await store.getState(owner: request.auth.require(OwnerIdentity.self).id)
    }
    secured.on(.PUT, "state", body: .collect(maxSize: "4mb")) { request async throws -> RevisionResponse in
        guard let contentType = request.headers.contentType,
            contentType.type.lowercased() == "application", contentType.subType.lowercased() == "json"
        else {
            throw Abort(.unsupportedMediaType, reason: "State requires application/json.")
        }
        guard (request.body.data?.readableBytes ?? 0) <= Validation.maxSnapshotBytes else {
            throw Abort(.payloadTooLarge)
        }
        let write: StateWrite
        do { write = try request.content.decode(StateWrite.self) } catch {
            throw Abort(.badRequest, reason: "Expected JSON with integer baseRevision and object snapshot.")
        }
        guard write.baseRevision >= 0 else {
            throw Abort(.badRequest, reason: "baseRevision cannot be negative.")
        }
        try Validation.snapshot(write.snapshot)
        return try await RevisionResponse(
            revision: store.putState(
                owner: request.auth.require(OwnerIdentity.self).id, baseRevision: write.baseRevision,
                snapshot: write.snapshot))
    }
    secured.delete("state") { request async throws -> RevisionResponse in
        try await RevisionResponse(
            revision: store.deleteState(owner: request.auth.require(OwnerIdentity.self).id))
    }
    // MARK: - Owner-scoped original file transfer
    // An attachment upload and a later snapshot PUT are separate commits.
    secured.on(.PUT, "attachments", ":id", body: .collect(maxSize: "16mb")) {
        request async throws -> HTTPStatus in
        let id = try attachmentID(request)
        guard let filename = request.headers.first(name: "X-Filename"),
            let rawType = request.headers.first(name: .contentType),
            let bytes = request.body.data
        else { throw Abort(.badRequest, reason: "Provide body bytes, Content-Type and X-Filename.") }
        let type = rawType.split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        let attachment = StoredAttachment(
            id: id, filename: filename, contentType: type, data: Data(bytes.readableBytesView),
            updatedAt: Date())
        try Validation.attachment(attachment)
        try await store.putAttachment(
            owner: request.auth.require(OwnerIdentity.self).id, attachment: attachment)
        return .noContent
    }
    secured.get("attachments", ":id") { request async throws -> Response in
        let attachment = try await store.getAttachment(
            owner: request.auth.require(OwnerIdentity.self).id, id: attachmentID(request))
        return Response(
            status: .ok,
            headers: [
                "Content-Type": attachment.contentType,
                "X-Filename": attachment.filename,
                "Content-Disposition": "attachment; filename=\"\(attachment.filename)\"",
            ], body: .init(data: attachment.data))
    }
    secured.delete("attachments", ":id") { request async throws -> HTTPStatus in
        try await store.deleteAttachment(
            owner: request.auth.require(OwnerIdentity.self).id, id: attachmentID(request))
        return .noContent
    }
}

// MARK: - Validate route identifiers before storage access
private func attachmentID(_ request: Request) throws -> String {
    guard let id = request.parameters.get("id"), Validation.safeID(id) else {
        throw Abort(.badRequest, reason: "Invalid attachment ID.")
    }
    return id
}
