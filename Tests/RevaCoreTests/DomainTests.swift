import XCTest
@testable import RevaCore

final class DomainTests: XCTestCase {
    func fixture() throws -> AppSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("demo/seed.json")))
    }
    func testDistinctVisitEvidencePinsAndSourceVersions() throws {
        let data = try fixture(); try data.validate()
        let ortho = try XCTUnwrap(data.visits.first { $0.type == "Orthopedics" })
        let primary = try XCTUnwrap(data.visits.first { $0.id == "demo-visit-primary-20260915" })
        let orthopedic = ReportEngine.generate(visit: ortho, records: data.records)
        let general = ReportEngine.generate(visit: primary, records: data.records)
        XCTAssertTrue(orthopedic.selectedRecordIDs.contains("demo-record-tibia-procedure"))
        XCTAssertFalse(orthopedic.selectedRecordIDs.contains("demo-record-ear-infection"))
        XCTAssertTrue(general.selectedRecordIDs.contains("demo-record-ecg"))
        XCTAssertTrue(general.selectedRecordIDs.contains("demo-record-labs"))
        XCTAssertNotEqual(Set(orthopedic.selectedRecordIDs), Set(general.selectedRecordIDs))
        var pinned = ortho; pinned.pinnedRecordIDs = ["demo-record-ear-infection"]
        XCTAssertTrue(ReportEngine.generate(visit: pinned, records: data.records).selectedRecordIDs.contains("demo-record-ear-infection"))
        for section in orthopedic.sections { for source in section.sources {
            let record = try XCTUnwrap(data.records.first { $0.id == source.recordID })
            XCTAssertEqual(source.sourceVersion, record.version)
            XCTAssertGreaterThan(source.page, 0); XCTAssertLessThanOrEqual(source.page, record.pageCount)
            XCTAssertFalse(source.excerpt.isEmpty)
        } }
    }
    func testStalenessAfterSourceChangeDeletionAndNewRecord() throws {
        var data = try fixture(); var visit = data.visits[0]
        visit.report = ReportEngine.generate(visit: visit, records: data.records)
        XCTAssertFalse(ReportEngine.isStale(visit, records: data.records))
        data.records[0].text += "\nA corrected source fact."; data.records[0].version += 1
        XCTAssertTrue(ReportEngine.isStale(visit, records: data.records))
        visit.report = ReportEngine.generate(visit: visit, records: data.records)
        data.records.removeFirst(); XCTAssertTrue(ReportEngine.isStale(visit, records: data.records))
        let oldQuestions = visit.questions; visit.notes = "My own note."
        let renewed = ReportEngine.generate(visit: visit, records: data.records)
        XCTAssertEqual(renewed.questions, oldQuestions); XCTAssertEqual(renewed.notes, "My own note.")
    }
    func testAtomicPersistenceRecoveryAndAttachmentRoundtrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = LocalRepository(directory: root); var data = try fixture()
        try repo.save(data)
        data.records[0].notes = "Persist me"; try repo.save(data)
        XCTAssertEqual(try LocalRepository(directory: root).load()?.snapshot.records[0].notes, "Persist me")
        let bytes = Data([0, 1, 255, 42]); _ = try repo.storeAttachment(bytes, filename: "source.pdf")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(repo.attachment("source.pdf"))), bytes)
        XCTAssertThrowsError(try repo.storeAttachment(bytes, filename: "../escape"))
        try Data("broken json".utf8).write(to: root.appendingPathComponent("state.json"))
        XCTAssertTrue(try XCTUnwrap(repo.load()).recovered)
        XCTAssertEqual(try repo.load()?.snapshot.records[0].notes, try fixture().records[0].notes)
    }
    func testBookingConfirmationIsIdempotentAndBounded() throws {
        var data = try fixture(); let visit = data.visits[0]
        let request = BookingRequest(visitID: visit.id, clinic: "Demo clinic", phone: "7135550100", reason: "Follow-up", earliest: visit.date, latest: visit.date, timeZone: visit.timeZone, preferences: "", status: "proposed")
        try BookingEngine.validate(request); data.bookings.append(request)
        let count = data.visits.count
        try BookingEngine.confirm(id: request.id, snapshot: &data); try BookingEngine.confirm(id: request.id, snapshot: &data)
        XCTAssertEqual(data.visits.count, count); XCTAssertEqual(data.bookings[0].confirmedVisitID, visit.id)
        var invalid = request; invalid.latest = "2000-01-01T00:00:00Z"
        XCTAssertThrowsError(try BookingEngine.validate(invalid))
    }
    func testSnapshotRejectsDuplicateIDsAndUnsafeAttachments() throws {
        var data = try fixture(); data.records.append(data.records[0]); XCTAssertThrowsError(try data.validate())
        data = try fixture(); data.records[0].sourceFilename = "../../real-data"; XCTAssertThrowsError(try data.validate())
    }
    func testLocalExcerptDoesNotInventFactsOrDropNegation() {
        let text = "No chest pain.\nDose: 2.5 mg\nPotassium 4.1 mmol/L"
        XCTAssertEqual(ReportEngine.localExcerpt(text), text)
    }
    func testQuestionAuthorityAndEquivalentDateFormatting() throws {
        let data = try fixture(); var visit = data.visits[0]
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
}
