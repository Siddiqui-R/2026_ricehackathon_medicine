import Foundation

extension AppStore {
    /// Saving uses the same durable record mutation and source-version rules as uploaded documents.
    @discardableResult
    func saveSymptomEntry(_ entry: SymptomEntry, existingRecord original: MedicalRecord? = nil) throws -> MedicalRecord {
        let current: MedicalRecord?
        if let original {
            guard let latest = record(original.id) else {
                throw RevaError.invalid("This symptom entry was deleted. Close the editor and create a new entry if needed.")
            }
            guard latest.version == original.version, latest.symptomEntry == original.symptomEntry else {
                throw RevaError.invalid("This entry changed while you were editing. Close and reopen it to see the latest version.")
            }
            current = latest
        } else { current = nil }
        let revised = try entry.makeRecord(existingRecord: current)
        try save(revised)
        guard let saved = record(revised.id) else { throw RevaError.invalid("The symptom entry could not be saved.") }
        notice = current == nil ? "Symptom entry saved to Records." : "Symptom entry updated. Existing visit briefs may need refreshing."
        return saved
    }
}
