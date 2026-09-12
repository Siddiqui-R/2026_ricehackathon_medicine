// Purpose: Capture or revise a symptom observation with optional supporting details.
// Inputs: An optional symptom MedicalRecord plus AppStore.
// Outputs: A validated User symptom entry saved in Records.
// Side effects: Persists through AppStore, optionally requests AI summarization, and confirms discarded edits.

import SwiftUI

// MARK: - SymptomEntryEditorView
/// Capture or revise a symptom observation with optional supporting details.
struct SymptomEntryEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let original: MedicalRecord?
    @State private var entry: SymptomEntry
    @State private var extraDetails = false
    @State private var saveError: String?
    @State private var confirmDiscard = false
    @FocusState private var symptomFocused: Bool
    private let initialEntry: SymptomEntry

    // MARK: - Draft initialization
    init(record: MedicalRecord? = nil) {
        let entry = record?.symptomEntry ?? SymptomEntry()
        original = record?.symptomEntry == nil ? nil : record
        initialEntry = entry
        _entry = State(initialValue: entry)
        _extraDetails = State(
            initialValue: !entry.duration.isEmpty || !entry.triggers.isEmpty || !entry.whatHelped.isEmpty)
    }

    // MARK: - Derived display and validation
    private var hasChanges: Bool { entry != initialEntry }
    private var validSymptom: Bool {
        let text = entry.symptom.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= 120 && !text.contains(where: \.isNewline)
    }
    private var observedDate: Binding<Date> {
        Binding(get: { RevaDate.parse(entry.observedAt) }, set: { entry.observedAt = RevaDate.iso($0) })
    }

    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section {
                TextField("For example, nausea or a headache", text: $entry.symptom)
                    .focused($symptomFocused).submitLabel(.done)
                    .accessibilityLabel("Symptom")
                DatePicker(
                    "When did it happen?", selection: observedDate, in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .environment(\.timeZone, TimeZone(identifier: entry.timeZone) ?? RevaDate.defaultTimeZone)
            } header: {
                Text("What did you notice?")
            } footer: {
                Text("Save a quick observation in your own words. Time zone: \(entry.timeZone).")
            }
            Section {
                Picker(
                    "Severity",
                    selection: Binding(
                        get: { entry.severity ?? "" }, set: { entry.severity = $0.isEmpty ? nil : $0 })
                ) {
                    Text("Not specified").tag("")
                    ForEach(SymptomEntry.severities, id: \.self) { Text($0.capitalized).tag($0) }
                }
                TextField(
                    "Where you felt it, what happened, or anything you want to remember",
                    text: $entry.details, axis: .vertical
                )
                .lineLimit(4...10).accessibilityLabel("Details, optional")
            } header: {
                Text("Details · optional")
            }
            Section {
                DisclosureGroup("A little more detail", isExpanded: $extraDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How long did it last?").font(.subheadline)
                        TextField(
                            "For example, 20 minutes or still happening", text: $entry.duration,
                            axis: .vertical
                        )
                        .lineLimit(1...4).accessibilityLabel("Duration, optional")
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Possible triggers").font(.subheadline)
                        TextField(
                            "Anything you noticed before it started", text: $entry.triggers, axis: .vertical
                        )
                        .lineLimit(2...5).accessibilityLabel("Possible triggers, optional")
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What helped?").font(.subheadline)
                        TextField("What you tried and how it felt", text: $entry.whatHelped, axis: .vertical)
                            .lineLimit(2...5).accessibilityLabel("What helped, optional")
                    }.padding(.vertical, 4)
                }
            } footer: {
                Text(
                    "Saved as a User symptom entry in Records. Relevant observations can be included when preparing for a visit."
                )
            }
            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.circle").font(.subheadline)
                        .foregroundStyle(RevaTheme.accent)
                }
            }
        }
        .navigationTitle(original == nil ? "Log symptoms" : "Edit symptom entry")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!validSymptom) }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "Discard your unsaved symptom entry changes?", isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: - Save the observation
    /// Persist validated text first; AI summarization is optional and never replaces the entry source.
    private func save() {
        do {
            let saved = try store.saveSymptomEntry(entry, existingRecord: original)
            if store.useConnectedAI { Task { await store.summarizeWithAI(saved.id) } }
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
