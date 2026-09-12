// Purpose: Edit visit notes independently from the original transcript and audio.
// Inputs: A recording ID, separate notes draft and AppStore.
// Outputs: Updated notes on the latest saved recording.
// Side effects: Saves only notes through AppStore; does not alter transcript words or audio.

import SwiftUI

// MARK: - RecordingNotesEditor
/// Edit visit notes independently from the original transcript and audio.

struct RecordingNotesEditor: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let recordingID: String
    @State private var summary: String
    // MARK: - Notes draft initialization
    init(recording: VisitRecording) {
        recordingID = recording.id
        _summary = State(initialValue: recording.summary)
    }
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("Your visit notes") { TextEditor(text: $summary).frame(minHeight: 300) }
            Text("These are your editable notes. They do not change the original transcript or audio.").font(
                .footnote
            ).foregroundStyle(.secondary)
        }.navigationTitle("Visit notes").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if store.perform({ try store.updateRecordingNotes(id: recordingID, summary: summary) }) {
                        dismiss()
                    }
                }
            }
        }
    }
}
