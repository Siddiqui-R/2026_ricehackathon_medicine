import Foundation
import CryptoKit

enum ReportEngine {
    static func localExcerpt(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return String(lines.prefix(8).joined(separator: "\n").prefix(1400))
    }
    static func signature(visit: Visit, records: [MedicalRecord]) -> String {
        // Includes the candidate pool, so a newly imported relevant document also makes a brief stale.
        let inputs = [visit.type, visit.concern, visit.goal, visit.date, visit.pinnedRecordIDs.sorted().joined(separator: ",")] + records.sorted { $0.id < $1.id }.map { "\($0.id)|\($0.version)|\($0.text)|\($0.summary)|\($0.tags.joined(separator: ","))|\($0.status)" }
        return SHA256.hash(data: Data(inputs.joined(separator: "\u{1e}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func isStale(_ visit: Visit, records: [MedicalRecord]) -> Bool {
        guard let report = visit.report else { return false }
        return report.sourceSignature != signature(visit: visit, records: records)
    }
    static func selectedRecords(visit: Visit, records: [MedicalRecord]) -> [MedicalRecord] {
        let focus = (visit.type + " " + visit.concern + " " + visit.goal).lowercased()
        let groups = [
            ["orthopedic", "orthopedics", "fracture", "broken", "fibula", "tibia", "implant", "leg", "hardware", "nail"],
            ["nausea", "palpitation", "palpitations", "heart", "cardiology", "ecg", "dizziness", "asthma", "breathing"],
            ["ear", "otitis", "infection"],
            ["lab", "labs", "blood", "thyroid", "electrolyte"]
        ]
        let stopWords = Set("want visit review follow followup help need past prior history medical about with this that from have what which would could should count bring report records question questions understand discuss since relevant concern clarify confirm care primary appointment safe safely timing time changes manage when before after including current symptoms recent next right left source record details together information recent ongoing routine explain planning plan".split(separator: " ").map { String($0) })
        let focusWords = Set(focus.split { !$0.isLetter }.map { String($0) })
        var terms = focusWords.filter { $0.count > 3 && !stopWords.contains($0) }
        for group in groups where !focusWords.isDisjoint(with: group) { terms.formUnion(group) }
        if terms.contains("nausea") || terms.contains("palpitations") { terms.formUnion(groups[3]) }
        return records.compactMap { record -> (MedicalRecord, Int)? in
            if visit.pinnedRecordIDs.contains(record.id) { return (record, 1000) }
            let index = (record.title + " " + record.tags.joined(separator: " ") + " " + record.summary).lowercased()
            let context = record.tags.contains { ["context", "medications", "allergies", "medical-history", "medical history"].contains($0.lowercased()) }
            let indexedWords = Set(index.split { !$0.isLetter }.map { String($0) })
            let count = terms.intersection(indexedWords).count
            guard context || count > 0 else { return nil }
            return (record, count * 10 + (context ? 50 : 0))
        }.sorted { $0.1 == $1.1 ? $0.0.date > $1.0.date : $0.1 > $1.1 }.map(\.0)
    }
    static func generate(visit: Visit, records: [MedicalRecord]) -> VisitReport {
        let selected = selectedRecords(visit: visit, records: records)
        var sections = [ReportSection(title: "Your focus", body: visit.concern + "\n\nGoal: " + visit.goal, sources: [])]
        for record in selected {
            let pages = record.pageTexts ?? [record.text]
            let focusWords = (visit.concern + " " + visit.goal).lowercased().split { !$0.isLetter }.filter { $0.count > 3 }
            let pageIndex = pages.enumerated().max { lhs, rhs in
                focusWords.filter { lhs.element.lowercased().contains($0) }.count < focusWords.filter { rhs.element.lowercased().contains($0) }.count
            }?.offset ?? 0
            let pageText = pages.indices.contains(pageIndex) ? pages[pageIndex] : record.text
            let excerpt = localExcerpt(pageText)
            let caveat = record.needsReview ? "Needs review: verify this extraction against the original.\n\n" : ""
            sections.append(ReportSection(title: record.title, body: caveat + excerpt, sources: [SourceReference(recordID: record.id, page: pageIndex + 1, excerpt: excerpt, sourceVersion: record.version)]))
        }
        sections.append(ReportSection(title: "Information to confirm", body: selected.isEmpty ? "No matching records were found. Add records or pin documents you want to discuss. Missing records do not establish that a condition is absent." : "Confirm current medications, allergies, symptom timing, and any changes since these records were written. This brief contains selected source excerpts; it is not a clinical assessment.", sources: []))
        let suggested = ["Which parts of my history matter most for this concern?", "What should I track before our next visit?", "What are the next steps, and when should I follow up?"]
        return VisitReport(visitID: visit.id, sourceSignature: signature(visit: visit, records: records), sections: sections, questions: visit.report?.questions ?? (visit.questions.isEmpty ? suggested : visit.questions), notes: visit.report?.notes ?? visit.notes, selectedRecordIDs: selected.map(\.id))
    }
}

enum BookingEngine {
    static func validate(_ request: BookingRequest) throws {
        guard !request.clinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.phone.filter(\.isNumber).count >= 10, !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RevaError.invalid("Enter a clinic, a complete phone number, and the visit reason.") }
        guard RevaDate.parse(request.earliest) <= RevaDate.parse(request.latest), TimeZone(identifier: request.timeZone) != nil else { throw RevaError.invalid("Check the date range and time zone.") }
    }
    static func confirm(id: String, snapshot: inout AppSnapshot) throws {
        guard let index = snapshot.bookings.firstIndex(where: { $0.id == id }) else { throw RevaError.invalid("Booking not found.") }
        if snapshot.bookings[index].confirmedVisitID != nil { return }
        guard snapshot.bookings[index].status == "proposed", let visitIndex = snapshot.visits.firstIndex(where: { $0.id == snapshot.bookings[index].visitID }) else { throw RevaError.invalid("This booking is not ready to confirm.") }
        let request = snapshot.bookings[index]
        snapshot.visits[visitIndex].date = request.earliest
        snapshot.visits[visitIndex].clinic = request.clinic
        snapshot.visits[visitIndex].timeZone = request.timeZone
        snapshot.bookings[index].status = "confirmed"
        snapshot.bookings[index].confirmedVisitID = snapshot.visits[visitIndex].id
    }
}
