// Purpose: Perform explicit snapshot and attachment push/pull against the selected server.
// Inputs: Server URL/token and probe, push or pull action.
// Outputs: Revision/status updates, replaced snapshot after a pull, or conflict/error state.
// Side effects: HTTP and disk transfers; attachments and snapshot are separate commits.

// MARK: - Server identity selection
// Changing URL/token resets known revisions so they are never reused across owner identities.
import Foundation

extension AppStore {
    func client(url: String, token: String) throws -> ServerClient {
        guard let base = URL(string: url) else { throw RevaError.invalid("Enter a valid server URL.") }
        let client = try ServerClient(baseURL: base, token: token)
        let identity = url + "|" + token
        if identity != serverIdentity {
            serverRevision = 0
            serverConflictRevision = nil
            serverIdentity = identity
            serverStatus = "Not connected"
        }
        return client
    }
    // MARK: - Explicit transfer orchestration
    // Probe first; transfer files before publishing pulled state and surface revision conflicts for review.
    func sync(url: String, token: String, action: String) async {
        guard !isSyncing else { return }
        guard url == connectionURL, token == connectionToken else { return }
        let connection = connectionGeneration
        let generation = snapshotGeneration
        let localSnapshot = snapshot
        isSyncing = true
        defer { isSyncing = false }
        do {
            let client = try client(url: url, token: token)
            let baseRevision = serverRevision
            let status = try await client.health()
            guard connection == connectionGeneration else { return }
            try Task.checkCancellation()
            serverStatus = status
            if action == "push", let snapshot = localSnapshot {
                // Preserve the old loops' last-write metadata, but transfer each file only once.
                var uploads: [String: String] = [:]
                for record in snapshot.records {
                    if let name = record.sourceFilename {
                        uploads[name] = ServerClient.uploadContentType(record.mimeType)
                    }
                }
                for recording in snapshot.recordings {
                    if let name = recording.audioFilename {
                        uploads[name] = ServerClient.audioContentType(filename: name)
                    }
                }
                for (name, type) in uploads.sorted(by: { $0.key < $1.key }) {
                    guard let url = sourceURL(name) else {
                        throw RevaError.invalid(
                            "An original source or recording is missing. Restore it before pushing.")
                    }
                    try await client.uploadAttachment(
                        id: ServerClient.attachmentID(for: name),
                        filename: ServerClient.attachmentMetadataName(name), data: Data(contentsOf: url),
                        type: type)
                    guard connection == connectionGeneration else { return }
                    try Task.checkCancellation()
                }
                let revision = try await client.push(snapshot, revision: baseRevision)
                guard connection == connectionGeneration else { return }
                serverRevision = revision
                serverConflictRevision = nil
                notice =
                    generation == snapshotGeneration
                    ? "Local snapshot copied to server revision \(serverRevision)."
                    : "Captured snapshot copied to server revision \(serverRevision). Newer local edits still need a push."
            } else if action == "pull" {
                let remote = try await client.pull()
                guard connection == connectionGeneration else { return }
                let names =
                    remote.snapshot.records.compactMap(\.sourceFilename)
                    + remote.snapshot.recordings.compactMap(\.audioFilename)
                // Stage one file at a time, preserving existing filenames and original bytes.
                var staged: [String] = []
                var committed = false
                defer { if !committed { repository.discardPullAttachments(staged) } }
                for name in Set(names).sorted() {
                    let data = try await client.attachment(id: ServerClient.attachmentID(for: name))
                    guard connection == connectionGeneration else { return }
                    try Task.checkCancellation()
                    guard generation == snapshotGeneration else {
                        throw RevaError.invalid(
                            "Local data changed during the pull. Your newer changes were kept; review before pulling again."
                        )
                    }
                    if try repository.stagePullAttachment(
                        data, filename: name, existingOriginal: sourceURL(name))
                    {
                        staged.append(name)
                    }
                }
                try Task.checkCancellation()
                guard generation == snapshotGeneration else {
                    throw RevaError.invalid(
                        "Local data changed during the pull. Your newer changes were kept; review before pulling again."
                    )
                }
                try repository.save(remote.snapshot)
                committed = true
                snapshot = remote.snapshot
                serverRevision = remote.revision
                serverConflictRevision = nil
                notice = "Server revision \(remote.revision) loaded."
            }
        } catch ServerFailure.conflict {
            guard connection == connectionGeneration else { return }
            do {
                let remote = try await client(url: url, token: token).pull()
                guard connection == connectionGeneration else { return }
                serverConflictRevision = remote.revision
            } catch ServerFailure.empty(let revision) {
                guard connection == connectionGeneration else { return }
                serverConflictRevision = revision
            } catch {
                guard connection == connectionGeneration else { return }
                serverConflictRevision = nil
            }
            errorMessage =
                "The server changed. Your local snapshot is intact. Pull the server copy, or explicitly replace it with your local copy in Developer settings."
        } catch ServerFailure.empty(let revision) {
            guard connection == connectionGeneration else { return }
            serverRevision = revision
            errorMessage = ServerFailure.empty(revision).localizedDescription
        } catch {
            guard connection == connectionGeneration else { return }
            errorMessage = error.localizedDescription
            if action == "probe" { serverStatus = "Connection failed" }
        }
    }
}
