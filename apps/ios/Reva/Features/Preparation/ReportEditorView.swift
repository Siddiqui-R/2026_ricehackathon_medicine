// Purpose: Edit the personal questions and notes attached to a visit brief.
// Inputs: The visit and its current report plus AppStore.
// Outputs: Updated visit questions and notes mirrored by the store into its report.
// Side effects: Saves through AppStore while retaining the latest visit snapshot.

import SwiftUI

// MARK: - ReportEditorView
/// Edit the personal questions and notes attached to a visit brief.
struct ReportEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    @State private var questions = ""
    @State private var notes = ""
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section {
                TextEditor(text: $questions).frame(minHeight: 220)
            } header: {
                Text("Questions to ask")
            } footer: {
                Text("One question per line. Your edits stay when the brief is regenerated.")
            }
            Section("Your notes") { TextEditor(text: $notes).frame(minHeight: 160) }
        }.navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline).onAppear {
            questions = visit.report?.questions.joined(separator: "\n") ?? ""
            notes = visit.report?.notes ?? ""
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var latest = store.visit(visit.id) ?? visit
                    latest.questions = questions.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    latest.notes = notes
                    if store.perform({ try store.save(latest) }) { dismiss() }
                }
            }
        }
    }
}
