// Purpose: Review and edit a saved document while preserving source provenance.
// Inputs: The original MedicalRecord and AppStore.
// Outputs: A revised record with explicit review status.
// Side effects: Saves through AppStore; text corrections replace the excerpt and clear page segmentation.

import SwiftUI

// MARK: - RecordEditorView
/// Review and edit a saved document while preserving source provenance.
struct RecordEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let original: MedicalRecord
    @State private var record: MedicalRecord
    @State private var reviewed = false
    // MARK: - Draft initialization
    init(record: MedicalRecord) {
        original = record
        _record = State(initialValue: record)
    }
    // MARK: - Derived display and validation
    private var textChanged: Bool { record.text != original.text }
    private var textPresent: Bool { !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("Record details") {
                TextField("Title", text: $record.title)
                TextField("Provider", text: $record.provider)
                DatePicker(
                    "Record date",
                    selection: Binding(
                        get: { RevaDate.parse(record.date) }, set: { record.date = RevaDate.day($0) }),
                    displayedComponents: .date
                ).environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
            }
            Section {
                TextEditor(text: $record.text).frame(minHeight: 220)
            } header: {
                Text("Extracted text")
            } footer: {
                Text(
                    "Keep the original wording, values, and units. Changing text refreshes the local excerpt and marks existing briefs out of date. Check source details again after a correction. Title, date, and notes edits keep the summary."
                )
            }
            Section("Your notes") { TextEditor(text: $record.notes).frame(minHeight: 100) }
            Section { Toggle("I checked the text against the source", isOn: $reviewed) }
        }.navigationTitle("Edit record").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(
                        record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
    }
    // MARK: - Save reviewed changes
    /// Preserve authored summaries and source pages unless the user changed the extracted text.
    private func save() {
        var revised = record
        // Fictional origin describes the source, not whether the user edited it.
        revised.isDemo = original.isDemo
        if textChanged {
            revised.summary = ReportEngine.localExcerpt(record.text)
            revised.summaryModel = nil
            // A manual whole-document correction no longer claims the original page segmentation.
            revised.pageTexts = nil
            revised.status = reviewed && textPresent ? "ready" : "needsReview"
        } else if reviewed, textPresent, original.status == "needsReview" {
            // Explicit confirmation clears the review state; summary and pages stay; the source version advances.
            revised.status = "ready"
        }
        if store.perform({ try store.save(revised) }) { dismiss() }
    }
}
