// Purpose: Persist new or revised self-reported symptom records.
// Inputs: A structured observation and optional original record for conflict checks.
// Outputs: The saved record with stable identity and normal source versioning.
// Side effects: Writes the snapshot and publishes a notice; preserves concurrent edits on error.

import Foundation

// MARK: - Symptom create and revise
// Verify the original identity/version before updating; delegate source versions to record save.
extension AppStore {
    /// Saving uses the same durable record mutation and source-version rules as uploaded documents.
    @discardableResult
    func saveSymptomEntry(_ entry: SymptomEntry, existingRecord original: MedicalRecord? = nil) throws
        -> MedicalRecord
    {
        let current: MedicalRecord?
        if let original {
            guard let latest = record(original.id) else {
                throw RevaError.invalid(
                    "This symptom entry was deleted. Close the editor and create a new entry if needed.")
            }
            guard latest.version == original.version, latest.symptomEntry == original.symptomEntry else {
                throw RevaError.invalid(
                    "This entry changed while you were editing. Close and reopen it to see the latest version."
                )
            }
            current = latest
        } else {
            current = nil
        }
        let revised = try entry.makeRecord(existingRecord: current)
        try save(revised)
        guard let saved = record(revised.id) else {
            throw RevaError.invalid("The symptom entry could not be saved.")
        }
        notice =
            current == nil
            ? "Symptom entry saved to Records."
            : "Symptom entry updated. Existing visit briefs may need refreshing."
        return saved
    }
}
