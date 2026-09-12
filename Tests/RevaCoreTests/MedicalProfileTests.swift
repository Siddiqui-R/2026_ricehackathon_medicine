import XCTest
@testable import RevaCore

final class MedicalProfileTests: XCTestCase {
    func testLegacyProfileDecodesWithoutNewMedicalFields() throws {
        let json = #"{"id":"legacy-profile","name":"Sam Rivera","dateOfBirth":"1991-05-10","initials":"SR","allergies":[],"medications":["Fictional sample"],"conditions":[],"isDemo":true}"#
        let profile = try JSONDecoder().decode(PatientProfile.self, from: Data(json.utf8))
        XCTAssertNil(profile.surgeriesAndImplants)
        XCTAssertNil(profile.careNotes)
        XCTAssertEqual(profile.allergies, [])
        XCTAssertEqual(profile.dateOfBirth, "1991-05-10")
    }

    func testMedicalProfileUpdatesPersistWithoutChangingOtherHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(directory: directory)
        var snapshot = try fixture()
        let records = snapshot.records
        let visits = snapshot.visits
        try repository.save(snapshot)
        snapshot.profile.name = "Sam Rivera"
        snapshot.profile.initials = "SR"
        snapshot.profile.allergies = ["Fictional allergen — rash"]
        snapshot.profile.medications = ["Fictional medication — sample instructions"]
        snapshot.profile.conditions = ["Fictional ongoing condition"]
        snapshot.profile.surgeriesAndImplants = ["Fictional right tibia implant, 2019"]
        snapshot.profile.careNotes = "Written instructions are helpful."
        try repository.save(snapshot)

        let loaded = try XCTUnwrap(LocalRepository(directory: directory).load()?.snapshot)
        XCTAssertEqual(loaded.profile, snapshot.profile)
        XCTAssertEqual(loaded.records, records)
        XCTAssertEqual(loaded.visits, visits)
    }

    func testEmptyProfileListsRemainUnspecifiedAfterSaving() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var snapshot = try fixture()
        snapshot.profile.dateOfBirth = ""
        snapshot.profile.allergies = []
        snapshot.profile.medications = []
        snapshot.profile.conditions = []
        snapshot.profile.surgeriesAndImplants = nil
        snapshot.profile.careNotes = nil
        try LocalRepository(directory: directory).save(snapshot)

        let saved = try XCTUnwrap(LocalRepository(directory: directory).load()?.snapshot.profile)
        XCTAssertEqual(saved.allergies, [])
        XCTAssertEqual(saved.medications, [])
        XCTAssertEqual(saved.dateOfBirth, "")
        XCTAssertNil(saved.surgeriesAndImplants)
        XCTAssertNil(saved.careNotes)
    }

    private func fixture() throws -> AppSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("demo/seed.json")))
    }
}
