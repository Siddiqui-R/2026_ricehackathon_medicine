// Native account sync and profile automation share the web API while retaining offline edits.
import Foundation

extension AppStore {
    func stopBackgroundUpdates() {
        backgroundActive = false
        backgroundGeneration = UUID()
        syncDebounce?.cancel()
        profileDebounce?.cancel()
        profileObserved = ""
    }
    func runBackgroundUpdates() async {
        stopBackgroundUpdates()
        guard !needsSignIn else { return }
        backgroundActive = true
        let generation = backgroundGeneration
        while !Task.isCancelled && backgroundActive && backgroundGeneration == generation {
            await synchronizeAccount()
            if Date().timeIntervalSince(lastProviderCheck) > 60 && (account != nil || useConnectedAI) {
                let context = providerContext
                do {
                    let status = try await providerClient().status()
                    guard backgroundActive, generation == backgroundGeneration, context == providerContext
                    else { return }
                    providerStatus = status
                    lastProviderCheck = Date()
                } catch
                { /* Foreground controls and update status expose availability without repeated alerts. */  }
            }
            considerMedicalProfileUpdate()
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
        }
    }
    func scheduleBackgroundChanges() {
        guard backgroundActive else { return }
        if account != nil && !isAccountSyncRunning {
            syncStatus = "Saving…"
            syncDebounce?.cancel()
            syncDebounce = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                await self?.synchronizeAccount()
            }
        }
        considerMedicalProfileUpdate()
    }
    func synchronizeAccount() async {
        guard let account, backgroundActive, !isAccountSyncRunning, snapshot != nil else { return }
        isAccountSyncRunning = true
        isSyncing = true
        let generation = backgroundGeneration
        defer {
            isAccountSyncRunning = false
            isSyncing = false
        }
        do {
            let client = try ServerClient(
                baseURL: NativeAccount.origin, token: account.token, session: NativeAccountTransport.session)
            for _ in 0..<3 {
                try Task.checkCancellation()
                guard backgroundActive, generation == backgroundGeneration else { return }
                let remote: ServerState
                do { remote = try await client.pull() } catch ServerFailure.empty(let revision) {
                    remote = ServerState(
                        revision: revision, snapshot: NativeAccount.emptySnapshot(account.user))
                }
                guard backgroundActive, generation == backgroundGeneration else { return }
                guard remote.snapshot.profile.id == account.user.id else {
                    throw RevaError.invalid("The server returned a different account.")
                }
                // Check immutable originals before publishing a remote snapshot. Never overwrite conflicting bytes.
                let remoteFiles = Set(
                    remote.snapshot.records.compactMap(\.sourceFilename)
                        + remote.snapshot.recordings.compactMap(\.audioFilename))
                let priorFiles = Set(
                    (syncBase?.snapshot.records.compactMap(\.sourceFilename) ?? [])
                        + (syncBase?.snapshot.recordings.compactMap(\.audioFilename) ?? []))
                for filename in remoteFiles where !priorFiles.contains(filename) || sourceURL(filename) == nil
                {
                    let data = try await client.attachment(id: ServerClient.attachmentID(for: filename))
                    guard backgroundActive, generation == backgroundGeneration else { return }
                    _ = try repository.stagePullAttachment(
                        data, filename: filename, existingOriginal: sourceURL(filename))
                }
                guard let local = snapshot else { return }
                let merged = try NativeSnapshotMerge.merge(
                    base: syncBase?.snapshot, local: local, remote: remote.snapshot)
                if merged.snapshot != local { try mutate { $0 = merged.snapshot } }
                if merged.recovered > 0 {
                    notice = "Simultaneous edits were kept as labeled recovery copies in Records."
                }
                let candidate = snapshot!
                if candidate != remote.snapshot {
                    var uploads: [String: String] = [:]
                    for record in candidate.records {
                        if let name = record.sourceFilename, !remoteFiles.contains(name) {
                            uploads[name] = ServerClient.uploadContentType(record.mimeType)
                        }
                    }
                    for recording in candidate.recordings {
                        if let name = recording.audioFilename, !remoteFiles.contains(name) {
                            uploads[name] = ServerClient.audioContentType(filename: name)
                        }
                    }
                    for (name, type) in uploads.sorted(by: { $0.key < $1.key }) {
                        guard let url = sourceURL(name) else {
                            throw RevaError.invalid("An original file is missing. Restore it before syncing.")
                        }
                        try await client.uploadAttachment(
                            id: ServerClient.attachmentID(for: name),
                            filename: ServerClient.attachmentMetadataName(name), data: Data(contentsOf: url),
                            type: type)
                        guard backgroundActive, generation == backgroundGeneration else { return }
                    }
                    do {
                        let revision = try await client.push(candidate, revision: remote.revision)
                        guard backgroundActive, generation == backgroundGeneration else { return }
                        try rememberAccountSync(ServerState(revision: revision, snapshot: candidate))
                    } catch ServerFailure.conflict { continue }
                } else {
                    try rememberAccountSync(remote)
                }
                syncStatus = snapshot == candidate ? "All changes saved" : "Saving newer changes…"
                return
            }
            throw RevaError.invalid("Your records changed on another device. Sync will retry shortly.")
        } catch ServerFailure.response(401) {
            guard generation == backgroundGeneration else { return }
            sessionExpired?()
        } catch {
            guard generation == backgroundGeneration else { return }
            syncStatus = "Saved on this device · sync will retry"
        }
    }
    private func rememberAccountSync(_ state: ServerState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: repository.directory.appendingPathComponent("sync-base.json"), options: .atomic)
        syncBase = state
        serverRevision = state.revision
    }
    func retryMedicalProfile() {
        profileObserved = ""
        profileFailures = 0
        considerMedicalProfileUpdate()
    }
    func considerMedicalProfileUpdate() {
        guard backgroundActive, let snapshot else { return }
        guard providerStatus?.gemini.configured == true, account != nil || useConnectedAI else {
            profileDebounce?.cancel()
            profileObserved = ""
            profileUpdateMessage =
                account == nil
                ? "Connect AI in account settings to update this demo from reports."
                : "Automatic profile updates will resume when AI is available."
            return
        }
        let sources = NativeMedicalProfile.sources(snapshot)
        guard let signature = try? NativeMedicalProfile.signature(sources) else { return }
        if snapshot.profile.aiMedicalHistory?.sourceSignature == signature
            || (sources.isEmpty && snapshot.profile.aiMedicalHistory == nil)
        {
            profileUpdateMessage =
                sources.isEmpty
                ? "Add a report to build your medical profile."
                : "Medical profile is up to date with your reports."
            return
        }
        guard signature != profileObserved else { return }
        profileObserved = signature
        profileFailures = 0
        profileDebounce?.cancel()
        profileUpdateMessage = "Updating your medical profile shortly…"
        let context = providerContext
        let generation = backgroundGeneration
        profileDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1800)) } catch { return }
            guard let self else { return }
            await self.updateMedicalProfile(
                sources, signature: signature, context: context, generation: generation)
        }
    }
    private func updateMedicalProfile(
        _ sources: [NativeProfileSource], signature: String, context: ProviderContext, generation: UUID
    ) async {
        guard !Task.isCancelled, backgroundActive, generation == backgroundGeneration,
            context == providerContext,
            account != nil || useConnectedAI, let snapshot, NativeMedicalProfile.sources(snapshot) == sources
        else { return }
        profileUpdateMessage = "Updating your medical profile from reports…"
        do {
            try NativeMedicalProfile.validateSources(sources)
            let result =
                sources.isEmpty
                ? NativeProfileResult(
                    allergies: [], medications: [], conditions: [], surgeriesAndImplants: [], careNotes: [],
                    model: "No source reports")
                : try await providerClient().medicalProfile(sources)
            try Task.checkCancellation()
            guard backgroundActive, generation == backgroundGeneration, context == providerContext,
                let current = self.snapshot, NativeMedicalProfile.sources(current) == sources
            else { return }
            try mutate {
                $0.profile = NativeMedicalProfile.apply(result, to: $0.profile, signature: signature)
            }
            profileUpdateMessage = "Medical profile is up to date with your reports."
        } catch {
            guard !Task.isCancelled, generation == backgroundGeneration, context == providerContext else {
                return
            }
            profileUpdateMessage =
                "Profile update could not finish. Your saved details are kept. Tap Retry to try again."
            if !(error is RevaError), profileFailures < 3 {
                profileFailures += 1
                do { try await Task.sleep(for: .seconds(15 * (1 << (profileFailures - 1)))) } catch { return }
                await updateMedicalProfile(
                    sources, signature: signature, context: context, generation: generation)
            }
        }
    }
}
