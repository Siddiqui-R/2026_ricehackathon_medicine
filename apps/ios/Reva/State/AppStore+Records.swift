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
            let current = data.records[i]
            var revised = record
            // Only changes a brief can quote or select on advance the source version; notes and provider edits keep it.
            let affectsBriefs =
                revised.title != current.title || revised.date != current.date || revised.text != current.text
                || revised.tags != current.tags || revised.summary != current.summary
                || revised.status != current.status
            revised.version = affectsBriefs ? current.version + 1 : current.version
            data.records[i] = revised
        }
    }
    // MARK: - Reviewed editor merge
    // Apply only edited fields to the latest source so a background summary or newer metadata survives.
    func saveRecordEdits(_ draft: MedicalRecord, original: MedicalRecord, reviewed: Bool) throws {
        guard var latest = record(original.id) else {
            throw RevaError.invalid("This record is no longer available.")
        }
        let textChanged = draft.text != original.text
        if textChanged || reviewed {
            guard latest.text == original.text else {
                throw RevaError.invalid(
                    "The source text changed while this editor was open. Reopen the record to review the current text."
                )
            }
        }
        if draft.title != original.title { latest.title = draft.title }
        if draft.provider != original.provider { latest.provider = draft.provider }
        if draft.date != original.date { latest.date = draft.date }
        if draft.notes != original.notes { latest.notes = draft.notes }
        let textPresent = !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if textChanged {
            latest.text = draft.text
            latest.summary = ReportEngine.localExcerpt(draft.text)
            latest.summaryModel = nil
            latest.pageTexts = nil
            latest.status = reviewed && textPresent ? "ready" : "needsReview"
        } else if reviewed, textPresent, latest.status == "needsReview" {
            latest.status = "ready"
        }
        try save(latest)
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
