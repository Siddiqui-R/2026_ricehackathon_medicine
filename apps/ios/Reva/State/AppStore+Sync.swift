// Purpose: Perform explicit snapshot and attachment push/pull against the selected server.
// Inputs: Server URL/token and probe, push or pull action.
// Outputs: Revision/status updates, replaced snapshot after a pull, or conflict/error state.
// Side effects: HTTP and disk transfers; attachments and snapshot are separate commits.

import Foundation

// MARK: - Server identity selection
// Changing URL/token resets known revisions so they are never reused across owner identities.
extension AppStore {
    func client(url: String, token: String) throws -> ServerClient {
        guard let base = URL(string: url) else { throw RevaError.invalid("Enter a valid server URL.") }
        let identity = url + "|" + token
        if identity != serverIdentity {
            serverRevision = 0
            serverConflictRevision = nil
            serverIdentity = identity
            serverStatus = "Not connected"
        }
        return try ServerClient(baseURL: base, token: token)
    }
    // MARK: - Explicit transfer orchestration
    // Probe first; transfer files before publishing pulled state and surface revision conflicts for review.
    func sync(url: String, token: String, action: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let client = try client(url: url, token: token)
            serverStatus = try await client.health()
            if action == "push", let snapshot {
                for record in snapshot.records {
                    if let name = record.sourceFilename {
                        guard let url = sourceURL(name) else {
                            throw RevaError.invalid(
                                "An original source is missing. Restore it before pushing.")
                        }
                        try await client.uploadAttachment(
                            id: ServerClient.attachmentID(for: name),
                            filename: ServerClient.attachmentMetadataName(name), data: Data(contentsOf: url),
                            type: ServerClient.uploadContentType(record.mimeType))
                    }
                }
                for recording in snapshot.recordings {
                    if let name = recording.audioFilename {
                        guard let url = sourceURL(name) else {
                            throw RevaError.invalid("A recording file is missing. Restore it before pushing.")
                        }
                        try await client.uploadAttachment(
                            id: ServerClient.attachmentID(for: name),
                            filename: ServerClient.attachmentMetadataName(name), data: Data(contentsOf: url),
                            type: ServerClient.audioContentType(filename: name))
                    }
                }
                serverRevision = try await client.push(snapshot, revision: serverRevision)
                serverConflictRevision = nil
                notice = "Local snapshot copied to server revision \(serverRevision)."
            } else if action == "pull" {
                let remote = try await client.pull()
                let names =
                    remote.snapshot.records.compactMap(\.sourceFilename)
                    + remote.snapshot.recordings.compactMap(\.audioFilename)
                // Download every attachment before replacing state. A failed transfer leaves local state untouched.
                var bytes: [String: Data] = [:]
                for name in Set(names) {
                    bytes[name] = try await client.attachment(id: ServerClient.attachmentID(for: name))
                }
                for (name, data) in bytes { _ = try repository.storeAttachment(data, filename: name) }
                try repository.save(remote.snapshot)
                snapshot = remote.snapshot
                serverRevision = remote.revision
                serverConflictRevision = nil
                notice = "Server revision \(remote.revision) loaded."
            }
        } catch ServerFailure.conflict {
            do {
                let remote = try await client(url: url, token: token).pull()
                serverConflictRevision = remote.revision
            } catch ServerFailure.empty(let revision) { serverConflictRevision = revision } catch {
                serverConflictRevision = nil
            }
            errorMessage =
                "The server changed. Your local snapshot is intact. Pull the server copy, or explicitly replace it with your local copy in Developer settings."
        } catch ServerFailure.empty(let revision) {
            serverRevision = revision
            errorMessage = ServerFailure.empty(revision).localizedDescription
        } catch {
            errorMessage = error.localizedDescription
            if action == "probe" { serverStatus = "Connection failed" }
        }
    }
}
