// Transient preparation uses the same concise contract as the website without creating appointments.
import Foundation

struct NativeVisitBrief: Identifiable, Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id = UUID()
    var patient: PatientProfile
    var visitType: String
    var createdAt = RevaDate.now
    var overview: String
    var questions: [String]
    var sources: [MedicalRecord]
    var model: String
    var snapshot: AppSnapshot

    static func inputs(snapshot: AppSnapshot, type: String, concern: String, questions: [String]) throws -> (
        Visit, [MedicalRecord]
    ) {
        let type = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, type.count <= 80, concern.count <= 2000, questions.count <= 3,
            questions.allSatisfy({ $0.count <= 300 })
        else {
            throw RevaError.invalid(
                "Enter a visit type, a concern under 2,000 characters, and up to three short questions.")
        }
        let visit = Visit(
            title: type, type: type, provider: "", clinic: "", date: RevaDate.now,
            concern: concern.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: "Prepare me for this upcoming appointment using my relevant history and questions.",
            questions: questions)
        var sources = snapshot.records.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.kind != "Sync recovery"
        }
        guard sources.count <= 99 else {
            throw RevaError.invalid("Preparation accepts up to 99 records in one request.")
        }
        for index in sources.indices { sources[index].summary = "" }
        let profile = snapshot.profile
        let fields: [String: Any] = [
            "source":
                "Current medical profile with patient-entered and AI-derived details. Review AI-derived facts against original records. Empty lists mean not documented, not confirmed absent.",
            "allergies": profile.allergies, "medications": profile.medications,
            "conditions": profile.conditions,
            "surgeriesAndImplants": profile.surgeriesAndImplants ?? [], "careNotes": profile.careNotes ?? "",
        ]
        sources.append(
            MedicalRecord(
                title: "Medical profile", kind: "Profile", provider: "", date: RevaDate.now,
                text: String(
                    decoding: try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys),
                    as: UTF8.self), summary: "", pageCount: 0, isDemo: profile.isDemo))
        return (visit, sources)
    }
    static func checked(snapshot: AppSnapshot, visit: Visit, sources: [MedicalRecord], result: AIPreparation)
        throws -> NativeVisitBrief
    {
        let ids = Set(sources.map(\.id))
        guard !result.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            result.model.utf8.count <= 100, !result.model.contains("\0"),
            !result.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            result.overview.count <= 2400, result.overview.split(whereSeparator: \.isWhitespace).count <= 180,
            result.overview.components(separatedBy: "\n").count <= 12, result.questions.count <= 3,
            result.questions.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 140
            }),
            result.selectedRecordIDs.count <= 6,
            Set(result.selectedRecordIDs).count == result.selectedRecordIDs.count,
            Set(result.selectedRecordIDs).isSubset(of: ids)
        else {
            throw RevaError.invalid(
                "The brief response was too long or included invalid sources. Please generate it again.")
        }
        return NativeVisitBrief(
            patient: snapshot.profile, visitType: visit.type, overview: result.overview,
            questions: result.questions,
            sources: result.selectedRecordIDs.compactMap { id in sources.first { $0.id == id } },
            model: result.model, snapshot: snapshot)
    }
}
