// Purpose: Preserve additive browser provenance fields when native clients decode and re-encode data.
// Inputs: Fictional records and recording JSON with generated, captured and saved dates.
// Outputs: Assertions that exact metadata survives and older absent/null fields remain optional.
// Side effects: None; no storage, recording or network activity occurs.

import Foundation
import XCTest

@testable import RevaCore

// MARK: - Model roundtrips retain date provenance without deriving timestamps from legacy dates
final class MetadataRoundTripTests: XCTestCase {
    func testMedicalRecordKeepsSummaryGeneratedAtAndDateSource() throws {
        let original = MedicalRecord(
            title: "Fictional report", kind: "Notes", provider: "Synthetic", date: "2024-02-29",
            text: "Fictional source", summary: "Fictional summary")
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["summaryGeneratedAt"] = "2026-09-12T12:40:00.123Z"
        json["dateSource"] = "document"
        let decoded = try JSONDecoder().decode(
            MedicalRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.summaryGeneratedAt, "2026-09-12T12:40:00.123Z")
        XCTAssertEqual(decoded.dateSource, "document")
        XCTAssertEqual(decoded.date, "2024-02-29")
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertEqual(encoded["summaryGeneratedAt"] as? String, json["summaryGeneratedAt"] as? String)
        XCTAssertEqual(encoded["dateSource"] as? String, "document")
        for value in [nil, NSNull()] as [Any?] {
            json["summaryGeneratedAt"] = value
            json["dateSource"] = value
            let legacy = try JSONDecoder().decode(
                MedicalRecord.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(legacy.summaryGeneratedAt)
            XCTAssertNil(legacy.dateSource)
        }
    }

    func testRecordingKeepsTitleSourceAndCaptureSaveGenerationDates() throws {
        let original = VisitRecording(visitID: "", title: "Fictional discussion", duration: 60)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        let metadata = [
            "titleSource": "ai", "capturedAt": "2026-09-12T12:00:00-05:00",
            "savedAt": "2026-09-12T12:30:00.123Z", "aiSummaryGeneratedAt": "2026-09-12T12:40:00.123Z",
        ]
        json.merge(metadata) { _, new in new }
        let decoded = try JSONDecoder().decode(
            VisitRecording.self, from: JSONSerialization.data(withJSONObject: json))
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        for (key, value) in metadata { XCTAssertEqual(encoded[key] as? String, value) }
        for value in [nil, NSNull()] as [Any?] {
            for key in metadata.keys { json[key] = value }
            let legacy = try JSONDecoder().decode(
                VisitRecording.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(legacy.titleSource)
            XCTAssertNil(legacy.capturedAt)
            XCTAssertNil(legacy.savedAt)
            XCTAssertNil(legacy.aiSummaryGeneratedAt)
        }
    }
}
