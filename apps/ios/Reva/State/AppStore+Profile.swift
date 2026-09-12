// Purpose: Normalize and save persistent quick-reference medical profile fields.
// Inputs: An edited PatientProfile with the active profile ID.
// Outputs: Trimmed fields and initials, or an identity/validation error.
// Side effects: Writes the profile snapshot; does not rewrite medical source documents.

import Foundation

// MARK: - Medical profile save
// Normalize display fields and reject saving into a different active profile.
extension AppStore {
    func saveMedicalProfile(_ profile: PatientProfile) throws {
        var updated = profile
        updated.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else {
            throw RevaError.invalid("Add your name before saving your medical profile.")
        }
        let words = updated.name.split(whereSeparator: \.isWhitespace)
            .filter { $0.first?.isLetter == true && !$0.hasSuffix(")") }
        updated.initials = [words.first, words.count > 1 ? words.last : nil]
            .compactMap { $0?.first.map(String.init) }.joined().uppercased()
        updated.allergies = cleanProfileItems(profile.allergies)
        updated.medications = cleanProfileItems(profile.medications)
        updated.conditions = cleanProfileItems(profile.conditions)
        let procedures = cleanProfileItems(profile.surgeriesAndImplants ?? [])
        updated.surgeriesAndImplants = procedures.isEmpty ? nil : procedures
        let notes = profile.careNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updated.careNotes = notes.isEmpty ? nil : notes
        try mutate { data in
            guard data.profile.id == updated.id else {
                throw RevaError.invalid(
                    "The active profile changed. Open your medical profile and try again.")
            }
            data.profile = updated
        }
    }

    // MARK: - Optional list normalization
    // Keep only supplied nonblank items; an empty list does not assert that a condition is absent.
    private func cleanProfileItems(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
