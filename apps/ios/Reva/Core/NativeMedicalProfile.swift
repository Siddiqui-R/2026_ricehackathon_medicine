// Pure, source-grounded profile updates preserve manual edits and source citations across clients.
import CryptoKit
import Foundation

enum MedicalProfileField: String, CaseIterable, Identifiable {
    case allergies, medications, conditions, surgeriesAndImplants, careNotes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allergies: return "Allergies"
        case .medications: return "Medications"
        case .conditions: return "Conditions"
        case .surgeriesAndImplants: return "Surgeries & implants"
        case .careNotes: return "Care notes"
        }
    }
    var symbol: String {
        switch self {
        case .allergies: return "allergens"
        case .medications: return "pills"
        case .conditions: return "heart.text.clipboard"
        case .surgeriesAndImplants: return "cross.case"
        case .careNotes: return "note.text"
        }
    }
    func values(_ profile: PatientProfile) -> [String] {
        switch self {
        case .allergies: return profile.allergies
        case .medications: return profile.medications
        case .conditions: return profile.conditions
        case .surgeriesAndImplants: return profile.surgeriesAndImplants ?? []
        case .careNotes:
            return (profile.careNotes ?? "").components(separatedBy: .newlines).filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }
    func set(_ values: [String], in profile: inout PatientProfile) {
        switch self {
        case .allergies: profile.allergies = values
        case .medications: profile.medications = values
        case .conditions: profile.conditions = values
        case .surgeriesAndImplants: profile.surgeriesAndImplants = values
        case .careNotes: profile.careNotes = values.isEmpty ? nil : values.joined(separator: "\n")
        }
    }
    func facts(_ values: AIMedicalHistory.Facts) -> [AIProfileFact] {
        switch self {
        case .allergies: return values.allergies
        case .medications: return values.medications
        case .conditions: return values.conditions
        case .surgeriesAndImplants: return values.surgeriesAndImplants
        case .careNotes: return values.careNotes
        }
    }
    func setFacts(_ items: [AIProfileFact], in values: inout AIMedicalHistory.Facts) {
        switch self {
        case .allergies: values.allergies = items
        case .medications: values.medications = items
        case .conditions: values.conditions = items
        case .surgeriesAndImplants: values.surgeriesAndImplants = items
        case .careNotes: values.careNotes = items
        }
    }
}
struct NativeProfileSource: Codable, Equatable {
    var id: String
    var version: Int
    var title: String
    var date: String
    var text: String
}
struct NativeProfileResult: Codable {
    var allergies: [AIProfileFact]
    var medications: [AIProfileFact]
    var conditions: [AIProfileFact]
    var surgeriesAndImplants: [AIProfileFact]
    var careNotes: [AIProfileFact]
    var model: String
    var facts: AIMedicalHistory.Facts {
        .init(
            allergies: allergies, medications: medications, conditions: conditions,
            surgeriesAndImplants: surgeriesAndImplants, careNotes: careNotes)
    }
}
enum NativeMedicalProfile {
    static let emptyFacts = AIMedicalHistory.Facts(
        allergies: [], medications: [], conditions: [], surgeriesAndImplants: [], careNotes: [])
    static func key(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased(
            with: Locale(identifier: "en_US"))
    }
    static func sources(_ snapshot: AppSnapshot) -> [NativeProfileSource] {
        snapshot.records.filter {
            $0.kind != "Sync recovery" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .map { .init(id: $0.id, version: $0.version, title: $0.title, date: $0.date, text: $0.text) }
        .sorted { $0.id.compare($1.id, locale: Locale(identifier: "en_US")) == .orderedAscending }
    }
    // JSON property order matches profileSourceKey in the web client, preventing cross-device refresh loops.
    static func signature(_ sources: [NativeProfileSource]) throws -> String {
        func quote(_ value: String) throws -> String {
            String(
                decoding: try JSONSerialization.data(
                    withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
                as: UTF8.self)
        }
        let items = try sources.map { source in
            "{\"id\":\(try quote(source.id)),\"version\":\(source.version),\"title\":\(try quote(source.title)),\"date\":\(try quote(source.date)),\"text\":\(try quote(source.text))}"
        }
        return SHA256.hash(data: Data(("[" + items.joined(separator: ",") + "]").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    static func validateSources(_ sources: [NativeProfileSource]) throws {
        guard sources.count <= 100, sources.allSatisfy({ $0.text.utf8.count <= 100_000 }),
            sources.reduce(0, { $0 + $1.text.utf8.count }) <= 200_000
        else {
            throw RevaError.invalid(
                "Automatic profile updates support up to 100 reports and 200 KB of text (100 KB per report). Your profile is preserved."
            )
        }
    }
    static func validate(_ result: NativeProfileResult, sources: [NativeProfileSource]) throws {
        let known = Set(sources.map(\.id))
        guard !result.model.isEmpty, result.model.utf8.count <= 200,
            MedicalProfileField.allCases.allSatisfy({ field in
                let facts = field.facts(result.facts)
                return facts.count <= 30
                    && facts.allSatisfy {
                        !key($0.text).isEmpty && $0.text.utf8.count <= 500 && !$0.recordIDs.isEmpty
                            && $0.recordIDs.count <= 100 && Set($0.recordIDs).count == $0.recordIDs.count
                            && Set($0.recordIDs).isSubset(of: known)
                    }
            })
        else {
            throw RevaError.invalid("The AI profile response was invalid. Your existing details were kept.")
        }
    }
    static func apply(
        _ result: NativeProfileResult, to profile: PatientProfile, signature: String,
        at date: String = RevaDate.now
    ) -> PatientProfile {
        var next = profile
        var facts = emptyFacts
        var suppressed = profile.aiMedicalHistory?.suppressed ?? [:]
        var removedSources = profile.aiMedicalHistory?.suppressedRecordIDs ?? [:]
        for field in MedicalProfileField.allCases {
            let current = field.values(profile)
            let prior = field.facts(profile.aiMedicalHistory?.facts ?? emptyFacts)
            let currentKeys = Set(current.map(key))
            let removed = prior.filter { !currentKeys.contains(key($0.text)) }
            let omitted = Set(suppressed[field.rawValue] ?? []).union(removed.map { key($0.text) })
            let sourceIDs = Set(removedSources[field.rawValue] ?? []).union(removed.flatMap(\.recordIDs))
            suppressed[field.rawValue] = omitted.sorted()
            removedSources[field.rawValue] = sourceIDs.sorted()
            let generated = Set(prior.map { key($0.text) })
            let manual = current.filter { !generated.contains(key($0)) }
            var retained = Set(manual.map(key))
            var accepted: [AIProfileFact] = []
            for fact in field.facts(result.facts) {
                let normalized = key(fact.text)
                guard !omitted.contains(normalized), !retained.contains(normalized),
                    Set(fact.recordIDs).isDisjoint(with: sourceIDs)
                else { continue }
                retained.insert(normalized)
                accepted.append(
                    .init(
                        text: fact.text.split(whereSeparator: \.isWhitespace).joined(separator: " "),
                        recordIDs: fact.recordIDs))
            }
            field.setFacts(accepted, in: &facts)
            field.set(manual + accepted.map(\.text), in: &next)
        }
        next.aiMedicalHistory = .init(
            sourceSignature: signature, generatedAt: date, model: result.model,
            facts: facts, suppressed: suppressed, suppressedRecordIDs: removedSources)
        return next
    }
}
