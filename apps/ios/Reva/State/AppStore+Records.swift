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
            if (current.summaryModel != nil || revised.summaryModel != nil)
                && (revised.title != current.title || revised.text != current.text
                    || revised.date != current.date || revised.dateSource != current.dateSource)
            {
                revised.summary = ReportEngine.localExcerpt(revised.text, isDemo: revised.isDemo)
                revised.summaryModel = nil
                revised.summaryGeneratedAt = nil
            }
            // Only changes a brief can quote or select on advance the source version; notes-only edits keep it.
            let affectsBriefs =
                revised.title != current.title || revised.date != current.date || revised.text != current.text
                || revised.dateSource != current.dateSource
                || revised.kind != current.kind || revised.provider != current.provider
                || revised.tags != current.tags || revised.summary != current.summary
                || revised.status != current.status
            revised.version = affectsBriefs ? current.version + 1 : current.version
            data.records[i] = revised
        }
    }
    // MARK: - Record editor merge
    // Apply only edited fields to the latest source so a background summary or newer metadata survives.
    func saveRecordEdits(_ draft: MedicalRecord, original: MedicalRecord) throws {
        guard original.id == draft.id else { throw RevaError.invalid("The record identity changed.") }
        guard let current = record(original.id) else {
            throw RevaError.invalid("This record is no longer available.")
        }
        var latest = current
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
            latest[keyPath: field] = draft[keyPath: field]
        }
        guard !latest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RevaError.invalid("Enter a record title.")
        }
        if latest.title != current.title || latest.text != current.text || latest.date != current.date
            || latest.dateSource != current.dateSource
        {
            latest.summary = ReportEngine.localExcerpt(latest.text, isDemo: latest.isDemo)
            latest.summaryModel = nil
            latest.summaryGeneratedAt = nil
        }
        if latest.text != current.text {
            latest.pageTexts = nil
        }
        latest.status = "ready"
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
