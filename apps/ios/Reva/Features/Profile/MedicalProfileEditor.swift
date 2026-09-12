// Purpose: Edit persistent medical essentials without inventing meaning for blank fields.
// Inputs: The original PatientProfile and AppStore.
// Outputs: A profile draft with name, optional birth date, medical lists, and care notes.
// Side effects: Saves through AppStore; blank medical fields remain unspecified.

import SwiftUI

// MARK: - MedicalProfileEditor
/// Edit persistent medical essentials without inventing meaning for blank fields.
struct MedicalProfileEditor: View {
    // MARK: - Inputs and view state

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

    // MARK: - Draft initialization
    init(profile: PatientProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _hasBirthDate = State(initialValue: !profile.dateOfBirth.isEmpty)
        _birthDate = State(
            initialValue: profile.dateOfBirth.isEmpty ? Date() : RevaDate.parse(profile.dateOfBirth))
        _allergies = State(initialValue: profile.allergies.joined(separator: "\n"))
        _medications = State(initialValue: profile.medications.joined(separator: "\n"))
        _conditions = State(initialValue: profile.conditions.joined(separator: "\n"))
        _surgeries = State(initialValue: (profile.surgeriesAndImplants ?? []).joined(separator: "\n"))
        _notes = State(initialValue: profile.careNotes ?? "")
    }

    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("About you") {
                TextField("Name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                Toggle("Include date of birth", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker(
                        "Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date
                    )
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                }
            }
            Section {
                TextField("Allergen and reaction", text: $allergies, axis: .vertical).lineLimit(2...8)
            } header: {
                Text("Allergies")
            } footer: {
                Text(
                    "One per line. Include reactions if known. A blank field means not provided; write “No known allergies” only if that is accurate."
                )
            }
            Section {
                TextField("Medication, dose, and frequency", text: $medications, axis: .vertical).lineLimit(
                    2...8)
            } header: {
                Text("Medications")
            } footer: {
                Text("One per line, including any supplements you want to remember.")
            }
            Section {
                TextField("Condition and helpful details", text: $conditions, axis: .vertical).lineLimit(
                    2...8)
            } header: {
                Text("Conditions")
            } footer: {
                Text("One condition per line.")
            }
            Section {
                TextField("Procedure or implant, location, and date", text: $surgeries, axis: .vertical)
                    .lineLimit(2...8)
            } header: {
                Text("Surgeries & implants")
            } footer: {
                Text("One per line. Add details such as the year, implant type, or side of the body.")
            }
            Section {
                TextField("Anything helpful to remember across appointments", text: $notes, axis: .vertical)
                    .lineLimit(3...10)
            } header: {
                Text("Care notes")
            } footer: {
                Text(
                    "For example, care preferences, accessibility needs, or relevant family history. Empty fields appear as “Not provided.”"
                )
            }
        }
        .navigationTitle("Edit medical profile").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Save profile essentials
    /// Pass list lines to AppStore for normalization without replacing blanks with medical claims.
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
