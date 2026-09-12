// Purpose: Implement owner-scoped snapshots and attachments in one serial local aggregate per owner.
// Inputs: Validated owner IDs, revision-based writes, attachment bytes, and a private storage directory.
// Outputs: Persisted state/revisions or explicit conflict, missing, quota, corruption, and filesystem errors.
// Side effects: Creates private files, fsyncs replacement contents, atomically renames them, and holds a writer lock.
// Ownership: One actor/process owns a directory. Separate attachment and snapshot requests are separate commits.

import Foundation
import Vapor

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// MARK: - Serial local-store ownership
/// One process per directory. Actor isolation makes compare-and-swap and atomic writes serial.
public actor LocalFileStore: RevaStore {
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
        let data = try JSONEncoder().encode(document)
        let target = try url(owner)
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
