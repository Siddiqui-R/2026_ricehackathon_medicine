import Foundation
import XCTest

@testable import RevaCore

final class NativeParityTests: XCTestCase {
    private var user: NativeAccountUser {
        .init(
            id: "native-test", email: "judge@example.test", name: "Test Judge",
            createdAt: "2026-09-12T12:00:00Z")
    }
    private func snapshot() -> AppSnapshot {
        var result = NativeAccount.emptySnapshot(user)
        result.records = [
            .init(
                id: "report", title: "Original report", kind: "Notes", provider: "", date: "2026-09-12",
                text: "No fever.", summary: "No fever.")
        ]
        return result
    }
    private func generated(_ text: String = "Test allergy") -> NativeProfileResult {
        .init(
            allergies: [.init(text: text, recordIDs: ["report"])], medications: [], conditions: [],
            surgeriesAndImplants: [], careNotes: [], model: "test-model")
    }
    func testPasswordPolicyAndAccountIsolation() throws {
        XCTAssertNil(NativeAccount.passwordProblem("Strong1!"))
        for value in [
            "Short1!", "lowercase1!", "NoNumber!", "NoSymbol123", "Strong1!\n",
            String(repeating: "A", count: 71) + "1!",
        ] {
            XCTAssertNotNil(NativeAccount.passwordProblem(value), value)
        }
        let empty = NativeAccount.emptySnapshot(user)
        try empty.validate()
        XCTAssertFalse(empty.profile.isDemo)
        XCTAssertEqual(empty.profile.initials, "TJ")
        XCTAssertTrue(empty.records.isEmpty && empty.visits.isEmpty && empty.recordings.isEmpty)
        XCTAssertNotEqual(NativeAccount.directoryName(user.id), NativeAccount.directoryName("other"))
        XCTAssertFalse(NativeAccount.directoryName("../../unsafe").contains("/"))
    }
    func testSectionEditingPreservesOtherSectionsAndRejectsOverlappingEdits() throws {
        let original = snapshot().profile
        var draft = original
        var current = original
        draft.allergies = ["New allergy"]
        current.medications = ["New medication"]
        let edited = try NativeProfileEditing.apply(
            original: original, draft: draft, current: current, field: .allergies)
        XCTAssertEqual(edited.allergies, draft.allergies)
        XCTAssertEqual(edited.medications, current.medications)
        current.allergies = ["Other device’s edit"]
        XCTAssertThrowsError(
            try NativeProfileEditing.apply(
                original: original, draft: draft, current: current, field: .allergies))
    }
    func testProfileSignatureMatchesBrowserJSONIncludingUnicodeAndEscapes() throws {
        let sources = [
            NativeProfileSource(
                id: "record-α", version: 2, title: "A / B \"source\"", date: "2026-09-12",
                text: "No fever.\nCafé 😀")
        ]
        // Generated independently with Node createHash('sha256').update(JSON.stringify(sources)).
        XCTAssertEqual(
            try NativeMedicalProfile.signature(sources),
            "026bf789c62f716369b550758e6cd71ae9b0dda10041eac74a2ad37af19d39c1")
    }
    func testProfileCorrectionsRemainSuppressedWhenAIRephrasesThem() throws {
        var profile = snapshot().profile
        profile.medications = ["My manual detail"]
        profile = NativeMedicalProfile.apply(generated(), to: profile, signature: "first")
        profile.allergies = ["Patient correction"]
        let refreshed = NativeMedicalProfile.apply(
            generated("Rephrased test allergy"), to: profile, signature: "second")
        XCTAssertEqual(refreshed.allergies, ["Patient correction"])
        XCTAssertEqual(refreshed.medications, ["My manual detail"])
        XCTAssertEqual(refreshed.aiMedicalHistory?.suppressedRecordIDs?["allergies"], ["report"])
        var invalid = generated()
        invalid.allergies[0].recordIDs = ["invented-source"]
        XCTAssertThrowsError(
            try NativeMedicalProfile.validate(invalid, sources: NativeMedicalProfile.sources(snapshot())))
    }
    func testDisjointCrossDeviceEditsMergeWithoutRecovery() throws {
        let base = snapshot()
        var local = base
        var remote = base
        local.records[0].notes = "Local notes"
        remote.records[0].title = "Remote title"
        local.profile.allergies = ["Local allergy"]
        remote.profile.medications = ["Remote medication"]
        let merged = try NativeSnapshotMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.recovered, 0)
        XCTAssertEqual(merged.snapshot.records[0].notes, "Local notes")
        XCTAssertEqual(merged.snapshot.records[0].title, "Remote title")
        XCTAssertEqual(merged.snapshot.profile.allergies, ["Local allergy"])
        XCTAssertEqual(merged.snapshot.profile.medications, ["Remote medication"])
    }
    func testConflictingEditsKeepBothAndDoNotDuplicateOnRetry() throws {
        let base = snapshot()
        var local = base
        var remote = base
        local.records[0].text = "Local corrected original"
        remote.records[0].text = "Remote corrected original"
        let first = try NativeSnapshotMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(first.recovered, 1)
        XCTAssertEqual(
            Set(first.snapshot.records.map(\.text)),
            ["Local corrected original", "Remote corrected original"])
        let retry = try NativeSnapshotMerge.merge(base: base, local: local, remote: first.snapshot)
        XCTAssertEqual(retry.recovered, 0)
        XCTAssertEqual(retry.snapshot.records.count, 2)
    }
    func testDeletionWinsOverUnchangedButPreservesNewEdits() throws {
        let base = snapshot()
        var local = base
        var remote = base
        remote.records = []
        XCTAssertTrue(
            try NativeSnapshotMerge.merge(base: base, local: local, remote: remote).snapshot.records.isEmpty)
        local.records[0].notes = "Keep this new note"
        XCTAssertEqual(
            try NativeSnapshotMerge.merge(base: base, local: local, remote: remote).snapshot.records[0].notes,
            "Keep this new note")
    }
    func testRecoveredRecordingsAndTranscriptsKeepTheirRecoveredParents() throws {
        var base = snapshot()
        base.visits = [
            .init(
                id: "visit", title: "Visit", type: "Primary care", provider: "", clinic: "",
                date: "2026-09-12", concern: "", goal: "")
        ]
        base.recordings = [.init(id: "audio", visitID: "visit", title: "Session", duration: 3)]
        base.records[0].sourceRecordingID = "audio"
        var local = base
        var remote = base
        local.visits[0].title = "Local visit"
        remote.visits[0].title = "Remote visit"
        local.recordings[0].title = "Local session"
        remote.recordings[0].title = "Remote session"
        local.records[0].title = "Local transcript"
        remote.records[0].title = "Remote transcript"
        let merged = try NativeSnapshotMerge.merge(base: base, local: local, remote: remote).snapshot
        let visit = try XCTUnwrap(merged.visits.first { $0.id != "visit" })
        let audio = try XCTUnwrap(merged.recordings.first { $0.id != "audio" })
        let report = try XCTUnwrap(merged.records.first { $0.id != "report" })
        XCTAssertEqual(audio.visitID, visit.id)
        XCTAssertEqual(report.sourceRecordingID, audio.id)
    }
    func testGeneratedFactsCannotUndoCorrectionDuringSync() throws {
        var base = snapshot()
        base.profile = NativeMedicalProfile.apply(generated(), to: base.profile, signature: "initial")
        var local = base
        var remote = base
        local.profile.allergies = ["Reviewed correction"]
        remote.profile = NativeMedicalProfile.apply(generated(), to: remote.profile, signature: "refreshed")
        let merged = try NativeSnapshotMerge.merge(base: base, local: local, remote: remote).snapshot
        XCTAssertEqual(merged.profile.allergies, ["Reviewed correction"])
        XCTAssertEqual(merged.profile.aiMedicalHistory?.suppressedRecordIDs?["allergies"], ["report"])
    }
    func testBriefUsesProfileAndReportsWithoutCreatingAppointment() throws {
        let source = snapshot()
        let (visit, records) = try NativeVisitBrief.inputs(
            snapshot: source, type: "Primary care", concern: "No new symptoms",
            questions: ["What should I ask?"])
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.kind, "Profile")
        let result = AIPreparation(
            overview: "Discuss the source report.", questions: ["What should I ask?"],
            selectedRecordIDs: ["report"], model: "gemini-flash-lite-latest")
        let brief = try NativeVisitBrief.checked(
            snapshot: source, visit: visit, sources: records, result: result)
        XCTAssertEqual(brief.snapshot, source)
        XCTAssertTrue(source.visits.isEmpty)
        for model in ["gemini-flash-lite-latest", "gemini-3.5-flash-lite", "gemini-configured-model"] {
            var attributed = result
            attributed.model = model
            XCTAssertEqual(
                try NativeVisitBrief.checked(
                    snapshot: source, visit: visit, sources: records, result: attributed
                ).model,
                model)
        }
        for model in ["", "   ", String(repeating: "x", count: 101), "gemini\0invalid"] {
            var invalidModel = result
            invalidModel.model = model
            XCTAssertThrowsError(
                try NativeVisitBrief.checked(
                    snapshot: source, visit: visit, sources: records, result: invalidModel))
        }
        var invalid = result
        invalid.selectedRecordIDs = ["invented"]
        XCTAssertThrowsError(
            try NativeVisitBrief.checked(snapshot: source, visit: visit, sources: records, result: invalid))
    }
}
