import Vapor

struct OwnerIdentity: Authenticatable { let id: String }

private struct BearerMiddleware: AsyncMiddleware {
    let tokens: [String: String]

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let supplied = request.headers.bearerAuthorization?.token,
              supplied.utf8.count <= 256,
              let owner = tokens.first(where: { constantTimeEqual($0.key, supplied) })?.value else {
            throw Abort(.unauthorized, headers: ["WWW-Authenticate": "Bearer"], reason: "A valid bearer token is required.")
        }
        request.auth.login(OwnerIdentity(id: owner))
        return try await next.respond(to: request)
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        var difference = left.count ^ right.count
        for index in 0..<max(left.count, right.count) {
            difference |= Int((index < left.count ? left[index] : 0) ^ (index < right.count ? right[index] : 0))
        }
        return difference == 0
    }
}

private struct SafeErrors: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response: Response
        do { response = try await next.respond(to: request) }
        catch {
            let status: HTTPResponseStatus
            let reason: String
            var headers = HTTPHeaders()
            switch error {
            case StoreError.conflict(let revision):
                status = .conflict; reason = "State changed on the server. Fetch and review before retrying."
                headers.replaceOrAdd(name: "X-State-Revision", value: String(revision))
            case StoreError.missing(let revision):
                status = .notFound; reason = "No snapshot exists for this owner."
                headers.replaceOrAdd(name: "X-State-Revision", value: String(revision))
            case StoreError.attachmentMissing:
                status = .notFound; reason = "Attachment not found."
            case StoreError.quota:
                status = .payloadTooLarge; reason = "Owner attachment limit is 64 MiB and 128 files."
            case let abort as any AbortError:
                status = abort.status; reason = abort.reason; headers = abort.headers
            default:
                status = .internalServerError; reason = "Storage is unavailable. No fallback was used; retry or inspect server configuration."
                // Do not log raw database errors: they can include SQL bind parameters.
                request.logger.error("Reva request failed with a storage/internal error; sensitive details suppressed.")
            }
            response = Response(status: status, headers: headers)
            try response.content.encode(ErrorResponse(error: true, reason: reason))
        }
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        return response
    }
}

public func configure(_ app: Application, configuration: ServerConfiguration, store: any RevaStore,
                      geminiTransport: GeminiHTTPTransport? = nil) {
    app.http.server.configuration.hostname = configuration.hostname
    app.http.server.configuration.port = configuration.port
    app.routes.defaultMaxBodySize = "4mb"
    app.middleware = Middlewares()
    app.middleware.use(SafeErrors())

    app.get("health") { _ async throws -> HealthResponse in
        try await store.health()
        return HealthResponse(status: "ok", storage: configuration.mode, isDemo: configuration.isDemo)
    }

    let secured = app.grouped(BearerMiddleware(tokens: configuration.tokens)).grouped("v1")
    registerProviderRoutes(secured, configuration: configuration.providers, directory: configuration.directory,
                           geminiTransport: geminiTransport ?? .live)
    secured.get("state") { request async throws -> StateEnvelope in
        try await store.getState(owner: request.auth.require(OwnerIdentity.self).id)
    }
    secured.on(.PUT, "state", body: .collect(maxSize: "4mb")) { request async throws -> RevisionResponse in
        guard let contentType = request.headers.contentType,
              contentType.type.lowercased() == "application", contentType.subType.lowercased() == "json" else {
            throw Abort(.unsupportedMediaType, reason: "State requires application/json.")
        }
        guard (request.body.data?.readableBytes ?? 0) <= Validation.maxSnapshotBytes else { throw Abort(.payloadTooLarge) }
        let write: StateWrite
        do { write = try request.content.decode(StateWrite.self) }
        catch { throw Abort(.badRequest, reason: "Expected JSON with integer baseRevision and object snapshot.") }
        guard write.baseRevision >= 0 else { throw Abort(.badRequest, reason: "baseRevision cannot be negative.") }
        try Validation.snapshot(write.snapshot)
        return try await RevisionResponse(revision: store.putState(owner: request.auth.require(OwnerIdentity.self).id, baseRevision: write.baseRevision, snapshot: write.snapshot))
    }
    secured.delete("state") { request async throws -> RevisionResponse in
        try await RevisionResponse(revision: store.deleteState(owner: request.auth.require(OwnerIdentity.self).id))
    }
    secured.on(.PUT, "attachments", ":id", body: .collect(maxSize: "16mb")) { request async throws -> HTTPStatus in
        let id = try attachmentID(request)
        guard let filename = request.headers.first(name: "X-Filename"),
              let rawType = request.headers.first(name: .contentType),
              let bytes = request.body.data else { throw Abort(.badRequest, reason: "Provide body bytes, Content-Type and X-Filename.") }
        let type = rawType.split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        let attachment = StoredAttachment(id: id, filename: filename, contentType: type, data: Data(bytes.readableBytesView), updatedAt: Date())
        try Validation.attachment(attachment)
        try await store.putAttachment(owner: request.auth.require(OwnerIdentity.self).id, attachment: attachment)
        return .noContent
    }
    secured.get("attachments", ":id") { request async throws -> Response in
        let attachment = try await store.getAttachment(owner: request.auth.require(OwnerIdentity.self).id, id: attachmentID(request))
        return Response(status: .ok, headers: [
            "Content-Type": attachment.contentType,
            "X-Filename": attachment.filename,
            "Content-Disposition": "attachment; filename=\"\(attachment.filename)\""
        ], body: .init(data: attachment.data))
    }
    secured.delete("attachments", ":id") { request async throws -> HTTPStatus in
        try await store.deleteAttachment(owner: request.auth.require(OwnerIdentity.self).id, id: attachmentID(request))
        return .noContent
    }
}

private func attachmentID(_ request: Request) throws -> String {
    guard let id = request.parameters.get("id"), Validation.safeID(id) else { throw Abort(.badRequest, reason: "Invalid attachment ID.") }
    return id
}
