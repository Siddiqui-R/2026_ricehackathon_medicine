// Purpose: Protect additive provenance metadata while retaining legacy and exact source dates.
// Inputs: Fictional snapshots, enum values and bounded ISO date/instant strings.
// Outputs: Assertions for accepted roundtrips and rejected malformed optional fields.
// Side effects: None; tests do not contact storage or providers.
import test from "node:test";
import assert from "node:assert/strict";
import { snapshot } from "./validation.mjs";
import { validMetadataDate } from "./snapshot-metadata.mjs";

// MARK: - Shared boundary vectors cover calendar rollovers and explicit time-zone offsets
const validDates = [
  "2026-09-12",
  "2024-02-29",
  "2026-09-12T12:30:00Z",
  "2026-09-12T12:30:00.123Z",
  "2026-09-12T12:30:00-05:00",
  "2026-09-12T12:30:00.123456789+05:30",
];
const invalidDates = [
  "",
  "yesterday",
  "1",
  "0000-01-01",
  "2026-02-29",
  "2026-02-30",
  "2026-13-01",
  "2026-00-01",
  "2026-01-00",
  "2026-09-12T24:00:00Z",
  "2026-09-12T12:60:00Z",
  "2026-09-12T12:30:00",
  "2026-09-12T12:30:00Z\n",
  "2026-09-12T12:30:00+25:00",
  "x".repeat(41),
];
test("metadata accepts valid ISO dates and instants without accepting rollover or relative dates", () => {
  for (const value of validDates)
    assert.equal(validMetadataDate(value), true, value);
  for (const value of invalidDates)
    assert.equal(validMetadataDate(value), false, value);
});
const example = () => ({
  schemaVersion: 1,
  profile: { id: "synthetic-owner" },
  records: [
    {
      id: "record",
      dateSource: "recorded",
      summaryGeneratedAt: "2026-09-12T12:40:00.123Z",
    },
  ],
  visits: [],
  bookings: [],
  recordings: [
    {
      id: "recording",
      titleSource: "ai",
      capturedAt: "2026-09-12T12:00:00-05:00",
      savedAt: "2026-09-12T12:30:00.123Z",
      aiSummaryGeneratedAt: "2026-09-12T12:40:00.123Z",
    },
  ],
});

// MARK: - Validate, serialize and deserialize without inferring or modifying any timestamp
test("valid and legacy snapshots retain exact metadata without mutation", () => {
  const value = example(),
    before = structuredClone(value);
  snapshot(value);
  assert.deepEqual(JSON.parse(JSON.stringify(value)), before);
  for (const nullValue of [undefined, null]) {
    const legacy = example();
    legacy.records[0] = {
      id: "record",
      dateSource: nullValue,
      summaryGeneratedAt: nullValue,
    };
    legacy.recordings[0] = {
      id: "recording",
      titleSource: nullValue,
      capturedAt: nullValue,
      savedAt: nullValue,
      aiSummaryGeneratedAt: nullValue,
    };
    assert.doesNotThrow(() => snapshot(legacy));
  }
});
test("invalid optional provenance metadata is rejected before storage", () => {
  for (const [collection, field] of [
    ["records", "dateSource"],
    ["records", "summaryGeneratedAt"],
    ["recordings", "titleSource"],
    ["recordings", "capturedAt"],
    ["recordings", "savedAt"],
    ["recordings", "aiSummaryGeneratedAt"],
  ]) {
    for (const invalid of ["unknown", 123, true, [], {}, "x".repeat(100)]) {
      const value = example();
      value[collection][0][field] = invalid;
      assert.throws(
        () => snapshot(value),
        (error) => error.status === 400,
      );
    }
  }
});
