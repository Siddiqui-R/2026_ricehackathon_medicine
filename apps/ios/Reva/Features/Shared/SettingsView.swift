// Purpose: Configure connected services, explicit snapshot transfer, and demo recovery.
// Inputs: AppStore connection fields, provider status, and user confirmations.
// Outputs: Service availability, connection state, and configuration controls.
// Side effects: Can call provider discovery/sync, toggle AI use, or restore the fictional demo through AppStore.

import SwiftUI

// MARK: - SettingsView
/// Configure connected services, explicit snapshot transfer, and demo recovery.
struct SettingsView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var reset = false
    @State private var confirmPull = false
    @State private var confirmOverwrite = false
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("Connected services") {
                TextField("Server URL", text: $store.connectionURL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().keyboardType(.URL)
                SecureField("Server access token", text: $store.connectionToken).textInputAutocapitalization(
                    .never
                ).autocorrectionDisabled()
                Button("Check available services") { Task { await store.checkProviders() } }.disabled(
                    store.isProviderBusy)
                LabeledContent(
                    "Gemini",
                    value: store.providerStatus?.gemini.configured == true
                        ? store.providerStatus!.gemini.model : "Not configured")
                LabeledContent(
                    "Transcription",
                    value: store.providerStatus?.transcription.configured == true
                        ? store.providerStatus!.transcription.model : "Not configured")
                LabeledContent(
                    "Clinic calling",
                    value: store.providerStatus?.booking.configured == true
                        && store.providerStatus?.liveCallsEnabled == true
                        ? "Available · review before calling" : "Simulation available")
                Toggle("Use connected AI for records & briefs", isOn: $store.useConnectedAI).disabled(
                    store.providerStatus?.gemini.configured != true)
                Text(
                    "Enabling AI sends imported text and visit-preparation records to your configured server and Gemini. Transcription sends selected audio to the configured speech service. Real calling always has a separate review step. Provider keys stay on the server; this access token stays in memory for this session."
                ).font(.footnote).foregroundStyle(.secondary)
                if store.isProviderBusy { ProgressView("Working with connected service…") }
            }
            Section {
                DisclosureGroup("Developer server connection") {
                    Text(
                        "Explicit snapshot transfer for fictional demo data. Local storage remains active. Pull replaces your local snapshot after all files download successfully."
                    ).font(.footnote).foregroundStyle(.secondary)
                    Text(store.serverStatus).font(.subheadline)
                    Text("Known revision: \(store.serverRevision)").font(.caption).foregroundStyle(.secondary)
                    Button("Check connection") {
                        Task {
                            await store.sync(
                                url: store.connectionURL, token: store.connectionToken, action: "probe")
                        }
                    }
                    Button("Push local snapshot") {
                        Task {
                            await store.sync(
                                url: store.connectionURL, token: store.connectionToken, action: "push")
                        }
                    }
                    Button("Pull server snapshot") { confirmPull = true }
                    if let revision = store.serverConflictRevision {
                        Text("Server revision \(revision) differs from this device.").font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Replace server with local snapshot") { confirmOverwrite = true }
                    }
                    if store.isSyncing { ProgressView("Connecting…") }
                }.disabled(store.isSyncing)
            }
            Section {
                Button("Restore fictional demo", role: .destructive) { reset = true }
            } footer: {
                Text(
                    "Restores the original sample profile, records, and visits. Local changes disappear from the active demo; source files remain in app storage until the app is removed."
                )
            }
            Section {
                Text("Reva · revamed.health").font(.headline)
                Text("Making every appointment count.").foregroundStyle(.secondary)
                Text("Hackathon prototype · 0.1.0").font(.caption).foregroundStyle(.secondary)
            }
        }.onChange(of: store.connectionURL) { _, _ in
            store.providerStatus = nil
            store.useConnectedAI = false
        }
        .onChange(of: store.connectionToken) { _, _ in
            store.providerStatus = nil
            store.useConnectedAI = false
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .confirmationDialog(
            "Restore the fictional demo and replace your local changes?", isPresented: $reset,
            titleVisibility: .visible
        ) { Button("Restore demo", role: .destructive) { store.perform { try store.resetDemo() } } }
        .confirmationDialog(
            "Replace local data with the server snapshot? Unsynced local changes will leave the active view.",
            isPresented: $confirmPull, titleVisibility: .visible
        ) {
            Button("Pull server snapshot") {
                Task {
                    await store.sync(url: store.connectionURL, token: store.connectionToken, action: "pull")
                }
            }
        }
        .confirmationDialog(
            "Replace the server snapshot with this device’s local copy? This is an explicit overwrite of the reviewed server revision.",
            isPresented: $confirmOverwrite, titleVisibility: .visible
        ) {
            Button("Replace server snapshot", role: .destructive) {
                if let revision = store.serverConflictRevision {
                    store.serverRevision = revision
                    Task {
                        await store.sync(
                            url: store.connectionURL, token: store.connectionToken, action: "push")
                    }
                }
            }
        }
    }
}
