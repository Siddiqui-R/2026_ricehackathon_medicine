// Purpose: Save, revise and remove record sources through the shared mutation boundary.
// Inputs: New or edited MedicalRecords, or a record ID to remove.
// Outputs: Persisted records with source versions and consistent visit pins.
// Side effects: Writes the snapshot; deletion removes active references but keeps original files.

import Foundation

// MARK: - Record mutation boundary
// Use source-aware version increments so report signatures detect substantive edits.

extension AppStore {
    func save(_ record: MedicalRecord) throws {
        try mutate { data in
            guard let i = data.records.firstIndex(where: { $0.id == record.id }) else {
                data.records.append(record)
                return
            }
            data.records[i] = Self.versioned(record, replacing: data.records[i])
        }
    }
    // MARK: - Field-targeted record editing
    // Merge only changed form fields into the latest record; provider results and provenance stay authoritative.
    func saveRecordEdits(original: MedicalRecord, draft: MedicalRecord, reviewed: Bool) throws {
        guard original.id == draft.id else { throw RevaError.invalid("The record identity changed.") }
        try mutate { data in
            guard let i = data.records.firstIndex(where: { $0.id == original.id }) else {
                throw RevaError.invalid("This record is no longer available. Close this editor.")
            }
            let current = data.records[i]
            var revised = current
            let fields: [WritableKeyPath<MedicalRecord, String>] = [
                \.title, \.provider, \.date, \.kind, \.text, \.notes,
            ]
            for field in fields where draft[keyPath: field] != original[keyPath: field] {
                guard
                    current[keyPath: field] == original[keyPath: field]
                        || current[keyPath: field] == draft[keyPath: field]
                else {
                    throw RevaError.invalid(
                        "A field you edited changed while this editor was open. Your saved data was kept. Reopen the record and apply your edit to the latest version."
                    )
                }
                revised[keyPath: field] = draft[keyPath: field]
            }
            guard !revised.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RevaError.invalid("Enter a record title.")
            }
            let textPresent = !revised.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if revised.text != current.text {
                revised.summary = ReportEngine.localExcerpt(revised.text)
                revised.summaryModel = nil
                revised.pageTexts = nil
                revised.status = reviewed && textPresent ? "ready" : "needsReview"
            } else if reviewed, textPresent {
                guard current.text == draft.text else {
                    throw RevaError.invalid(
                        "The source text changed. Reopen the record before marking it reviewed.")
                }
                revised.status = "ready"
            }
            data.records[i] = Self.versioned(revised, replacing: current)
        }
    }
    // MARK: - Source version reconciliation
    // Changes a brief can quote or select on advance its source version; notes-only edits preserve it.
    private static func versioned(_ record: MedicalRecord, replacing current: MedicalRecord) -> MedicalRecord
    {
        var revised = record
        let affectsBriefs =
            revised.title != current.title || revised.date != current.date || revised.text != current.text
            || revised.kind != current.kind || revised.provider != current.provider
            || revised.tags != current.tags || revised.summary != current.summary
            || revised.status != current.status
        revised.version = affectsBriefs ? current.version + 1 : current.version
        return revised
    }
    // MARK: - Active record deletion
    // Remove record and pin references in one snapshot mutation; leave attachment cleanup separate.
    func deleteRecord(_ id: String) throws {
        try mutate { data in
            data.records.removeAll { $0.id == id }
            for i in data.visits.indices { data.visits[i].pinnedRecordIDs.removeAll { $0 == id } }
        }
    }

}
