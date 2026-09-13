// Edit only the selected profile section; protect concurrent updates and unfinished drafts.
import SwiftUI

struct MedicalProfileEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let profile: PatientProfile
    let field: MedicalProfileField?
    @State private var name: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var text: String
    @State private var error: String?
    @State private var discard = false
    init(profile: PatientProfile, field: MedicalProfileField?) {
        self.profile = profile
        self.field = field
        _name = State(initialValue: profile.name)
        _hasBirthDate = State(initialValue: !profile.dateOfBirth.isEmpty)
        _birthDate = State(
            initialValue: RevaDate.parse(profile.dateOfBirth.isEmpty ? RevaDate.today() : profile.dateOfBirth)
        )
        _text = State(initialValue: field?.values(profile).joined(separator: "\n") ?? "")
    }
    private var dirty: Bool {
        if let field { return text != field.values(profile).joined(separator: "\n") }
        return name != profile.name || (hasBirthDate ? RevaDate.day(birthDate) : "") != profile.dateOfBirth
    }
    var body: some View {
        RevaForm {
            if let field {
                Section {
                    TextField(field.title, text: $text, axis: .vertical).lineLimit(5...15)
                } footer: {
                    Text(
                        field == .careNotes
                            ? "Keep details you want handy at an appointment."
                            : "One item per line. Leave blank if not provided.")
                }
            } else {
                Section("Personal details") {
                    TextField("Name", text: $name).textContentType(.name)
                    Toggle("Include date of birth", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker(
                            "Date of birth", selection: $birthDate, in: ...RevaDate.parse(RevaDate.today()),
                            displayedComponents: .date
                        )
                        .environment(\.timeZone, RevaDate.calendarDayTimeZone)
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(RevaTheme.accentText) } }
        }.navigationTitle("Edit " + (field?.title.lowercased() ?? "personal details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!dirty || text.count > 12000)
                }
            }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog(
                "Discard your unsaved changes?", isPresented: $discard, titleVisibility: .visible
            ) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
    }
    private func save() {
        var draft = profile
        if let field {
            field.set(text.components(separatedBy: .newlines), in: &draft)
        } else {
            draft.name = name
            draft.dateOfBirth = hasBirthDate ? RevaDate.day(birthDate) : ""
        }
        do {
            try store.mutate {
                $0.profile = try NativeProfileEditing.apply(
                    original: profile, draft: draft, current: $0.profile, field: field)
            }
            store.notice = (field?.title ?? "Personal details") + " saved."
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
