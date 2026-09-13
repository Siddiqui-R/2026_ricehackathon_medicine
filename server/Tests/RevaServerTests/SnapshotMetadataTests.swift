// Purpose: Verify additive source/date/title metadata survives server persistence and rejects malformed values.
// Inputs: Fictional JSON snapshots and bounded ISO date/instant boundary vectors.
// Outputs: Assertions for legacy compatibility, exact roundtrips and validation without revision changes.
// Side effects: Creates and removes a test-owned temporary local store; no network or provider calls.

import Foundation
import Testing
import Vapor

@testable import RevaServer

// MARK: - Date vectors match the Node snapshot metadata contract
@Suite("Snapshot provenance metadata")
struct SnapshotMetadataTests {
    @Test func strictDatesAcceptOffsetsAndRejectRollover() {
        for value in [
            "2026-09-12", "2024-02-29", "2026-09-12T12:30:00Z", "2026-09-12T12:30:00.123Z",
            "2026-09-12T12:30:00-05:00", "2026-09-12T12:30:00.123456789+05:30",
        ] {
            #expect(Validation.validMetadataDate(value))
        }
        for value in [
            "", "yesterday", "1", "0000-01-01", "2026-02-29", "2026-02-30", "2026-13-01", "2026-00-01",
            "2026-01-00", "2026-09-12T24:00:00Z", "2026-09-12T12:60:00Z", "2026-09-12T12:30:00",
            "2026-09-12T12:30:00Z\n", "2026-09-12T12:30:00+25:00", String(repeating: "x", count: 41),
        ] {
            #expect(!Validation.validMetadataDate(value))
        }
    }

    @Test func metadataRoundtripPreservesExactDatesAndLegacyAbsence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reva-metadata-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let record: [String: JSONValue] = [
            "id": .string("record"), "dateSource": .string("recorded"),
            "summaryGeneratedAt": .string("2026-09-12T12:40:00.123Z"),
        ]
        let recording: [String: JSONValue] = [
            "id": .string("recording"), "titleSource": .string("ai"),
            "capturedAt": .string("2026-09-12T12:00:00-05:00"),
            "savedAt": .string("2026-09-12T12:30:00.123Z"),
            "aiSummaryGeneratedAt": .string("2026-09-12T12:40:00.123Z"),
        ]
        let value = example(record: record, recording: recording)
        func writeOriginal() async throws {
            let store = try LocalFileStore(directory: directory)
            #expect(try await store.putState(owner: "synthetic-owner", baseRevision: 0, snapshot: value) == 1)
            #expect(try await store.getState(owner: "synthetic-owner").snapshot == value)
        }
        try await writeOriginal()
        let reopened = try LocalFileStore(directory: directory)
        #expect(try await reopened.getState(owner: "synthetic-owner").snapshot == value)
        for metadata in [
            [:] as [String: JSONValue],
            [
                "dateSource": .null, "summaryGeneratedAt": .null, "titleSource": .null, "capturedAt": .null,
                "savedAt": .null, "aiSummaryGeneratedAt": .null,
            ],
        ] {
            try Validation.snapshot(example(record: metadata, recording: metadata))
        }
    }

    @Test func invalidMetadataFailsBeforeStoreRevisionChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reva-metadata-reject-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFileStore(directory: directory)
        let original = example()
        _ = try await store.putState(owner: "owner", baseRevision: 0, snapshot: original)
        for (collection, field) in [
            ("records", "dateSource"), ("records", "summaryGeneratedAt"), ("recordings", "titleSource"),
            ("recordings", "capturedAt"), ("recordings", "savedAt"), ("recordings", "aiSummaryGeneratedAt"),
        ] {
            for invalid: JSONValue in [
                .string("unknown"), .integer(123), .bool(true), .array([]), .object([:]),
                .string(String(repeating: "x", count: 100)),
            ] {
                let metadata = [field: invalid]
                let value = example(
                    record: collection == "records" ? metadata : [:],
                    recording: collection == "recordings" ? metadata : [:])
                await #expect(throws: Abort.self) {
                    try await store.putState(owner: "owner", baseRevision: 1, snapshot: value)
                }
            }
        }
        #expect(try await store.getState(owner: "owner").revision == 1)
        #expect(try await store.getState(owner: "owner").snapshot == original)
    }

    // MARK: - Generic snapshots preserve unrelated fields and need no clinical fixture
    private func example(record: [String: JSONValue] = [:], recording: [String: JSONValue] = [:]) -> JSONValue
    {
        .object([
            "schemaVersion": .integer(1), "profile": .object(["id": .string("synthetic-owner")]),
            "records": .array([.object(record)]), "recordings": .array([.object(recording)]),
            "visits": .array([]), "bookings": .array([]),
        ])
    }
}
