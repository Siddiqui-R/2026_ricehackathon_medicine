// Purpose: Select relevant source records and build traceable local visit briefs.
// Inputs: Visit goals, pinned record IDs and versioned record text.
// Outputs: Source selection/signatures and quoted report sections.
// Side effects: None; this engine does not call AI or write files.

import CryptoKit
import Foundation

// MARK: - Local source preparation
// Select from supplied sources; new report IDs/timestamps use domain defaults. No cloud model runs here.
enum ReportEngine {
    // MARK: - Faithful local excerpts
    // Ordinary uploads keep their headers; fixture stripping requires explicit provenance.
    static func localExcerpt(_ text: String, isDemo: Bool = false) -> String {
        SourceExcerpt.passage(SourceExcerpt.sourceText(text, isDemo: isDemo)).text
    }
    static func excerptNotice(_ text: String, isDemo: Bool = false) -> String? {
        SourceExcerpt.passage(SourceExcerpt.sourceText(text, isDemo: isDemo)).notice
    }
    private static func contentLines(_ text: String) -> [String] {
        SourceExcerpt.contentLines(text).map(String.init)
    }
    // MARK: - Evidence freshness
    // Hash visit intent and the full candidate pool so new or revised records invalidate saved briefs.
    static func signature(visit: Visit, records: [MedicalRecord]) -> String {
        // Includes the candidate pool, so a newly imported relevant document also makes a brief stale.
        let inputs =
            [
                // A rule revision invalidates older briefs without changing original records.
                "source-rules-v2", visit.type, visit.concern, visit.goal,
                String(RevaDate.parse(visit.date).timeIntervalSince1970),
                visit.pinnedRecordIDs.sorted().joined(separator: ","),
            ]
            + records.sorted { $0.id < $1.id }.map {
                "\($0.id)|\($0.version)|\($0.title)|\($0.date)|\($0.text)|\($0.summary)|\($0.tags.joined(separator: ","))|\($0.status)"
            }
        return SHA256.hash(data: Data(inputs.joined(separator: "\u{1e}").utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }
    static func isStale(_ visit: Visit, records: [MedicalRecord]) -> Bool {
        guard let report = visit.report else { return false }
        return report.sourceSignature != signature(visit: visit, records: records)
    }
    // MARK: - Relevant record selection
    // Match goal terms and context, retain explicit pins, and ignore generic entry labels.
    static func selectedRecords(visit: Visit, records: [MedicalRecord]) -> [MedicalRecord] {
        let focus = (visit.type + " " + visit.concern + " " + visit.goal).lowercased()
        let groups = [
            [
                "orthopedic", "orthopedics", "fracture", "broken", "fibula", "tibia", "implant", "leg",
                "hardware", "nail",
            ],
            [
                "nausea", "palpitation", "palpitations", "heart", "cardiology", "ecg", "dizziness", "asthma",
                "breathing",
            ],
            ["ear", "otitis", "infection"],
            ["lab", "labs", "blood", "thyroid", "electrolyte"],
        ]
        let stopWords = Set(
            "want visit review follow followup help need past prior history medical about with this that from have what which would could should count bring report records question questions understand discuss since relevant concern clarify confirm care primary appointment safe safely timing time changes manage when before after including current symptom symptoms entry entries user recent next right left source record details together information recent ongoing routine explain planning plan patient reported documents existing organize unresolved"
                .split(separator: " ").map { String($0) })
        let focusWords = Set(focus.split { !$0.isLetter }.map { String($0) })
        var terms = focusWords.filter { $0.count > 3 && !stopWords.contains($0) }
        for group in groups where !focusWords.isDisjoint(with: group) { terms.formUnion(group) }
        if terms.contains("nausea") || terms.contains("palpitations") { terms.formUnion(groups[3]) }
        return records.compactMap { record -> (MedicalRecord, Int)? in
            if visit.pinnedRecordIDs.contains(record.id) { return (record, 1000) }
            let index =
                (record.title + " " + record.tags.joined(separator: " ") + " " + record.summary + " "
                + SourceExcerpt.sourceText(record.text, isDemo: record.isDemo)).lowercased()
            let context = record.tags.contains {
                ["context", "medications", "allergies", "medical-history", "medical history"].contains(
                    $0.lowercased())
            }
            let indexedWords = Set(index.split { !$0.isLetter }.map { String($0) })
            let count = terms.intersection(indexedWords).count
            guard context || count > 0 else { return nil }
            return (record, count * 10 + (context ? 50 : 0))
        }.sorted { $0.1 == $1.1 ? $0.0.date > $1.0.date : $0.1 > $1.1 }.map(\.0)
    }
    // MARK: - Brief assembly
    // Select original page passages and preserve questions/notes while building source references.
    static func generate(visit: Visit, records: [MedicalRecord]) -> VisitReport {
        let selected = selectedRecords(visit: visit, records: records)
        var sections = [
            ReportSection(title: "Your focus", body: visit.concern + "\n\nGoal: " + visit.goal, sources: [])
        ]
        for record in selected {
            let pages = record.pageTexts ?? [record.text]
            let focusWords = Set(
                (visit.concern + " " + visit.goal).lowercased().split { !$0.isLetter }.map { String($0) }
                    .filter { $0.count > 3 })
            func pageScore(_ text: String) -> Int {
                let content = SourceExcerpt.sourceText(text, isDemo: record.isDemo).lowercased()
                let words = Set(content.split { !$0.isLetter }.map { String($0) })
                var score = focusWords.intersection(words).count
                if focusWords.contains("implant") || focusWords.contains("hardware") {
                    if content.contains("implant location:") { score += 20 }
                    if content.contains("device identification") { score += 5 }
                }
                return score
            }
            let pageIndex =
                pages.enumerated().max { lhs, rhs in
                    let left = pageScore(lhs.element)
                    let right = pageScore(rhs.element)
                    return left == right ? lhs.offset < rhs.offset : left < right
                }?.offset ?? 0
            let pageText = pages.indices.contains(pageIndex) ? pages[pageIndex] : record.text
            let passage = relevantExcerpt(
                SourceExcerpt.sourceText(pageText, isDemo: record.isDemo), focusWords: focusWords)
            let excerpt = passage.text
            let caveat =
                record.needsReview ? "Needs review: verify this extraction against the original.\n\n" : ""
            let sourcePage = (record.pageTexts?.isEmpty == false) ? pageIndex + 1 : 0
            sections.append(
                ReportSection(
                    title: record.title,
                    body: caveat + (passage.notice.map { $0 + "\n\n" } ?? "") + excerpt,
                    sources: [
                        SourceReference(
                            recordID: record.id, page: sourcePage, excerpt: excerpt,
                            sourceVersion: record.version)
                    ]))
        }
        sections.append(
            ReportSection(
                title: "Information to confirm",
                body: selected.isEmpty
                    ? "No matching records were found. Add records or pin documents you want to discuss. Missing records do not establish that a condition is absent."
                    : "Confirm current medications, allergies, symptom timing, and any changes since these records were written. This brief contains selected source excerpts; it is not a clinical assessment.",
                sources: []))
        let suggested = [
            "Which parts of my history matter most for this concern?",
            "What should I track before our next visit?",
            "What are the next steps, and when should I follow up?",
        ]
        return VisitReport(
            visitID: visit.id, sourceSignature: signature(visit: visit, records: records), sections: sections,
            questions: visit.questions.isEmpty && visit.report == nil ? suggested : visit.questions,
            notes: visit.notes, selectedRecordIDs: selected.map(\.id))
    }

    /// Keep a contiguous source passage. If the opening excerpt has no focus terms,
    /// look deeper in a long page instead of citing an unrelated introduction.
    // MARK: - Deep source passage selection
    // When the opening has no focus terms, choose a contiguous bounded passage near a deeper match.
    private static func relevantExcerpt(_ text: String, focusWords: Set<String>) -> SourceExcerpt {
        let opening = SourceExcerpt.passage(text)
        func score(_ value: String) -> Int {
            focusWords.intersection(Set(value.lowercased().split { !$0.isLetter }.map(String.init))).count
        }
        guard score(opening.text) == 0 else { return opening }
        let lines = contentLines(text)
        guard let match = lines.indices.max(by: { score(lines[$0]) < score(lines[$1]) }),
            score(lines[match]) > 0
        else { return opening }
        let start = max(0, match - 2)
        return SourceExcerpt.passage(text, startLine: start)
    }
}
