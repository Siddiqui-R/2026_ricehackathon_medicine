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
    // Keep bounded source wording and strip only known synthetic fixture wrapper lines.
    struct Excerpt {
        let text: String
        let omitted: Bool
    }
    static let omissionNotice = SourceReference.excerptOmissionNotice

    static func localExcerpt(_ text: String, isDemo: Bool = false) -> String {
        localExcerptDetails(text, isDemo: isDemo).text
    }
    static func localExcerptDetails(_ text: String, isDemo: Bool = false) -> Excerpt {
        boundedExcerpt(sourceContent(text, isDemo: isDemo))
    }
    // Share the display/preparation policy without rewriting persisted source or provider summaries.
    static func currentSummary(_ record: MedicalRecord) -> String {
        record.summaryModel != nil || hasAuthoredDemoSummary(record)
            ? record.summary : localExcerpt(record.text, isDemo: record.isDemo)
    }
    // Legacy local summaries used a lossy character cut. Recognize that exact old output only
    // to classify it, then display a fresh safe excerpt; never quote the legacy transformed value.
    static func hasAuthoredDemoSummary(_ record: MedicalRecord) -> Bool {
        guard record.isDemo, record.summary != localExcerpt(record.text, isDemo: true) else { return false }
        let lines = record.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let start =
            (lines.prefix(10).lastIndex {
                $0.hasPrefix("Source date:") || $0.hasPrefix("Week ending:")
            }).map { $0 + 1 } ?? 0
        let end = lines.lastIndex { $0.hasPrefix("Invented for Reva software demonstration.") } ?? lines.count
        let legacyLines = start < end ? Array(lines[start..<end]) : lines
        let legacy = String(legacyLines.prefix(24).joined(separator: "\n").prefix(1800))
        return record.summary != legacy
    }
    private struct SourceLine {
        let text: String
        let range: Range<String.Index>
    }
    private static func sourceLines(_ text: String) -> [SourceLine] {
        var lines: [SourceLine] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byLines) {
            line, range, _, _ in
            if let line, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(SourceLine(text: line, range: range))
            }
        }
        return lines
    }
    // Only the explicit demo flag plus the complete known wrapper authorize removing metadata.
    private static func sourceContent(_ text: String, isDemo: Bool) -> String {
        let lines = sourceLines(text)
        guard isDemo,
            lines.first?.text == "SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD",
            let metadata = lines.prefix(10).lastIndex(where: {
                $0.text.hasPrefix("Source date:") || $0.text.hasPrefix("Week ending:")
            }),
            let trailer = lines.lastIndex(where: {
                $0.text
                    == "Invented for Reva software demonstration. Not a real patient record or medical advice."
            }), metadata + 1 < trailer,
            lines.dropFirst(trailer + 1).allSatisfy({ line in
                line.text.range(
                    of: #"^Synthetic source ID: demo-record-[a-z0-9-]+$"#, options: .regularExpression) != nil
                    || line.text.range(of: #"^Page \d+ of \d+$"#, options: .regularExpression) != nil
                    || line.text == "SYNTHETIC SCAN | 1 page | no real patient data"
            })
        else { return text }
        return String(text[lines[metadata + 1].range.lowerBound..<lines[trailer - 1].range.upperBound])
    }
    // A cut never splits a source line, including a value/unit or a negation. Internal whitespace
    // remains byte-for-byte source wording; an overlong first line yields an explicitly omitted excerpt.
    private static func boundedExcerpt(_ text: String, start: Int = 0) -> Excerpt {
        let lines = sourceLines(text)
        guard lines.indices.contains(start) else { return Excerpt(text: "", omitted: false) }
        let lower = lines[start].range.lowerBound
        var upper = lower
        var count = 0
        for line in lines.dropFirst(start).prefix(24) {
            guard text[lower..<line.range.upperBound].count <= 1800 else { break }
            upper = line.range.upperBound
            count += 1
        }
        return Excerpt(text: String(text[lower..<upper]), omitted: start > 0 || start + count < lines.count)
    }
    // MARK: - Evidence freshness
    // Hash visit intent and the full candidate pool so new or revised records invalidate saved briefs.
    static func signature(visit: Visit, records: [MedicalRecord]) -> String {
        // The rule revision also invalidates old selections when a report has no citations.
        // Includes the candidate pool, so a newly imported relevant document also makes a brief stale.
        let inputs =
            [
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
        return report.sections.flatMap(\.sources).contains { $0.excerptOmitted == nil }
            || report.sourceSignature != signature(visit: visit, records: records)
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
            "want visit review follow followup help need past prior history medical about with this that from have what which would could should count bring report records question questions understand discuss since relevant concern clarify confirm care primary appointment safe safely timing time changes manage when before after including current symptom symptoms entry entries user recent next right left source record details together information recent ongoing routine explain planning plan patient reported document documents existing organize unresolved brief"
                .split(separator: " ").map { String($0) })
        let focusWords = Set(focus.split { !$0.isLetter }.map { String($0) })
        var terms = focusWords.filter { $0.count > 3 && !stopWords.contains($0) }
        for group in groups where !focusWords.isDisjoint(with: group) { terms.formUnion(group) }
        if terms.contains("nausea") || terms.contains("palpitations") { terms.formUnion(groups[3]) }
        return records.compactMap { record -> (MedicalRecord, Int)? in
            if visit.pinnedRecordIDs.contains(record.id) { return (record, 1000) }
            let index =
                (record.title + " " + record.tags.joined(separator: " ") + " " + record.summary + " "
                + (record.pageTexts?.isEmpty == false ? record.pageTexts! : [record.text]).map {
                    sourceContent($0, isDemo: record.isDemo)
                }
                .joined(separator: " ")).lowercased()
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
                let content = sourceContent(text, isDemo: record.isDemo).lowercased()
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
            let excerpt = relevantExcerpt(pageText, focusWords: focusWords, isDemo: record.isDemo)
            let sourcePage = (record.pageTexts?.isEmpty == false) ? pageIndex + 1 : 0
            sections.append(
                ReportSection(
                    title: record.title, body: excerpt.text,
                    sources: [
                        SourceReference(
                            recordID: record.id, page: sourcePage, excerpt: excerpt.text,
                            sourceVersion: record.version, excerptOmitted: excerpt.omitted)
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
    private static func relevantExcerpt(_ text: String, focusWords: Set<String>, isDemo: Bool) -> Excerpt {
        let content = sourceContent(text, isDemo: isDemo)
        let opening = boundedExcerpt(content)
        func score(_ value: String) -> Int {
            focusWords.intersection(Set(value.lowercased().split { !$0.isLetter }.map(String.init))).count
        }
        guard score(opening.text) == 0 else { return opening }
        let lines = sourceLines(content)
        guard let match = lines.indices.max(by: { score(lines[$0].text) < score(lines[$1].text) }),
            score(lines[match].text) > 0
        else { return opening }
        return boundedExcerpt(content, start: max(0, match - 2))
    }
}
