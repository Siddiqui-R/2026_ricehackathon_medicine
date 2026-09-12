// Purpose: Protect symptom-entry validation, faithful source text, persistence, and preparation relevance.
// Inputs: Fixed-time self-reported observations, invalid variants, and the synthetic legacy snapshot.
// Outputs: XCTest assertions for source identity, optional fields, citations, and brief invalidation.
// Side effects: One test writes a temporary repository and removes it afterward; no provider calls occur.

import XCTest

@testable import RevaCore

final class SymptomEntryTests: XCTestCase {
    // MARK: - Fixed-time observation fixture

    private let now = RevaDate.parse("2026-09-12T18:00:00Z")

    private func entry() -> SymptomEntry {
        SymptomEntry(
            observedAt: "2026-09-12T02:15:00Z", timeZone: "America/Chicago", symptom: "Nausea",
            severity: "moderate", duration: "20 minutes", details: "No vomiting. Started after dinner.",
            triggers: "Not sure; I had eaten rice.", whatHelped: "Sitting down helped a little.")
    }

    // MARK: - Required fields and input validation

    func testOnlySymptomAndOccurrenceAreRequiredAndUnsetSeverityRemainsAbsent() throws {
        let input = SymptomEntry(
            observedAt: "2026-09-12T02:15:00Z", timeZone: "America/Chicago", symptom: "  Headache  ")
        let record = try input.makeRecord(now: now)
        XCTAssertEqual(record.title, "Headache")
        XCTAssertEqual(record.kind, "User symptom entry")
        XCTAssertEqual(record.provider, "Self-reported")
        XCTAssertEqual(record.status, "ready")
        XCTAssertFalse(record.isDemo)
        XCTAssertNil(record.symptomEntry?.severity)
        XCTAssertFalse(record.text.contains("Severity:"))
        XCTAssertFalse(record.text.contains("Mild"))
        XCTAssertEqual(record.summary, "Symptom: Headache")
    }

    func testInvalidDatesSeverityAndEmptySymptomCannotBecomeSources() throws {
        var input = entry()
        for symptom in ["", " \n ", String(repeating: "a", count: 121), "First\nSecond"] {
            input = entry()
            input.symptom = symptom
            XCTAssertThrowsError(try input.makeRecord(now: now), symptom)
        }
        for date in [
            "not-a-date", "2026-09-12", "2026-02-30T10:00:00Z", "2026-09-12T29:00:00Z",
            "2026-09-13T10:00:00Z",
        ] {
            input = entry()
            input.observedAt = date
            XCTAssertThrowsError(try input.makeRecord(now: now), date)
        }
        input = entry()
        input.timeZone = "invalid/zone"
        XCTAssertThrowsError(try input.makeRecord(now: now))
        input = entry()
        input.severity = "critical"
        XCTAssertThrowsError(try input.makeRecord(now: now))
        input.severity = "  MILD "
        XCTAssertEqual(try input.validated(now: now).severity, "mild")
        input.severity = "  "
        XCTAssertNil(try input.validated(now: now).severity)
    }

    // MARK: - Faithful source text and edit identity

    func testSourcePreservesExactObservationsNegationTimestampAndZone() throws {
        let input = entry()
        let record = try input.makeRecord(now: now)
        XCTAssertEqual(
            record.text,
            """
            User symptom entry
            Self-reported by the user.
            Symptom: Nausea
            Occurred at: 2026-09-12T02:15:00Z (America/Chicago)
            Severity: Moderate
            Duration: 20 minutes
            Details:
            No vomiting. Started after dinner.
            Possible triggers:
            Not sure; I had eaten rice.
            What helped:
            Sitting down helped a little.
            """)
        XCTAssertEqual(record.symptomEntry, input)
        XCTAssertEqual(record.date, "2026-09-11", "List date must be the user's local occurrence day.")
        XCTAssertNil(record.pageTexts)
        XCTAssertNil(record.sourceFilename)
        XCTAssertNil(record.summaryModel)
        XCTAssertTrue(record.tags.contains("self-reported"))
    }

    func testEditingPreservesIdentityUploadTimeNotesAndCorrectsSource() throws {
        var original = try entry().makeRecord(now: now)
        original.uploadedAt = "2026-09-12T03:00:00Z"
        original.notes = "Discuss at my next visit."
        original.version = 4
        original.summaryModel = "old-ai-summary"
        var revisedEntry = entry()
        revisedEntry.details = "Correction: no nausea after lunch; it began after dinner."
        let revised = try revisedEntry.makeRecord(existingRecord: original, now: now)
        XCTAssertEqual(revised.id, original.id)
        XCTAssertEqual(revised.uploadedAt, original.uploadedAt)
        XCTAssertEqual(revised.notes, original.notes)
        XCTAssertEqual(revised.version, original.version, "AppStore.save owns source version increments.")
        XCTAssertNil(revised.summaryModel)
        XCTAssertTrue(revised.text.contains(revisedEntry.details))
        XCTAssertFalse(revised.text.contains("No vomiting."))
        var imported = original
        imported.symptomEntry = nil
        XCTAssertThrowsError(try revisedEntry.makeRecord(existingRecord: imported, now: now))
    }

    // MARK: - Legacy decoding and durable storage

    func testLegacySnapshotAndNewEntriesRoundtripThroughDurableRepository() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = try Data(contentsOf: root.appendingPathComponent("demo/seed.json"))
        // Existing snapshots have no symptomEntry key and retain their uploaded document text.
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        var records = try XCTUnwrap(legacyJSON["records"] as? [[String: Any]])
        for i in records.indices { records[i].removeValue(forKey: "symptomEntry") }
        legacyJSON["records"] = records
        var snapshot = try JSONDecoder().decode(
            AppSnapshot.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        XCTAssertTrue(snapshot.records.allSatisfy { $0.symptomEntry == nil })
        let oldRecord = try XCTUnwrap(snapshot.records.first)
        let saved = try entry().makeRecord(now: now)
        snapshot.records.append(saved)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try LocalRepository(directory: directory).save(snapshot)
        let restored = try XCTUnwrap(LocalRepository(directory: directory).load()?.snapshot)
        XCTAssertEqual(restored.records.first, oldRecord)
        XCTAssertEqual(restored.records.last, saved)
        XCTAssertEqual(restored.records.last?.symptomEntry, entry())
    }

    // MARK: - Preparation relevance and citation invalidation

    func testRelevantEntryIsQuotedWithSelfReportedProvenanceAndEditsInvalidateBrief() throws {
        let record = try entry().makeRecord(now: now)
        var visit = Visit(
            title: "Discuss nausea", type: "Primary care", provider: "Example clinician",
            clinic: "Example clinic",
            date: "2026-09-14T16:00:00Z", concern: "Nausea after dinner", goal: "Discuss symptom timing")
        var unrelated = entry()
        unrelated.symptom = "Ear pain"
        unrelated.details = "Started this morning."
        unrelated.triggers = ""
        unrelated.whatHelped = ""
        let otherRecord = try unrelated.makeRecord(now: now)
        let report = ReportEngine.generate(visit: visit, records: [record, otherRecord])
        XCTAssertEqual(report.selectedRecordIDs, [record.id])
        let citation = try XCTUnwrap(report.sections.flatMap(\.sources).first)
        XCTAssertEqual(citation.recordID, record.id)
        XCTAssertEqual(citation.page, 0, "A typed observation must not claim a scanned source page.")
        XCTAssertEqual(citation.sourceVersion, record.version)
        XCTAssertTrue(citation.excerpt.contains("Self-reported by the user."))
        XCTAssertTrue(citation.excerpt.contains("No vomiting."))
        XCTAssertTrue(record.text.contains(citation.excerpt))
        visit.report = report
        XCTAssertFalse(ReportEngine.isStale(visit, records: [record, otherRecord]))
        var correction = entry()
        correction.details = "Nausea lasted an hour, not 20 minutes."
        let revised = try correction.makeRecord(existingRecord: record, now: now)
        XCTAssertTrue(ReportEngine.isStale(visit, records: [revised, otherRecord]))
    }
}
