// Purpose: Correct transcript words while retaining speaker labels and relative timestamps.
// Inputs: An existing VisitRecording and AppStore.
// Outputs: Validated segment text updates keyed by the original segment IDs.
// Side effects: Saves corrections through AppStore and refreshes any existing record memory.

import SwiftUI

// MARK: - TranscriptTextEditor
/// Correct transcript words while retaining speaker labels and relative timestamps.
struct TranscriptTextEditor: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let recordingID: String
    @State private var segments: [TranscriptSegment]

    // MARK: - Draft initialization
    init(recording: VisitRecording) {
        recordingID = recording.id
        _segments = State(initialValue: recording.segments)
    }

    // MARK: - Derived display and validation
    private var valid: Bool {
        !segments.isEmpty
            && segments.allSatisfy {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 20_000
            }
            && segments.reduce(0, { $0 + $1.text.count }) <= 200_000
    }

    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section {
                Text(
                    "Correct the words in the existing transcript. Speaker labels and recording-relative times stay the same. Your separate visit notes are kept; an already-saved memory refreshes from these corrections."
                ).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach($segments) { $segment in
                Section {
                    TextEditor(text: $segment.text).frame(minHeight: 140)
                        .accessibilityLabel(
                            "Transcript text for \(segment.speaker) at \(RevaDate.duration(segment.start))")
                } header: {
                    Text(
                        segment.speaker + " · " + RevaDate.duration(segment.start) + "–"
                            + RevaDate.duration(segment.end))
                }
            }
            if !valid {
                Text(
                    "Each segment needs text. Keep individual segments below 20,000 characters and the whole transcript below 200,000."
                ).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit transcript").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save corrections") {
                    let texts = Dictionary(
                        segments.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
                    if store.perform({
                        try store.saveMemory(recordingID: recordingID, correctedSegmentTexts: texts)
                    }) {
                        dismiss()
                    }
                }.disabled(!valid)
            }
        }
    }
}
