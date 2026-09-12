// Purpose: Create or edit an appointment and its preparation preferences.
// Inputs: An optional existing Visit plus AppStore records available for pinning.
// Outputs: A Visit containing appointment details, questions, and pinned record IDs.
// Side effects: Saves the validated appointment through AppStore.

import SwiftUI

// MARK: - VisitEditorView
/// Create or edit an appointment and its preparation preferences.
struct VisitEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var existing: Visit?
    @State private var title = ""
    @State private var type = "Primary care"
    @State private var provider = ""
    @State private var clinic = ""
    @State private var date = Date().addingTimeInterval(86400 * 3)
    @State private var zone = RevaDate.defaultTimeZoneIdentifier
    @State private var concern = ""
    @State private var goal = ""
    @State private var questions = ""
    @State private var pins: Set<String> = []
    // MARK: - Derived display and validation
    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !concern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && TimeZone(identifier: zone) != nil
    }
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section("Appointment") {
                TextField("Visit title", text: $title)
                Picker("Visit type", selection: $type) {
                    ForEach(["Primary care", "Orthopedics", "Cardiology", "Other"], id: \.self) { Text($0) }
                }
                TextField("Provider", text: $provider)
                TextField("Clinic", text: $clinic)
                DatePicker("Date & time", selection: $date).environment(
                    \.timeZone, TimeZone(identifier: zone) ?? RevaDate.defaultTimeZone)
                Picker("Time zone", selection: $zone) {
                    ForEach(
                        [
                            "America/Chicago", "America/New_York", "America/Denver", "America/Los_Angeles",
                            "Europe/London", "UTC",
                        ], id: \.self
                    ) { Text($0) }
                }
            }
            Section("What would you like to discuss?") {
                TextField("Your concern or symptoms", text: $concern, axis: .vertical).lineLimit(3...6)
                TextField("What would make this visit useful?", text: $goal, axis: .vertical).lineLimit(2...5)
            }
            Section {
                TextEditor(text: $questions).frame(minHeight: 100)
            } header: {
                Text("Questions to ask")
            } footer: {
                Text("One question per line. You can also edit the questions in your generated brief.")
            }
            Section {
                ForEach(store.records) { record in
                    Toggle(
                        record.title,
                        isOn: Binding(
                            get: { pins.contains(record.id) },
                            set: { if $0 { pins.insert(record.id) } else { pins.remove(record.id) } }))
                }
            } header: {
                Text("Always include these records")
            } footer: {
                Text("Pinned records are included alongside the relevant history selected for your visit.")
            }
        }.navigationTitle(existing == nil ? "Add visit" : "Edit visit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) }
            }
            .onAppear {
                guard let existing else { return }
                title = existing.title
                type = existing.type
                provider = existing.provider
                clinic = existing.clinic
                date = RevaDate.parse(existing.date)
                zone = existing.timeZone
                concern = existing.concern
                goal = existing.goal
                questions = existing.questions.joined(separator: "\n")
                pins = Set(existing.pinnedRecordIDs)
            }
    }
    // MARK: - Save appointment details
    /// Keep existing identity and report while replacing the fields controlled by this editor.
    private func save() {
        var visit =
            existing
            ?? Visit(
                title: title, type: type, provider: provider, clinic: clinic, date: RevaDate.iso(date),
                concern: concern, goal: goal)
        visit.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.type = type
        visit.provider = provider
        visit.clinic = clinic
        visit.date = RevaDate.iso(date)
        visit.timeZone = zone
        visit.concern = concern
        visit.goal = goal
        visit.questions = questions.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        visit.pinnedRecordIDs = pins.sorted()
        if store.perform({ try store.save(visit) }) { dismiss() }
    }
}
