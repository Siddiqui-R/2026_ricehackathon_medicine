// Purpose: Preserve recording compatibility and full transcript evidence for appointment summaries.
// Inputs: Synthetic recording metadata, transcript segments, and legacy JSON.
// Outputs: Assertions for optional AI fields, exact source text, and separate notes.
// Side effects: None; no recordings or connected providers are used.

import Foundation
import XCTest

@testable import RevaCore

// MARK: - Appointment recording contract
final class AppointmentRecordingTests: XCTestCase {
    func testStandaloneRecordingDoesNotRequireAnAppointment() throws {
        let profile = PatientProfile(id: "profile", name: "Fictional Patient", dateOfBirth: "1990-01-01", initials: "FP", allergies: [], medications: [], conditions: [], isDemo: true)
        var snapshot = AppSnapshot(profile: profile, records: [], visits: [], recordings: [
            VisitRecording(visitID: "", title: "Session", duration: 60, segments: [], summary: "")
        ])
        XCTAssertNoThrow(try snapshot.validate())
        snapshot.recordings[0].visitID = "missing"
        XCTAssertThrowsError(try snapshot.validate())
    }

    func testLegacyRecordingDecodesWithoutAISummaryAndPreservesNotes() throws {
        let legacy = Data(
            #"{"id":"old-recording","visitID":"visit","title":"Appointment","createdAt":"2026-09-12T12:00:00Z","duration":60,"segments":[],"summary":"My own notes","isSample":false,"status":"saved"}"#
                .utf8)
        let recording = try JSONDecoder().decode(VisitRecording.self, from: legacy)
        XCTAssertEqual(recording.summary, "My own notes")
        XCTAssertNil(recording.aiSummary)
        XCTAssertNil(recording.aiSummaryModel)
        XCTAssertNil(recording.aiSummaryGeneratedAt)
        XCTAssertFalse(recording.hasAISummary)
    }

    func testFullTranscriptAndDerivedSummaryRoundTripSeparately() throws {
        var recording = VisitRecording(
            visitID: "visit", title: "Appointment", duration: 90,
            segments: [
                .init(
                    id: "one", speaker: "Speaker", start: 0, end: 5,
                    text: "Exact words: café, 0.25, and 12 mg."),
                .init(
                    id: "two", speaker: "Speaker", start: 65, end: 90,
                    text: "Later source line.\nUnchanged second line."),
            ], summary: "My separate notes", aiSummary: "Derived overview", aiSummaryModel: "synthetic-model",
            aiSummaryGeneratedAt: "2026-09-12T12:00:00Z")
        XCTAssertEqual(
            recording.transcriptText,
            "[0:00–0:05] Speaker: Exact words: café, 0.25, and 12 mg.\n\n[1:05–1:30] Speaker: Later source line.\nUnchanged second line."
        )
        XCTAssertTrue(recording.hasAISummary)
        XCTAssertEqual(
            try JSONDecoder().decode(VisitRecording.self, from: JSONEncoder().encode(recording)), recording)
        recording.clearAISummary()
        XCTAssertNil(recording.aiSummary)
        XCTAssertNil(recording.aiSummaryModel)
        XCTAssertNil(recording.aiSummaryGeneratedAt)
        XCTAssertEqual(recording.summary, "My separate notes")
        XCTAssertEqual(recording.segments.count, 2)
    }
}
