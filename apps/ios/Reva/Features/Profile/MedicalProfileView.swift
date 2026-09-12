// Purpose: Keep persistent medical essentials available in one overview.
// Inputs: The current PatientProfile from AppStore.
// Outputs: Identity, medical lists, care notes, and routes to editing and Settings.
// Side effects: Changes local sheet state; the editor and Settings own their mutations.

import SwiftUI

// MARK: - MedicalProfileView
/// Keep persistent medical essentials available in one overview.
struct MedicalProfileView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @State private var editing = false
    @State private var settings = false

    // MARK: - Rendering and navigation
    var body: some View {
        Group {
            if let profile = store.snapshot?.profile {
                Page {
                    Text("The essentials to remember, in one place.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    RevaCard {
                        HStack(spacing: 16) {
                            Text(profile.initials).font(.title2.bold())
                                .frame(width: 60, height: 60)
                                .foregroundStyle(RevaTheme.accent)
                                .background(RevaTheme.canvas, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.name).font(.title3.bold())
                                if profile.isDemo {
                                    Text("Fictional demo profile").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        LabeledContent(
                            "Date of birth",
                            value: profile.dateOfBirth.isEmpty
                                ? "Not provided" : RevaDate.display(profile.dateOfBirth)
                        )
                        .font(.subheadline)
                        Button {
                            editing = true
                        } label: {
                            Label("Edit medical profile", systemImage: "pencil")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    MedicalProfileListCard(title: "Allergies", symbol: "allergens", items: profile.allergies)
                    MedicalProfileListCard(title: "Medications", symbol: "pills", items: profile.medications)
                    MedicalProfileListCard(
                        title: "Conditions", symbol: "heart.text.clipboard", items: profile.conditions)
                    MedicalProfileListCard(
                        title: "Surgeries & implants", symbol: "cross.case",
                        items: profile.surgeriesAndImplants ?? [])
                    RevaCard {
                        Label("Care notes", systemImage: "note.text").font(.headline).foregroundStyle(
                            RevaTheme.accent)
                        Text(profile.careNotes?.isEmpty == false ? profile.careNotes! : "Not provided")
                            .font(.subheadline).foregroundStyle(
                                profile.careNotes?.isEmpty == false ? .primary : .secondary
                            )
                            .textSelection(.enabled)
                    }
                    Text("Keep this profile up to date with the details you want handy at every appointment.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .sheet(isPresented: $editing) { NavigationStack { MedicalProfileEditor(profile: profile) } }
            } else {
                ContentUnavailableView(
                    "Profile unavailable", systemImage: "person.crop.rectangle",
                    description: Text("Open Settings to restore the fictional demo."))
            }
        }
        .navigationTitle("Medical profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settings = true
                } label: {
                    Image(systemName: "gearshape")
                }.accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    }
}

// MARK: - MedicalProfileListCard
/// Render a medical list and preserve the distinction between missing and negative information.
private struct MedicalProfileListCard: View {
    // MARK: - Inputs and view state

    let title: String
    let symbol: String
    let items: [String]

    // MARK: - Rendering and navigation
    var body: some View {
        RevaCard {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(RevaTheme.accent)
            if items.isEmpty {
                Text("Not provided").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    Text(item).font(.subheadline).textSelection(.enabled)
                }
            }
        }
    }
}
