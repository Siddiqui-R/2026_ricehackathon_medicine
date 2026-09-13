// Section edits replace only displayed fields and reject overlapping concurrent edits.
import Foundation

enum NativeProfileEditing {
    static func apply(
        original: PatientProfile, draft: PatientProfile, current: PatientProfile, field: MedicalProfileField?
    ) throws -> PatientProfile {
        guard current.id == original.id, draft.id == original.id else {
            throw RevaError.invalid("The active profile changed. Reopen this section.")
        }
        var result = current
        if let field {
            guard field.values(current) == field.values(original) else {
                throw RevaError.invalid(
                    "This section changed while you were editing. Reopen it to see the latest details.")
            }
            field.set(
                field.values(draft).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
                    !$0.isEmpty
                }, in: &result)
        } else {
            guard current.name == original.name, current.dateOfBirth == original.dateOfBirth else {
                throw RevaError.invalid("Your personal details changed. Reopen them before saving.")
            }
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 240 else {
                throw RevaError.invalid("Enter your name (up to 240 characters).")
            }
            result.name = name
            result.dateOfBirth = draft.dateOfBirth
            let words = name.split(whereSeparator: \.isWhitespace)
            result.initials = [words.first?.first, words.count > 1 ? words.last?.first : nil].compactMap {
                $0.map(String.init)
            }.joined().uppercased()
        }
        return result
    }
}
