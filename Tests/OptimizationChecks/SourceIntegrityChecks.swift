// Purpose: Verify exact source spans, fixture provenance, relevance and local calendar days.
// Inputs: Synthetic boundary strings and the checked-in fictional snapshot.
// Outputs: Fatal preconditions on regressions and named passing groups.
// Side effects: Reads only the fixture; no database, provider or persistence calls.

import Foundation

#if !canImport(CryptoKit)
    // The Windows harness tests domain behavior; cryptographic signatures are outside its scope.
    enum SHA256 {
        static func hash(data: Data) -> [UInt8] { Array(data) }
    }
#endif

// MARK: - Production source and date regression checks
@main struct SourceIntegrityChecks {
    static func main() throws {
        let longLine = String(repeating: "x", count: 1791) + " dose: 100 mg"
        precondition(ReportEngine.localExcerpt(longLine).isEmpty)
        precondition(ReportEngine.excerptNotice(longLine)?.contains("Open the original") == true)
        for line in ["Dose: 100 mg", "Potassium: 4.15 mmol/L", "No chest pain", "Dose: １０ µg 👩🏽‍⚕️"] {
            let source = "  Exact source line.\r\n" + String(repeating: "x", count: 1790) + line
            let excerpt = ReportEngine.localExcerpt(source)
            precondition(excerpt == "  Exact source line.")
            precondition(source.contains(excerpt))
            precondition(ReportEngine.localExcerpt(line) == line)
        }
        let exact = String(repeating: "x", count: 1800)
        precondition(ReportEngine.localExcerpt(exact) == exact)
        precondition(ReportEngine.excerptNotice(exact) == nil)
        let lines = (0..<25).map { "Line \($0)" }.joined(separator: "\n")
        precondition(ReportEngine.localExcerpt(lines).hasSuffix("Line 23"))
        precondition(ReportEngine.excerptNotice(lines) != nil)
        print("PASS: complete exact source spans and separate omission notices")

        let ordinary = "Medication: synthetic A\nSource date: 2026-09-12\nPlan: synthetic follow-up"
        precondition(ReportEngine.localExcerpt(ordinary) == ordinary)
        precondition(ReportEngine.localExcerpt(ordinary, isDemo: true) == ordinary)
        let trailer = "Before\nInvented for Reva software demonstration.\nAfter"
        precondition(ReportEngine.localExcerpt(trailer) == trailer)
        let fixture =
            "SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD\nSource date: 2026-09-12\nExact content\nInvented for Reva software demonstration."
        precondition(ReportEngine.localExcerpt(fixture, isDemo: true) == "Exact content")
        precondition(ReportEngine.localExcerpt(fixture) == fixture)
        print("PASS: ordinary headers retained; stripping requires recognized fictional provenance")

        let snapshot = try JSONDecoder().decode(
            AppSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var visit = snapshot.visits.first { $0.id == "demo-visit-primary-20260908" }!
        let unrelated = "demo-record-ear-infection"
        precondition(
            !ReportEngine.selectedRecords(visit: visit, records: snapshot.records).contains {
                $0.id == unrelated
            })
        visit.pinnedRecordIDs.append(unrelated)
        precondition(
            ReportEngine.selectedRecords(visit: visit, records: snapshot.records).contains {
                $0.id == unrelated
            })
        var record = snapshot.records[0]
        record.isDemo = false
        record.text = longLine
        record.pageTexts = [longLine]
        visit.pinnedRecordIDs = [record.id]
        let report = ReportEngine.generate(visit: visit, records: [record])
        precondition(
            report.sections.first { !$0.sources.isEmpty }?.body.contains("Open the original") == true)
        print("PASS: unrelated fixture excluded, explicit pins and report omission disclosure retained")

        let localDay = RevaDate.display("2026-09-12T02:30:00Z", zone: "America/Chicago")
        let documentDay = RevaDate.display("2026-09-12", zone: "America/Chicago")
        precondition(localDay == RevaDate.display("2026-09-11"))
        precondition(documentDay == RevaDate.display("2026-09-12"))
        print("PASS: local timestamp day and date-only document day are distinct")
    }
}
