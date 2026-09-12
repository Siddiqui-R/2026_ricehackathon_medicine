// Purpose: Guard exact source spans, demo provenance and calendar-day versus instant display.
// Inputs: Synthetic boundaries, the fictional seed and persisted citation JSON.
// Outputs: Regression assertions for audited source integrity and relevance defects.
// Side effects: Reads checked-in fixtures; no provider calls or persistent writes.
import XCTest

@testable import RevaCore

final class ExcerptIntegrityTests: XCTestCase {
    private func seed() throws -> AppSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try JSONDecoder().decode(
            AppSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("demo/seed.json")))
    }
    func testNumericUnitsNegationAndUnicodeAreNeverSplitAtTheCap() {
        for ending in [
            "dose: 100 mg", "potassium: 4.1 mmol/L", "No evidence of fracture", "👩🏽‍⚕️ reviewed café: 100 mg",
        ] {
            let text = String(repeating: "x", count: 1792) + "\n" + ending
            let excerpt = ReportEngine.localExcerptDetails(text)
            XCTAssertEqual(excerpt.text, String(repeating: "x", count: 1792))
            XCTAssertTrue(excerpt.omitted)
            XCTAssertTrue(text.contains(excerpt.text))
            XCTAssertFalse(excerpt.text.contains("dose: 10"))
        }
        let audited = String(repeating: "x", count: 1792) + "dose: 100 mg"
        XCTAssertEqual(String(audited.prefix(1800)).suffix(8), "dose: 10")
        XCTAssertEqual(ReportEngine.localExcerptDetails(audited).text, "")
        XCTAssertTrue(ReportEngine.localExcerptDetails(audited).omitted)
    }
    func testContiguousSourceWhitespaceAndFullLinesArePreserved() {
        let text = "  dose: 100 mg\r\n\r\n  Do not discontinue.\r\n👩🏽‍⚕️ reviewed café."
        XCTAssertEqual(ReportEngine.localExcerpt(text), text)
        let long = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let excerpt = ReportEngine.localExcerptDetails(long)
        XCTAssertEqual(excerpt.text, (1...24).map { "line \($0)" }.joined(separator: "\n"))
        XCTAssertTrue(excerpt.omitted)
        XCTAssertTrue(long.contains(excerpt.text))
    }
    func testOrdinaryMetadataAndQuotedDemoWordingArePreserved() {
        let text =
            "Source date: 2026-09-01\nPotassium 4.1 mmol/L\nInvented for Reva software demonstration. is a quoted phrase."
        XCTAssertEqual(ReportEngine.localExcerpt(text), text)
        XCTAssertEqual(ReportEngine.localExcerpt(text, isDemo: true), text)
        let wrapper =
            "SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD\nSource date: 2026-09-01\nPotassium 4.1 mmol/L\nInvented for Reva software demonstration. Not a real patient record or medical advice."
        XCTAssertEqual(ReportEngine.localExcerpt(wrapper), wrapper)
        XCTAssertEqual(ReportEngine.localExcerpt(wrapper, isDemo: true), "Potassium 4.1 mmol/L")
    }
    func testCompletedPalpitationVisitExcludesUnrelatedEarNoteAndRetainsPins() throws {
        let snapshot = try seed()
        var visit = try XCTUnwrap(snapshot.visits.first { $0.id == "demo-visit-primary-20260908" })
        XCTAssertFalse(
            ReportEngine.selectedRecords(visit: visit, records: snapshot.records).contains {
                $0.id == "demo-record-ear-infection"
            })
        visit.pinnedRecordIDs.append("demo-record-ear-infection")
        XCTAssertTrue(
            ReportEngine.selectedRecords(visit: visit, records: snapshot.records).contains {
                $0.id == "demo-record-ear-infection"
            })
    }
    func testReportOmitsNoticeFromQuotedFieldAndRoundTripsMetadata() throws {
        var snapshot = try seed()
        var visit = snapshot.visits[0]
        var record = snapshot.records[0]
        record.text = (1...30).map { "retained source line \($0)" }.joined(separator: "\n")
        record.pageTexts = nil
        record.isDemo = false
        visit.pinnedRecordIDs = [record.id]
        let report = ReportEngine.generate(visit: visit, records: [record])
        let source = try XCTUnwrap(report.sections.flatMap(\.sources).first)
        XCTAssertEqual(source.excerptOmitted, true)
        XCTAssertTrue(record.text.contains(source.excerpt))
        XCTAssertFalse(source.excerpt.contains(ReportEngine.omissionNotice))
        snapshot.visits[0].report = report
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.visits[0].report?.sections.flatMap(\.sources).first?.excerptOmitted, true)
        let legacy = Data(#"{"recordID":"old","page":1,"excerpt":"Original text"}"#.utf8)
        let oldSource = try JSONDecoder().decode(SourceReference.self, from: legacy)
        XCTAssertNil(oldSource.excerptOmitted)
        XCTAssertNotNil(oldSource.omissionNotice)
        visit.report = report
        XCTAssertFalse(ReportEngine.isStale(visit, records: [record]))
        visit.report?.sections[1].sources[0].excerptOmitted = nil
        XCTAssertTrue(ReportEngine.isStale(visit, records: [record]))
    }
    func testDateOnlyUsesCalendarDayWhileInstantsUseDisplayZoneWithoutRequiringTime() {
        XCTAssertEqual(
            RevaDate.display("2026-09-12T01:00:00Z", zone: "America/Chicago"), RevaDate.display("2026-09-11"))
        XCTAssertEqual(
            RevaDate.display("2026-09-12", time: true, zone: "Pacific/Honolulu"),
            RevaDate.display("2026-09-12"))
        XCTAssertEqual(
            RevaDate.display("2026-09-11T23:30:00Z", zone: "Asia/Tokyo"), RevaDate.display("2026-09-12"))
    }
}
