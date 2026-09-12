// Purpose: Edit visit notes independently from the original transcript and audio.
// Inputs: A VisitRecording draft and AppStore.
// Outputs: The recording with revised separate notes.
// Side effects: Saves the recording through AppStore; does not alter transcript words or audio.

import SwiftUI

// MARK: - RecordingNotesEditor
/// Edit visit notes independently from the original transcript and audio.
struct RecordingNotesEditor: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var recording: VisitRecording
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("Your visit notes") { TextEditor(text: $recording.summary).frame(minHeight: 300) }
            Text("These are your editable notes. They do not change the original transcript or audio.").font(
                .footnote
            ).foregroundStyle(.secondary)
        }.navigationTitle("Visit notes").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if store.perform({
                        try store.saveRecordingNotes(recording.summary, recordingID: recording.id)
                    }) {
                        dismiss()
                    }
                }
            }
        }
    }
}
