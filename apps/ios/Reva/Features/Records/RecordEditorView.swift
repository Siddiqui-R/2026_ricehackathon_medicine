// Purpose: Review and edit a saved document while preserving source provenance.
// Inputs: The original MedicalRecord and AppStore.
// Outputs: A revised record with preserved source provenance.
// Side effects: Saves through AppStore; text corrections replace the excerpt and clear page segmentation.

import SwiftUI

// MARK: - RecordEditorView
/// Review and edit a saved document while preserving source provenance.
struct RecordEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var original: MedicalRecord
    @State private var record: MedicalRecord
    // MARK: - Draft initialization
    init(record: MedicalRecord) {
        _original = State(initialValue: record)
        _record = State(initialValue: record)
    }
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("Record details") {
                TextField("Title", text: $record.title)
                TextField("Provider", text: $record.provider)
                Picker("Record kind", selection: $record.kind) {
                    ForEach(MedicalRecord.configurableKinds, id: \.self) { Text($0).tag($0) }
                    if !MedicalRecord.configurableKinds.contains(original.kind) {
                        Text(original.kind).tag(original.kind)
                    }
                }
                DatePicker(
                    "Record date",
                    selection: Binding(
                        get: { RevaDate.parse(record.date) }, set: { record.date = RevaDate.day($0) }),
                    displayedComponents: .date
                ).environment(\.timeZone, RevaDate.calendarDayTimeZone)
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
        }.navigationTitle("Edit record").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(
                        record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
    }
    // MARK: - Save record changes
    /// Preserve authored summaries and source pages unless the user changed the extracted text.
    private func save() {
        if store.perform({ try store.saveRecordEdits(record, original: original) }) {
            dismiss()
        }
    }
}
