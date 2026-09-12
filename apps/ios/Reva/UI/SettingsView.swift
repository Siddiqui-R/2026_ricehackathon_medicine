import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "System"
    @State private var reset = false
    @State private var confirmPull = false
    @State private var confirmOverwrite = false
    @State private var serverURL = "http://127.0.0.1:8080"
    @State private var token = "reva-local-demo-token"
    var body: some View {
        Form {
            if let profile = store.snapshot?.profile {
                Section { HStack(spacing: 16) { Text(profile.initials).font(.title2.bold()).frame(width: 60, height: 60).foregroundStyle(RevaTheme.accent).background(RevaTheme.soft, in: Circle()); VStack(alignment: .leading, spacing: 5) { Text(profile.name).font(.headline); Text("Fictional demo profile").font(.caption).foregroundStyle(.secondary) } }; LabeledContent("Date of birth", value: RevaDate.display(profile.dateOfBirth)) }
                Section("Allergies · demo history") { ForEach(profile.allergies, id: \.self) { Text($0) } }
                Section("Medications · demo history") { ForEach(profile.medications, id: \.self) { Text($0) } }
            }
            Section("Appearance") { Picker("Theme", selection: $appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } } }
            Section("Connections") {
                LabeledContent("Records", value: "Manual upload")
                LabeledContent("Summaries", value: "Local excerpts")
                LabeledContent("Clinic calling", value: "Simulation")
                LabeledContent("Transcription", value: "Not configured")
                LabeledContent("Tiger PostgreSQL", value: "Prepared, not connected")
                Text("No live APIs are activated. Sources and changes are saved in this app’s device storage.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { DisclosureGroup("Developer server connection") {
                Text("Explicit snapshot transfer for fictional demo data. Local storage remains active. Pull replaces your local snapshot after all files download successfully.").font(.footnote).foregroundStyle(.secondary)
                TextField("Server URL", text: $serverURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Demo token", text: $token).textInputAutocapitalization(.never)
                Text(store.serverStatus).font(.subheadline)
                Text("Known revision: \(store.serverRevision)").font(.caption).foregroundStyle(.secondary)
                Button("Check connection") { Task { await store.sync(url: serverURL, token: token, action: "probe") } }
                Button("Push local snapshot") { Task { await store.sync(url: serverURL, token: token, action: "push") } }
                Button("Pull server snapshot") { confirmPull = true }
                if let revision = store.serverConflictRevision {
                    Text("Server revision \(revision) differs from this device.").font(.caption).foregroundStyle(.secondary)
                    Button("Replace server with local snapshot") { confirmOverwrite = true }
                }
                if store.isSyncing { ProgressView("Connecting…") }
            }.disabled(store.isSyncing) }
            Section { Button("Restore fictional demo", role: .destructive) { reset = true } } footer: { Text("Restores the original sample profile, records, and visits. Local changes disappear from the active demo; source files remain in app storage until the app is removed.") }
            Section { Text("Reva · revamed.health").font(.headline); Text("Making every appointment count.").foregroundStyle(.secondary); Text("Hackathon prototype · 0.1.0").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Profile & settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Restore the fictional demo and replace your local changes?", isPresented: $reset, titleVisibility: .visible) { Button("Restore demo", role: .destructive) { store.perform { try store.resetDemo() } } }
            .confirmationDialog("Replace local data with the server snapshot? Unsynced local changes will leave the active view.", isPresented: $confirmPull, titleVisibility: .visible) { Button("Pull server snapshot") { Task { await store.sync(url: serverURL, token: token, action: "pull") } } }
            .confirmationDialog("Replace the server snapshot with this device’s local copy? This is an explicit overwrite of the reviewed server revision.", isPresented: $confirmOverwrite, titleVisibility: .visible) { Button("Replace server snapshot", role: .destructive) { if let revision = store.serverConflictRevision { store.serverRevision = revision; Task { await store.sync(url: serverURL, token: token, action: "push") } } } }
    }
}
