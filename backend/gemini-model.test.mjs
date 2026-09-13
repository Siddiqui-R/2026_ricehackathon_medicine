// Purpose: Keep every Gemini operation on one latest Flash primary model resolver.
// Inputs: Empty, prior-default and explicitly overridden environment values plus fictional records.
// Outputs: Assertions for discovery, request URLs and returned model attribution.
// Side effects: Test-process environment only; all provider traffic is mocked.
import test from "node:test";
import assert from "node:assert/strict";
import { gemini, providerStatus } from "./providers.mjs";

// MARK: - Legacy deployment defaults migrate; intentional alternative models remain global overrides
test("summaries, preparation and profile share the latest alias and legacy-default migration", async () => {
  const previousKey = process.env.GEMINI_API_KEY;
  const previousModel = process.env.GEMINI_MODEL;
  const record = {
    id: "report",
    version: 1,
    title: "Fictional note",
    date: "2026-09-12",
    text: "Fictional source.",
  };
  const operations = [
    [
      "summarize",
      { recordID: record.id, title: record.title, text: record.text },
      { summary: "Fictional summary." },
    ],
    [
      "prepare",
      {
        visit: {
          id: "visit",
          type: "Follow-up",
          concern: "Review source",
          goal: "Prepare",
          questions: [],
        },
        records: [{ ...record, summary: "" }],
      },
      {
        overview: "Reason: Review source.",
        questions: [],
        selectedRecordIDs: [record.id],
      },
    ],
    [
      "profile",
      { records: [record] },
      {
        allergies: [],
        medications: [],
        conditions: [],
        surgeriesAndImplants: [],
        careNotes: [],
      },
    ],
  ];
  process.env.GEMINI_API_KEY = "fictional-model-test-key";
  try {
    for (const configured of [
      undefined,
      "",
      "   ",
      "gemini-3.8-flash",
      " gemini-3.8-flash ",
      "gemini-3.5-flash-lite",
      " gemini-3.5-flash-lite ",
      "gemini-flash-lite-latest",
      " gemini-custom-model ",
    ]) {
      if (configured === undefined) delete process.env.GEMINI_MODEL;
      else process.env.GEMINI_MODEL = configured;
      const expected = configured?.includes("custom")
        ? "gemini-custom-model"
        : "gemini-flash-latest";
      assert.equal(providerStatus().gemini.model, expected);
      for (const [operation, input, output] of operations) {
        const result = await gemini(operation, input, async (url) => {
          assert.equal(
            new URL(url).pathname,
            `/v1beta/models/${expected}:generateContent`,
          );
          return new Response(
            JSON.stringify({
              candidates: [
                {
                  finishReason: "STOP",
                  content: { parts: [{ text: JSON.stringify(output) }] },
                },
              ],
            }),
          );
        });
        assert.equal(result.model, expected);
      }
    }
  } finally {
    if (previousKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previousKey;
    if (previousModel === undefined) delete process.env.GEMINI_MODEL;
    else process.env.GEMINI_MODEL = previousModel;
  }
});
