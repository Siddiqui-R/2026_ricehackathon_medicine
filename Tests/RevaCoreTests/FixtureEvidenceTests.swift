// Purpose: Verify report selection and citations against the checked-in synthetic acceptance scenarios.
// Inputs: demo/seed.json and demo/expected-evidence.json, including page and source uncertainty expectations.
// Outputs: XCTest assertions for allowed evidence, exact source pages, pinning, and source uncertainty.
// Side effects: Reads fixture files and generates reports in memory; no files or network state are changed.

import XCTest

@testable import RevaCore

/// Executes the checked-in synthetic acceptance scenarios against the real engine.
final class FixtureEvidenceTests: XCTestCase {
    // MARK: - Shared browser/native signatures for the refreshed fixture
    func testDemoSignaturesMatchBrowserGoldenValues() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        XCTAssertEqual(
            snapshot.visits.map { ReportEngine.signature(visit: $0, records: snapshot.records) },
            [
                "937429cbe44f6a68bfc00a8a478d96fe15cd1d5ccad14f706f11bbf6c2410838",
                "2e7fcfea03b2755a34e4ca33a88d3ba7ff21377d2cbeb72b5efec1d530591e22",
                "94fce266a8ea02ac6a60dcbe6b8268ab949b6756b320daee89e2c07157206caf",
            ])
    }

    // MARK: - Acceptance fixture schema

    private struct Expectations: Decodable {
        struct Scenario: Decodable {
            struct SourceCheck: Decodable {
                let recordID: String
                let page: Int
                let contains: String
            }
            let id: String
            let visitID: String
            let mustInclude: [String]
            let mustExclude: [String]
            let mayInclude: [String]
            let sourceChecks: [SourceCheck]
        }
        struct PinningCase: Decodable {
            let visitID: String
            let pinRecordID: String
            let mustInclude: String
        }
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

    // MARK: - Fixture loading and whitespace comparison

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func load<T: Decodable>(_ filename: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(
            T.self, from: Data(contentsOf: root.appendingPathComponent("demo/" + filename)))
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Scenario selection and original-page citations

    func testSourceRuleVersionSignatureGoldens() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        let expected = [
            "937429cbe44f6a68bfc00a8a478d96fe15cd1d5ccad14f706f11bbf6c2410838",
            "2e7fcfea03b2755a34e4ca33a88d3ba7ff21377d2cbeb72b5efec1d530591e22",
            "94fce266a8ea02ac6a60dcbe6b8268ab949b6756b320daee89e2c07157206caf",
        ]
        XCTAssertEqual(
            snapshot.visits.map { ReportEngine.signature(visit: $0, records: snapshot.records) }, expected)
        var visit = snapshot.visits[0]
        visit.report = ReportEngine.generate(visit: visit, records: snapshot.records)
        XCTAssertFalse(ReportEngine.isStale(visit, records: snapshot.records))
        visit.report?.sourceSignature = "cbfd98f0df80c54187ca88eed7c6cd439c7fd643b86a5a56f0bbea9a13326ee0"
        XCTAssertTrue(ReportEngine.isStale(visit, records: snapshot.records))
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
            XCTAssertTrue(
                selected.isSubset(of: allowed), "Unexpected evidence outside fixture allowance. " + detail)

            let references = report.sections.flatMap(\.sources)
            for check in scenario.sourceChecks {
                let record = try XCTUnwrap(snapshot.records.first { $0.id == check.recordID })
                guard
                    let reference = references.first(where: {
                        $0.recordID == check.recordID && $0.page == check.page
                    })
                else {
                    XCTFail(
                        "\(scenario.id) must link \(check.recordID), page \(check.page); actual pages \(references.filter { $0.recordID == check.recordID }.map(\.page))"
                    )
                    continue
                }
                let pages = try XCTUnwrap(record.pageTexts)
                XCTAssertTrue(pages.indices.contains(reference.page - 1))
                guard pages.indices.contains(reference.page - 1) else { continue }
                XCTAssertTrue(
                    normalized(reference.excerpt).contains(normalized(check.contains)),
                    "Expected clinical detail missing from generated excerpt")
                XCTAssertTrue(
                    normalized(pages[reference.page - 1]).contains(normalized(check.contains)),
                    "Expected evidence phrase is absent from the actual referenced page: \(check.contains)")
            }
        }
        XCTAssertGreaterThan(
            Set(selectedByScenario).count, 1, "The distinct visit goals produced identical evidence sets.")
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
                XCTAssertTrue(
                    normalized(pages[reference.page - 1]).contains(normalized(reference.excerpt)),
                    "Excerpt is not grounded in \(record.id), page \(reference.page)")
            }
        }
    }

    // MARK: - Explicit pins and ambiguous-source review

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

    func testAmbiguousScanRetainsItsKnownDateAndSourceUncertainty() throws {
        let snapshot = try load("seed.json", as: AppSnapshot.self)
        let expected = try load("expected-evidence.json", as: Expectations.self)
        let review = expected.reviewCase
        let record = try XCTUnwrap(snapshot.records.first { $0.id == review.recordID })
        XCTAssertEqual(record.status, review.expectedStatus)
        XCTAssertEqual(record.date, review.knownDate)
        XCTAssertEqual(record.sourceFilename, review.sourceFilename)
        XCTAssertTrue(record.text.contains(review.expectedText))
        for scenario in expected.scenarios where scenario.mustInclude.contains(review.recordID) {
            let visit = try XCTUnwrap(snapshot.visits.first { $0.id == scenario.visitID })
            let report = ReportEngine.generate(visit: visit, records: snapshot.records)
            let section = try XCTUnwrap(
                report.sections.first { $0.sources.contains { $0.recordID == review.recordID } })
            XCTAssertTrue(
                section.body.contains(review.expectedText),
                "Ambiguous source must retain the unclear date in its excerpt.")
        }
    }
}
