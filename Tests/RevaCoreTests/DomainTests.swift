// Purpose: Exercise local evidence selection, source fidelity, persistence, dates, and legacy snapshot compatibility.
// Inputs: Checked-in synthetic snapshot data and explicitly constructed invalid or revised values.
// Outputs: XCTest assertions for domain behavior and lossless local data handling.
// Side effects: Persistence tests write only to a unique temporary directory and remove it afterward.

import XCTest

@testable import RevaCore

final class DomainTests: XCTestCase {
    // MARK: - Synthetic snapshot fixture

    func fixture() throws -> AppSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try JSONDecoder().decode(
            AppSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("demo/seed.json")))
    }
    // MARK: - Evidence selection and source invalidation

    func testDistinctVisitEvidencePinsAndSourceVersions() throws {
        let data = try fixture()
        try data.validate()
        let ortho = try XCTUnwrap(data.visits.first { $0.type == "Orthopedics" })
        let primary = try XCTUnwrap(data.visits.first { $0.id == "demo-visit-primary-20260915" })
        let orthopedic = ReportEngine.generate(visit: ortho, records: data.records)
        let general = ReportEngine.generate(visit: primary, records: data.records)
        XCTAssertTrue(orthopedic.selectedRecordIDs.contains("demo-record-tibia-procedure"))
        XCTAssertFalse(orthopedic.selectedRecordIDs.contains("demo-record-ear-infection"))
        XCTAssertTrue(general.selectedRecordIDs.contains("demo-record-ecg"))
        XCTAssertTrue(general.selectedRecordIDs.contains("demo-record-labs"))
        XCTAssertNotEqual(Set(orthopedic.selectedRecordIDs), Set(general.selectedRecordIDs))
        var pinned = ortho
        pinned.pinnedRecordIDs = ["demo-record-ear-infection"]
        XCTAssertTrue(
            ReportEngine.generate(visit: pinned, records: data.records).selectedRecordIDs.contains(
                "demo-record-ear-infection"))
        for section in orthopedic.sections {
            for source in section.sources {
                let record = try XCTUnwrap(data.records.first { $0.id == source.recordID })
                XCTAssertEqual(source.sourceVersion, record.version)
                XCTAssertGreaterThan(source.page, 0)
                XCTAssertLessThanOrEqual(source.page, record.pageCount)
                XCTAssertFalse(source.excerpt.isEmpty)
            }
        }
    }
    func testStalenessAfterSourceChangeDeletionAndNewRecord() throws {
        var data = try fixture()
        var visit = data.visits[0]
        visit.report = ReportEngine.generate(visit: visit, records: data.records)
        XCTAssertFalse(ReportEngine.isStale(visit, records: data.records))
        data.records[0].text += "\nA corrected source fact."
        data.records[0].version += 1
        XCTAssertTrue(ReportEngine.isStale(visit, records: data.records))
        visit.report = ReportEngine.generate(visit: visit, records: data.records)
        data.records.removeFirst()
        XCTAssertTrue(ReportEngine.isStale(visit, records: data.records))
        let oldQuestions = visit.questions
        visit.notes = "My own note."
        let renewed = ReportEngine.generate(visit: visit, records: data.records)
        XCTAssertEqual(renewed.questions, oldQuestions)
        XCTAssertEqual(renewed.notes, "My own note.")
    }
    // MARK: - Local persistence and attachment recovery

    func testAtomicPersistenceRecoveryAndAttachmentRoundtrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = LocalRepository(directory: root)
        var data = try fixture()
        try repo.save(data)
        data.records[0].notes = "Persist me"
        try repo.save(data)
        XCTAssertEqual(try LocalRepository(directory: root).load()?.snapshot.records[0].notes, "Persist me")
        let bytes = Data([0, 1, 255, 42])
        _ = try repo.storeAttachment(bytes, filename: "source.pdf")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(repo.attachment("source.pdf"))), bytes)
        XCTAssertThrowsError(try repo.storeAttachment(bytes, filename: "../escape"))
        try Data("broken json".utf8).write(to: root.appendingPathComponent("state.json"))
        XCTAssertTrue(try XCTUnwrap(repo.load()).recovered)
        XCTAssertEqual(try repo.load()?.snapshot.records[0].notes, try fixture().records[0].notes)
    }
    // MARK: - Legacy snapshot compatibility and validation
    func testLegacyBookingDataRoundTripsWithoutChangingVisits() throws {
        var data = try fixture()
        let visits = data.visits
        data.bookings.append(
            BookingRequest(
                visitID: visits[0].id, clinic: "Archived clinic", phone: "7135550100",
                reason: "Archived request",
                earliest: visits[0].date, latest: visits[0].date, timeZone: visits[0].timeZone,
                preferences: "", status: "queued"))
        let restored = try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(data))
        try restored.validate()
        XCTAssertEqual(restored.bookings, data.bookings)
        XCTAssertEqual(restored.visits, visits)
    }
    func testSnapshotRejectsDuplicateIDsAndUnsafeAttachments() throws {
        var data = try fixture()
        data.records.append(data.records[0])
        XCTAssertThrowsError(try data.validate())
        data = try fixture()
        data.records[0].sourceFilename = "../../real-data"
        XCTAssertThrowsError(try data.validate())
    }
    // MARK: - Source fidelity, user edits, and calendar dates

    func testLocalExcerptDoesNotInventFactsOrDropNegation() {
        let text = "No chest pain.\nDose: 2.5 mg\nPotassium 4.1 mmol/L"
        XCTAssertEqual(ReportEngine.localExcerpt(text), text)
    }
    func testQuestionAuthorityAndEquivalentDateFormatting() throws {
        let data = try fixture()
        var visit = data.visits[0]
        visit.report = ReportEngine.generate(visit: visit, records: data.records)
        let signature = visit.report?.sourceSignature
        visit.questions = ["My revised question"]
        visit.notes = "My revised note"
        visit.date = RevaDate.iso(RevaDate.parse(visit.date))
        XCTAssertEqual(ReportEngine.signature(visit: visit, records: data.records), signature)
        let regenerated = ReportEngine.generate(visit: visit, records: data.records)
        XCTAssertEqual(regenerated.questions, visit.questions)
        XCTAssertEqual(regenerated.notes, visit.notes)
        visit.questions = []
        XCTAssertEqual(ReportEngine.generate(visit: visit, records: data.records).questions, [])
    }
    func testDocumentCalendarDateRoundtripsWithoutTimeZoneShift() {
        for value in ["2019-04-18", "2026-09-12", "2026-01-01"] {
            XCTAssertEqual(RevaDate.day(RevaDate.parse(value)), value)
        }
    }
    // MARK: - Central time defaults and explicit-zone preservation

    func testNewVisitsAndSymptomsDefaultToCentralTime() {
        let visit = Visit(
            title: "Follow-up", type: "Primary care", provider: "Fictional clinician", clinic: "Demo clinic",
            date: "2026-01-15T14:00:00Z", concern: "Review", goal: "Prepare")
        XCTAssertEqual(visit.timeZone, "America/Chicago")
        XCTAssertEqual(SymptomEntry().timeZone, "America/Chicago")
    }

    func testDefaultDisplayUsesCentralDateAndHonorsExplicitZones() {
        let instant = "2026-01-15T05:30:00Z"
        XCTAssertEqual(RevaDate.display(instant), RevaDate.display("2026-01-14"))
        XCTAssertEqual(RevaDate.display(instant, zone: "invalid/zone"), RevaDate.display("2026-01-14"))
        XCTAssertEqual(RevaDate.display(instant, zone: "Asia/Tokyo"), RevaDate.display("2026-01-15"))
        XCTAssertEqual(
            RevaDate.display(instant, time: true),
            RevaDate.display(instant, time: true, zone: "America/Chicago"))
        XCTAssertNotEqual(
            RevaDate.display(instant, time: true),
            RevaDate.display(instant, time: true, zone: "America/New_York"))
    }

    func testCentralTodayFollowsStandardAndDaylightTimeWithoutChangingDateOnlyStorage() {
        XCTAssertEqual(RevaDate.today(at: RevaDate.parse("2026-01-15T05:59:00Z")), "2026-01-14")
        XCTAssertEqual(RevaDate.today(at: RevaDate.parse("2026-01-15T06:00:00Z")), "2026-01-15")
        XCTAssertEqual(RevaDate.today(at: RevaDate.parse("2026-07-15T04:59:00Z")), "2026-07-14")
        XCTAssertEqual(RevaDate.today(at: RevaDate.parse("2026-07-15T05:00:00Z")), "2026-07-15")
        XCTAssertEqual(
            RevaDate.defaultTimeZone.secondsFromGMT(for: RevaDate.parse("2026-01-15T12:00:00Z")), -21_600)
        XCTAssertEqual(
            RevaDate.defaultTimeZone.secondsFromGMT(for: RevaDate.parse("2026-07-15T12:00:00Z")), -18_000)
        let today = RevaDate.today(at: RevaDate.parse("2026-01-15T05:59:00Z"))
        XCTAssertEqual(RevaDate.day(RevaDate.parse(today)), "2026-01-14")
        XCTAssertEqual(RevaDate.iso(RevaDate.parse("2026-01-15T05:59:00Z")), "2026-01-15T05:59:00Z")
    }

    func testExistingSymptomZoneAndInstantSurviveRoundtrip() throws {
        let original = SymptomEntry(
            observedAt: "2026-09-12T01:30:00Z", timeZone: "Pacific/Honolulu", symptom: "Headache")
        let restored = try JSONDecoder().decode(SymptomEntry.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.timeZone, "Pacific/Honolulu")
        XCTAssertEqual(restored.observedAt, original.observedAt)
    }
    // MARK: - Retrieval beyond the opening excerpt

    func testLongGenericImportFindsEvidenceBeyondOpeningSummary() throws {
        let data = try fixture()
        var visit = data.visits[0]
        visit.type = "Orthopedics"
        visit.concern = "Implant location"
        visit.goal = "Review hardware"
        var record = data.records[0]
        record.id = "generic-long-import"
        record.title = "Uploaded document"
        record.tags = []
        record.text =
            Array(repeating: "Administrative information retained for this appointment.", count: 40).joined(
                separator: "\n")
            + "\nImplant location: RIGHT TIBIA. Hardware retained.\nNo additional procedure documented."
        record.summary = ReportEngine.localExcerpt(record.text)
        record.pageTexts = [record.text]
        record.pageCount = 1
        record.isDemo = false
        XCTAssertFalse(record.summary.contains("RIGHT TIBIA"))
        let report = ReportEngine.generate(visit: visit, records: [record])
        XCTAssertEqual(report.selectedRecordIDs, [record.id])
        let source = try XCTUnwrap(report.sections.flatMap(\.sources).first)
        XCTAssertTrue(source.excerpt.contains("Implant location: RIGHT TIBIA"))
        XCTAssertTrue(source.excerpt.contains("No additional procedure documented."))
        XCTAssertEqual(source.page, 1)
        XCTAssertTrue(record.text.contains(source.excerpt))
    }
}
