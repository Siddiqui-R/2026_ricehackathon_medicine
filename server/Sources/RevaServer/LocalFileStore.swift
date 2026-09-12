// Purpose: Implement owner-scoped snapshots/attachments and the account/session registry as serial local aggregates.
// Inputs: Validated owner IDs, revision-based writes, attachment bytes, account/session records, and a private directory.
// Outputs: Persisted state/revisions/accounts or explicit conflict, missing, quota, corruption, and filesystem errors.
// Side effects: Creates private files, fsyncs replacement contents, atomically renames them, and holds a writer lock.
// Ownership: One actor/process owns a directory. Separate attachment and snapshot requests are separate commits.
// accounts.json holds every user and session row (bcrypt/SHA-256 hashes only) and is rewritten as a whole on each change.

import Foundation
import Vapor

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// MARK: - Serial local-store ownership
/// One process per directory. Actor isolation makes compare-and-swap and atomic writes serial.
public actor LocalFileStore: RevaStore, AccountStore {
    private let directory: URL
    private let directoryLock: DirectoryLock

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        directoryLock = try DirectoryLock(directory: directory)
    }

    public func health() async throws {
        guard FileManager.default.isWritableFile(atPath: directory.path) else { throw StoreError.corrupt }
    }

    // MARK: - Read and replace an owner aggregate
    // Unverifiable data fails closed instead of silently creating a replacement snapshot.
    private func url(_ owner: String) throws -> URL {
        guard Validation.safeID(owner) else { throw StoreError.corrupt }
        return directory.appendingPathComponent(owner + ".json")
    }

    private func read(_ owner: String) throws -> OwnerDocument {
        let file = try url(owner)
        guard FileManager.default.fileExists(atPath: file.path) else { return OwnerDocument() }
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 100 * 1024 * 1024 else { throw StoreError.corrupt }
            let document = try JSONDecoder().decode(OwnerDocument.self, from: Data(contentsOf: file))
            guard document.formatVersion == 1, document.revision >= 0 else { throw StoreError.corrupt }
            return document
        } catch { throw StoreError.corrupt }
    }

    private func write(_ document: OwnerDocument, owner: String) throws {
        try commit(try JSONEncoder().encode(document), to: try url(owner))
    }

    // MARK: - Private temp-file, fsync, rename commit shared by owner documents and accounts.json
    private func commit(_ data: Data, to target: URL) throws {
        let temporary = directory.appendingPathComponent(".pending-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard
            FileManager.default.createFile(
                atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        // Same-directory rename is the single commit point; no fallible work follows it.
        guard rename(temporary.path, target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: - Revision-checked snapshot access and deletion tombstones
    public func getState(owner: String) async throws -> StateEnvelope {
        let document = try read(owner)
        guard let snapshot = document.snapshot else { throw StoreError.missing(document.revision) }
        return StateEnvelope(revision: document.revision, snapshot: snapshot)
    }

    public func putState(owner: String, baseRevision: Int, snapshot: JSONValue) async throws -> Int {
        try Validation.snapshot(snapshot)
        var document = try read(owner)
        guard baseRevision == document.revision else { throw StoreError.conflict(document.revision) }
        guard document.revision < Int.max else { throw StoreError.corrupt }
        document.revision += 1
        document.snapshot = snapshot
        document.record("state.put")
        try write(document, owner: owner)
        return document.revision
    }

    public func deleteState(owner: String) async throws -> Int {
        var document = try read(owner)
        // Repeat delete is idempotent once all owner content is gone.
        guard document.snapshot != nil || !document.attachments.isEmpty else { return document.revision }
        guard document.revision < Int.max else { throw StoreError.corrupt }
        document.revision += 1
        document.snapshot = nil
        document.attachments = [:]
        document.record("state.delete")
        try write(document, owner: owner)
        return document.revision
    }

    // MARK: - Independent attachment operations and aggregate quotas
    public func putAttachment(owner: String, attachment: StoredAttachment) async throws {
        try Validation.attachment(attachment)
        var document = try read(owner)
        let total =
            document.attachments.values.reduce(0) { $0 + $1.data.count }
            - (document.attachments[attachment.id]?.data.count ?? 0) + attachment.data.count
        guard total <= Validation.maxOwnerAttachmentBytes,
            document.attachments[attachment.id] != nil
                || document.attachments.count < Validation.maxAttachmentCount
        else { throw StoreError.quota }
        document.attachments[attachment.id] = attachment
        document.record("attachment.put")
        try write(document, owner: owner)
    }

    public func getAttachment(owner: String, id: String) async throws -> StoredAttachment {
        guard let attachment = try read(owner).attachments[id] else { throw StoreError.attachmentMissing }
        return attachment
    }

    public func deleteAttachment(owner: String, id: String) async throws {
        var document = try read(owner)
        guard document.attachments.removeValue(forKey: id) != nil else { return }
        document.record("attachment.delete")
        try write(document, owner: owner)
    }

    // MARK: - Account registry document with bounds and pruning
    // Unverifiable data fails closed instead of silently starting an empty registry.
    static let maximumUsers = 10_000
    static let maximumSessionRows = 100_000
    static let sessionRetention: TimeInterval = 30 * 24 * 60 * 60

    private var accountsURL: URL { directory.appendingPathComponent("accounts.json") }

    private func readAccounts() throws -> AccountsDocument {
        let file = accountsURL
        guard FileManager.default.fileExists(atPath: file.path) else { return AccountsDocument() }
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 100 * 1024 * 1024 else { throw StoreError.corrupt }
            let document = try JSONDecoder().decode(AccountsDocument.self, from: Data(contentsOf: file))
            guard document.formatVersion == 1 else { throw StoreError.corrupt }
            return document
        } catch { throw StoreError.corrupt }
    }

    /// Prunes revoked/expired sessions older than 30 days, enforces row bounds, then commits atomically.
    private func writeAccounts(_ input: AccountsDocument, now: Date = Date()) throws {
        var document = input
        let cutoff = now.addingTimeInterval(-Self.sessionRetention)
        document.sessions.removeAll { session in
            (session.revokedAt.map { $0 < cutoff } ?? false) || session.expiresAt < cutoff
        }
        guard document.users.count <= Self.maximumUsers else {
            throw Abort(.serviceUnavailable, reason: "This server cannot accept more accounts.")
        }
        guard document.sessions.count <= Self.maximumSessionRows else {
            throw Abort(.serviceUnavailable, reason: "This server cannot store more sessions.")
        }
        try commit(try JSONEncoder().encode(document), to: accountsURL)
    }

    // MARK: - Users
    public func createUser(_ user: UserRecord) async throws {
        guard Validation.safeID(user.id) else { throw StoreError.corrupt }
        var document = try readAccounts()
        let email = user.email.lowercased()
        guard !document.users.contains(where: { $0.email.lowercased() == email || $0.id == user.id }) else {
            throw AccountError.emailTaken
        }
        document.users.append(user)
        try writeAccounts(document)
    }

    public func user(email: String) async throws -> UserRecord? {
        let normalized = email.lowercased()
        return try readAccounts().users.first { $0.email.lowercased() == normalized }
    }

    public func user(id: String) async throws -> UserRecord? {
        try readAccounts().users.first { $0.id == id }
    }

    public func updatePassword(userID: String, hash: String, at date: Date) async throws {
        var document = try readAccounts()
        guard let index = document.users.firstIndex(where: { $0.id == userID }) else {
            throw AccountError.userMissing
        }
        document.users[index] = document.users[index].replacingPassword(hash: hash, at: date)
        try writeAccounts(document)
    }

    /// Owner data is removed first so a failure after that point still leaves no orphaned snapshot behind.
    public func deleteUser(id: String) async throws {
        var document = try readAccounts()
        guard document.users.contains(where: { $0.id == id }) else { throw AccountError.userMissing }
        let owner = try url(id)
        if FileManager.default.fileExists(atPath: owner.path) {
            try FileManager.default.removeItem(at: owner)
        }
        document.users.removeAll { $0.id == id }
        document.sessions.removeAll { $0.userID == id }
        try writeAccounts(document)
    }

    // MARK: - Sessions
    /// Creating a 21st live session revokes the oldest live sessions until 20 remain including the new one.
    public func createSession(_ session: SessionRecord) async throws {
        var document = try readAccounts()
        guard document.users.contains(where: { $0.id == session.userID }) else {
            throw AccountError.userMissing
        }
        guard !document.sessions.contains(where: { $0.id == session.id || $0.tokenHash == session.tokenHash })
        else { throw StoreError.corrupt }
        let now = Date()
        var live = document.sessions.indices.filter {
            document.sessions[$0].userID == session.userID && document.sessions[$0].isLive(at: now)
        }
        live.sort { document.sessions[$0].createdAt < document.sessions[$1].createdAt }
        let excess = live.count - (AccountPolicy.maximumLiveSessions - 1)
        if excess > 0, session.isLive(at: now) {
            for index in live.prefix(excess) {
                document.sessions[index] = document.sessions[index].revoked(at: now)
            }
        }
        document.sessions.append(session)
        try writeAccounts(document, now: now)
    }

    public func session(tokenHash: String) async throws -> (SessionRecord, UserRecord)? {
        let document = try readAccounts()
        guard let session = document.sessions.first(where: { $0.tokenHash == tokenHash }),
            session.isLive(at: Date()), let user = document.users.first(where: { $0.id == session.userID })
        else { return nil }
        return (session, user)
    }

    public func touchSession(id: UUID, at date: Date) async throws {
        var document = try readAccounts()
        guard let index = document.sessions.firstIndex(where: { $0.id == id }) else {
            throw AccountError.sessionMissing
        }
        document.sessions[index] = document.sessions[index].touched(at: date)
        try writeAccounts(document)
    }

    public func revokeSession(id: UUID) async throws {
        var document = try readAccounts()
        guard let index = document.sessions.firstIndex(where: { $0.id == id }) else {
            throw AccountError.sessionMissing
        }
        guard document.sessions[index].revokedAt == nil else { return }
        document.sessions[index] = document.sessions[index].revoked(at: Date())
        try writeAccounts(document)
    }

    public func revokeSessions(userID: String, except: UUID?) async throws {
        var document = try readAccounts()
        let now = Date()
        var changed = false
        for index in document.sessions.indices
        where document.sessions[index].userID == userID && document.sessions[index].revokedAt == nil
            && document.sessions[index].id != except
        {
            document.sessions[index] = document.sessions[index].revoked(at: now)
            changed = true
        }
        guard changed else { return }
        try writeAccounts(document, now: now)
    }
}

// MARK: - Persisted account registry envelope
struct AccountsDocument: Codable, Sendable {
    var formatVersion = 1
    var users: [UserRecord] = []
    var sessions: [SessionRecord] = []
}

// MARK: - Cross-process writer exclusion
/// Protect the aggregate's revision check/commit from another server process using this directory.
private final class DirectoryLock: @unchecked Sendable {
    private let descriptor: Int32
    init(directory: URL) throws {
        let descriptor = open(directory.appendingPathComponent(".writer-lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw ConfigurationError("Cannot open local storage writer lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw ConfigurationError(
                "Local data directory is already in use by another store. Use one server process per directory."
            )
        }
        self.descriptor = descriptor
    }
    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
