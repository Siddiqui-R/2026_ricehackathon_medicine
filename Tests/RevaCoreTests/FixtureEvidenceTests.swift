import XCTest
@testable import RevaCore

/// Executes the checked-in synthetic acceptance scenarios against the real engine.
final class FixtureEvidenceTests: XCTestCase {
    private struct Expectations: Decodable {
        struct Scenario: Decodable {
            struct SourceCheck: Decodable { let recordID: String; let page: Int; let contains: String }
            let id: String
            let visitID: String
            let mustInclude: [String]
            let mustExclude: [String]
            let mayInclude: [String]
            let sourceChecks: [SourceCheck]
        }
        struct PinningCase: Decodable { let visitID: String; let pinRecordID: String; let mustInclude: String }
        struct ReviewCase: Decodable {
            let recordID: String
            let expectedStatus: String
            let sourceFilename: String
            let knownDate: String
            let expectedText: String
        }
        let synthetic: Bool
        let scenarios: [Scenario]
        let pinningCase: PinningCase
        let reviewCase: ReviewCase
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func load<T: Decodable>(_ filename: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: root.appendingPathComponent("demo/" + filename)))
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func testEveryExpectedScenarioSelectsAndExcludesItsDeclaredRecords() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        let expected = try load("expected-evidence.json", as: Expectations.self)
        try snapshot.validate()
        XCTAssertTrue(expected.synthetic)
        XCTAssertGreaterThanOrEqual(expected.scenarios.count, 2)
        var selectedByScenario: [Set<String>] = []

        for scenario in expected.scenarios {
            let visit = try XCTUnwrap(snapshot.visits.first { $0.id == scenario.visitID }, scenario.id)
            let report = ReportEngine.generate(visit: visit, records: snapshot.records)
            let selected = Set(report.selectedRecordIDs)
            selectedByScenario.append(selected)
            let detail = "Scenario \(scenario.id); selected \(report.selectedRecordIDs.sorted())"
            XCTAssertEqual(report.selectedRecordIDs.count, selected.count, "Duplicate evidence: " + detail)
            for id in scenario.mustInclude {
                XCTAssertTrue(selected.contains(id), "Missing required record \(id). " + detail)
            }
            for id in scenario.mustExclude {
                XCTAssertFalse(selected.contains(id), "Included unrelated record \(id). " + detail)
            }
            let allowed = Set(scenario.mustInclude + scenario.mayInclude)
            XCTAssertTrue(selected.isSubset(of: allowed), "Unexpected evidence outside fixture allowance. " + detail)

            let references = report.sections.flatMap(\.sources)
            for check in scenario.sourceChecks {
                let record = try XCTUnwrap(snapshot.records.first { $0.id == check.recordID })
                guard let reference = references.first(where: { $0.recordID == check.recordID && $0.page == check.page }) else {
                    XCTFail("\(scenario.id) must link \(check.recordID), page \(check.page); actual pages \(references.filter { $0.recordID == check.recordID }.map(\.page))")
                    continue
                }
                let pages = try XCTUnwrap(record.pageTexts)
                XCTAssertTrue(pages.indices.contains(reference.page - 1))
                guard pages.indices.contains(reference.page - 1) else { continue }
                XCTAssertTrue(normalized(reference.excerpt).contains(normalized(check.contains)), "Expected clinical detail missing from generated excerpt")
                XCTAssertTrue(normalized(pages[reference.page - 1]).contains(normalized(check.contains)),
                    "Expected evidence phrase is absent from the actual referenced page: \(check.contains)")
            }
        }
        XCTAssertGreaterThan(Set(selectedByScenario).count, 1, "The distinct visit goals produced identical evidence sets.")
    }

    func testEveryGeneratedReferenceResolvesToItsVersionAndOriginalPage() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        let expected = try load("expected-evidence.json", as: Expectations.self)
        for scenario in expected.scenarios {
            let visit = try XCTUnwrap(snapshot.visits.first { $0.id == scenario.visitID })
            let report = ReportEngine.generate(visit: visit, records: snapshot.records)
            let references = report.sections.flatMap(\.sources)
            XCTAssertEqual(Set(references.map(\.recordID)), Set(report.selectedRecordIDs))
            for reference in references {
                let record = try XCTUnwrap(snapshot.records.first { $0.id == reference.recordID })
                let pages = try XCTUnwrap(record.pageTexts)
                XCTAssertEqual(reference.sourceVersion, record.version)
                XCTAssertGreaterThanOrEqual(reference.page, 1)
                XCTAssertLessThanOrEqual(reference.page, record.pageCount)
                guard pages.indices.contains(reference.page - 1) else {
                    XCTFail("Page \(reference.page) does not exist for \(record.id)")
                    continue
                }
                XCTAssertFalse(reference.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertTrue(normalized(pages[reference.page - 1]).contains(normalized(reference.excerpt)),
                    "Excerpt is not grounded in \(record.id), page \(reference.page)")
            }
        }
    }

    func testExplicitFixturePinOverridesBaselineExclusion() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        let expected = try load("expected-evidence.json", as: Expectations.self)
        let pin = expected.pinningCase
        var visit = try XCTUnwrap(snapshot.visits.first { $0.id == pin.visitID })
        let baseline = ReportEngine.generate(visit: visit, records: snapshot.records)
        XCTAssertFalse(baseline.selectedRecordIDs.contains(pin.pinRecordID))
        visit.pinnedRecordIDs.append(pin.pinRecordID)
        let pinned = ReportEngine.generate(visit: visit, records: snapshot.records)
        XCTAssertTrue(pinned.selectedRecordIDs.contains(pin.mustInclude))
        XCTAssertTrue(Set(baseline.selectedRecordIDs).isSubset(of: Set(pinned.selectedRecordIDs)))
        XCTAssertEqual(pinned.selectedRecordIDs.filter { $0 == pin.mustInclude }.count, 1)
        XCTAssertTrue(pinned.sections.flatMap(\.sources).contains { $0.recordID == pin.mustInclude })
    }

    func testAmbiguousScanRetainsItsKnownDateAndVisibleReviewCaveat() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        let expected = try load("expected-evidence.json", as: Expectations.self)
        let review = expected.reviewCase
        let record = try XCTUnwrap(snapshot.records.first { $0.id == review.recordID })
        XCTAssertEqual(record.status, review.expectedStatus)
        XCTAssertTrue(record.needsReview)
        XCTAssertEqual(record.date, review.knownDate)
        XCTAssertEqual(record.sourceFilename, review.sourceFilename)
        XCTAssertTrue(record.text.contains(review.expectedText))
        for scenario in expected.scenarios where scenario.mustInclude.contains(review.recordID) {
            let visit = try XCTUnwrap(snapshot.visits.first { $0.id == scenario.visitID })
            let report = ReportEngine.generate(visit: visit, records: snapshot.records)
            let section = try XCTUnwrap(report.sections.first { $0.sources.contains { $0.recordID == review.recordID } })
            XCTAssertTrue(section.body.contains("Needs review"), "Ambiguous source was presented without its review warning.")
        }
    }
}
