import SwiftUI

struct MedicalProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing = false
    @State private var settings = false

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
                                if profile.isDemo { Text("Fictional demo profile").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        LabeledContent("Date of birth", value: profile.dateOfBirth.isEmpty ? "Not provided" : RevaDate.display(profile.dateOfBirth))
                            .font(.subheadline)
                        Button { editing = true } label: { Label("Edit medical profile", systemImage: "pencil") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    MedicalProfileListCard(title: "Allergies", symbol: "allergens", items: profile.allergies)
                    MedicalProfileListCard(title: "Medications", symbol: "pills", items: profile.medications)
                    MedicalProfileListCard(title: "Conditions", symbol: "heart.text.clipboard", items: profile.conditions)
                    MedicalProfileListCard(title: "Surgeries & implants", symbol: "cross.case", items: profile.surgeriesAndImplants ?? [])
                    RevaCard {
                        Label("Care notes", systemImage: "note.text").font(.headline).foregroundStyle(RevaTheme.accent)
                        Text(profile.careNotes?.isEmpty == false ? profile.careNotes! : "Not provided")
                            .font(.subheadline).foregroundStyle(profile.careNotes?.isEmpty == false ? .primary : .secondary)
                            .textSelection(.enabled)
                    }
                    Text("Keep this profile up to date with the details you want handy at every appointment.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .sheet(isPresented: $editing) { NavigationStack { MedicalProfileEditor(profile: profile) } }
            } else {
                ContentUnavailableView("Profile unavailable", systemImage: "person.crop.rectangle", description: Text("Open Settings to restore the fictional demo."))
            }
        }
        .navigationTitle("Medical profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    }
}

private struct MedicalProfileListCard: View {
    let title: String
    let symbol: String
    let items: [String]

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

private struct MedicalProfileEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let profile: PatientProfile
    @State private var name: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var allergies: String
    @State private var medications: String
    @State private var conditions: String
    @State private var surgeries: String
    @State private var notes: String

    init(profile: PatientProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _hasBirthDate = State(initialValue: !profile.dateOfBirth.isEmpty)
        _birthDate = State(initialValue: profile.dateOfBirth.isEmpty ? Date() : RevaDate.parse(profile.dateOfBirth))
        _allergies = State(initialValue: profile.allergies.joined(separator: "\n"))
        _medications = State(initialValue: profile.medications.joined(separator: "\n"))
        _conditions = State(initialValue: profile.conditions.joined(separator: "\n"))
        _surgeries = State(initialValue: (profile.surgeriesAndImplants ?? []).joined(separator: "\n"))
        _notes = State(initialValue: profile.careNotes ?? "")
    }

    var body: some View {
        RevaForm {
            Section("About you") {
                TextField("Name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                Toggle("Include date of birth", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                }
            }
            Section {
                TextField("Allergen and reaction", text: $allergies, axis: .vertical).lineLimit(2...8)
            } header: { Text("Allergies") } footer: {
                Text("One per line. Include reactions if known. A blank field means not provided; write “No known allergies” only if that is accurate.")
            }
            Section {
                TextField("Medication, dose, and frequency", text: $medications, axis: .vertical).lineLimit(2...8)
            } header: { Text("Medications") } footer: {
                Text("One per line, including any supplements you want to remember.")
            }
            Section {
                TextField("Condition and helpful details", text: $conditions, axis: .vertical).lineLimit(2...8)
            } header: { Text("Conditions") } footer: { Text("One condition per line.") }
            Section {
                TextField("Procedure or implant, location, and date", text: $surgeries, axis: .vertical).lineLimit(2...8)
            } header: { Text("Surgeries & implants") } footer: { Text("One per line. Add details such as the year, implant type, or side of the body.") }
            Section {
                TextField("Anything helpful to remember across appointments", text: $notes, axis: .vertical).lineLimit(3...10)
            } header: { Text("Care notes") } footer: { Text("For example, care preferences, accessibility needs, or relevant family history. Empty fields appear as “Not provided.”") }
        }
        .navigationTitle("Edit medical profile").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }

    private func save() {
        var edited = profile
        edited.name = name
        edited.dateOfBirth = hasBirthDate ? RevaDate.day(birthDate) : ""
        edited.allergies = allergies.components(separatedBy: .newlines)
        edited.medications = medications.components(separatedBy: .newlines)
        edited.conditions = conditions.components(separatedBy: .newlines)
        edited.surgeriesAndImplants = surgeries.components(separatedBy: .newlines)
        edited.careNotes = notes
        if store.perform({ try store.saveMedicalProfile(edited) }) { dismiss() }
    }
}
