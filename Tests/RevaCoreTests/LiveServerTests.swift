// Purpose: Exercise the real native client against the opt-in temporary localhost Vapor test server.
// Inputs: Harness-supplied listener and owner tokens plus checked-in synthetic snapshots and source files.
// Outputs: XCTest assertions and a verification message for auth, revisions, attachments, and owner isolation.
// Side effects: When explicitly enabled, sends real loopback requests that mutate test-owner state and attachments; invalidates its session afterward.

import Foundation
import XCTest

@testable import RevaCore

/// Real URLSession requests, enabled only by scripts/test_client_server.py.
final class LiveServerTests: XCTestCase {
    // MARK: - Fixture location and expected failure helpers

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func expectEmpty(
        _ client: ServerClient, revision: Int, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await client.pull()
            XCTFail("Expected missing state with revision \(revision).", file: file, line: line)
        } catch {
            guard case ServerFailure.empty(let actual) = error else {
                return XCTFail("Expected a missing-state response, got \(error).", file: file, line: line)
            }
            XCTAssertEqual(actual, revision, file: file, line: line)
        }
    }

    private func expectConflict(
        _ client: ServerClient, snapshot: AppSnapshot, revision: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await client.push(snapshot, revision: revision)
            XCTFail("Expected a stale-revision conflict.", file: file, line: line)
        } catch {
            guard case ServerFailure.conflict = error else {
                return XCTFail("Expected a conflict response, got \(error).", file: file, line: line)
            }
        }
    }

    private func expectHTTPFailure<T>(
        _ status: Int, operation: () async throws -> T,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected HTTP \(status).", file: file, line: line)
        } catch {
            guard case ServerFailure.response(let actual) = error else {
                return XCTFail("Expected HTTP status failure, got \(error).", file: file, line: line)
            }
            XCTAssertEqual(actual, status, file: file, line: line)
        }
    }

    // MARK: - Opt-in localhost integration

    func testNativeURLSessionClientAgainstLocalVapor() async throws {
        // MARK: - Harness gate and isolated owner sessions

        let environment = ProcessInfo.processInfo.environment
        guard environment["REVA_RUN_LIVE_CLIENT_TESTS"] == "1" else {
            throw XCTSkip(
                "Run python3 scripts/test_client_server.py to enable the temporary localhost server integration test."
            )
        }
        let address = try XCTUnwrap(environment["REVA_LIVE_TEST_URL"])
        let baseURL = try XCTUnwrap(URL(string: address))
        guard baseURL.scheme == "http", baseURL.host == "127.0.0.1", baseURL.port != nil else {
            return XCTFail("Live tests require an explicit temporary 127.0.0.1 HTTP listener.")
        }
        let token = try XCTUnwrap(environment["REVA_LIVE_TEST_TOKEN"])
        let otherToken = try XCTUnwrap(environment["REVA_LIVE_TEST_OTHER_TOKEN"])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = try ServerClient(baseURL: baseURL, token: token, session: session)
        let otherOwner = try ServerClient(baseURL: baseURL, token: otherToken, session: session)
        let invalidIdentity = try ServerClient(
            baseURL: baseURL, token: "unconfigured-synthetic-token", session: session)

        // MARK: - Initial health, authentication, and owner isolation

        let health = try await client.health()
        XCTAssertEqual(health, "Connected · local")
        await expectEmpty(client, revision: 0)
        await expectEmpty(otherOwner, revision: 0)
        await expectHTTPFailure(401) { try await invalidIdentity.pull() }

        // MARK: - Snapshot round-trip and stale revision rejection

        let seed = try JSONDecoder().decode(
            AppSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("demo/seed.json")))
        try seed.validate()
        XCTAssertTrue(seed.profile.isDemo)
        XCTAssertTrue(seed.records.allSatisfy(\.isDemo))
        XCTAssertGreaterThan(seed.records.count, 1)
        XCTAssertGreaterThan(seed.visits.count, 1)
        let firstRevision = try await client.push(seed, revision: 0)
        XCTAssertEqual(firstRevision, 1)
        let firstRead = try await client.pull()
        XCTAssertEqual(firstRead.revision, firstRevision)
        XCTAssertEqual(firstRead.snapshot, seed)
        await expectEmpty(otherOwner, revision: 0)

        // Populate domains which the reset fixture intentionally leaves empty.
        var edited = seed
        edited.records[0].notes = "Synthetic integration edit — preserve Unicode and source content."
        edited.visits[0].questions.append("Synthetic integration preparation question?")
        edited.visits[0].report = ReportEngine.generate(visit: edited.visits[0], records: edited.records)
        let visit = edited.visits[0]
        edited.bookings.append(
            BookingRequest(
                id: "synthetic-live-test-booking", visitID: visit.id,
                clinic: visit.clinic, phone: "+1 202 555 0100",
                reason: "Fictional local integration test only",
                earliest: "2026-09-15T14:00:00Z", latest: "2026-09-18T18:00:00Z", timeZone: visit.timeZone,
                preferences: "No real call", status: "draft", scenario: "Appointment available"))
        let sampleRecording = try JSONDecoder().decode(
            VisitRecording.self,
            from: Data(contentsOf: root.appendingPathComponent("demo/sample-transcript.json")))
        XCTAssertTrue(sampleRecording.isSample)
        XCTAssertNil(sampleRecording.audioFilename)
        edited.recordings.append(sampleRecording)
        try edited.validate()
        let secondRevision = try await client.push(edited, revision: firstRevision)
        XCTAssertEqual(secondRevision, 2)
        await expectConflict(client, snapshot: seed, revision: firstRevision)
        let updatedRead = try await client.pull()
        XCTAssertEqual(updatedRead.revision, secondRevision)
        XCTAssertEqual(updatedRead.snapshot, edited)
        XCTAssertFalse(updatedRead.snapshot.bookings.isEmpty)
        XCTAssertFalse(updatedRead.snapshot.recordings.isEmpty)
        XCTAssertNotNil(updatedRead.snapshot.visits[0].report)

        // MARK: - Original attachment bytes and per-owner access

        let sourceDirectory = root.appendingPathComponent("demo/sources", isDirectory: true)
            .resolvingSymlinksInPath()
        var uploadedIDs: [String] = []
        var representativeBytes: Data?
        for record in seed.records {
            let filename = try XCTUnwrap(record.sourceFilename)
            guard filename.hasPrefix("reva-synthetic-"), AppSnapshot.safeFilename(filename) else {
                return XCTFail("Integration source is not an explicit flat synthetic fixture.")
            }
            let sourceURL = sourceDirectory.appendingPathComponent(filename).resolvingSymlinksInPath()
            guard sourceURL.path.hasPrefix(sourceDirectory.path + "/") else {
                return XCTFail("Synthetic source path escaped its fixture directory.")
            }
            let bytes = try Data(contentsOf: sourceURL)
            XCTAssertFalse(bytes.isEmpty)
            let id = ServerClient.attachmentID(for: filename)
            let metadata = ServerClient.attachmentMetadataName(filename)
            XCTAssertEqual(id.count, 64)
            try await client.uploadAttachment(
                id: id, filename: metadata, data: bytes, type: record.mimeType ?? "application/octet-stream")
            let downloaded = try await client.attachment(id: id)
            XCTAssertEqual(downloaded, bytes, "Original bytes changed for \(filename).")
            await expectHTTPFailure(404) { try await otherOwner.attachment(id: id) }
            uploadedIDs.append(id)
            if record.mimeType == "application/pdf" { representativeBytes = bytes }
        }

        // A Unicode filename becomes a safe metadata header while the ID keeps its exact original UTF-8 identity.
        let unicodeName = "Synthetic café source (copy).pdf"
        let unicodeID = ServerClient.attachmentID(for: unicodeName)
        let safeMetadata = ServerClient.attachmentMetadataName(unicodeName)
        XCTAssertNotEqual(safeMetadata, unicodeName)
        let pdfBytes = try XCTUnwrap(representativeBytes)
        try await client.uploadAttachment(
            id: unicodeID, filename: safeMetadata, data: pdfBytes, type: "application/pdf")
        var metadataRequest = URLRequest(url: baseURL.appendingPathComponent("v1/attachments/" + unicodeID))
        metadataRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (metadataBytes, metadataResponse) = try await session.data(for: metadataRequest)
        let httpResponse = try XCTUnwrap(metadataResponse as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "X-Filename"), safeMetadata)
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "application/pdf")
        XCTAssertEqual(metadataBytes, pdfBytes)
        try await otherOwner.deleteAttachment(id: unicodeID)
        let isolatedBytes = try await client.attachment(id: unicodeID)
        XCTAssertEqual(isolatedBytes, pdfBytes)
        try await client.deleteAttachment(id: unicodeID)
        await expectHTTPFailure(404) { try await client.attachment(id: unicodeID) }
        try await client.deleteAttachment(id: unicodeID)

        // MARK: - Deletion tombstones and explicit restoration

        let otherDeletedRevision = try await otherOwner.deleteState()
        XCTAssertEqual(otherDeletedRevision, 0)
        let preservedState = try await client.pull()
        XCTAssertEqual(preservedState.snapshot, edited)
        let deletedRevision = try await client.deleteState()
        XCTAssertEqual(deletedRevision, 3)
        await expectEmpty(client, revision: deletedRevision)
        for id in uploadedIDs { await expectHTTPFailure(404) { try await client.attachment(id: id) } }
        let repeatedDeleteRevision = try await client.deleteState()
        XCTAssertEqual(repeatedDeleteRevision, deletedRevision)
        await expectConflict(client, snapshot: edited, revision: secondRevision)
        let restoredRevision = try await client.push(seed, revision: deletedRevision)
        XCTAssertEqual(restoredRevision, 4)
        let restored = try await client.pull()
        XCTAssertEqual(restored.revision, restoredRevision)
        XCTAssertEqual(restored.snapshot, seed)
        await expectEmpty(otherOwner, revision: 0)
        print(
            "Verified real client/server health, auth, full snapshot domains, stale conflict, \(uploadedIDs.count) original sources, Unicode metadata, isolation and deletion tombstones."
        )
    }
}
