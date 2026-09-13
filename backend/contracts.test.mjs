// Purpose: Check strict input/output validation with fictional fixtures and a mocked provider.
// Inputs: Fictional DTOs and controlled HTTP responses.
// Outputs: Validation assertions.
// Side effects: Test-process environment only; no external requests.
import test from "node:test";
import assert from "node:assert/strict";
import { snapshot, credentials, preparationInput } from "./validation.mjs";
import { gemini, scribeResult } from "./providers.mjs";
// MARK: - Source and provider contract fixtures
const source = {
  recordID: "source-1",
  title: "Fictional note",
  text: "The fictional patient reported no pain.",
};
test("rejects invalid aggregate, missing credentials and duplicate candidate identities", () => {
  assert.throws(() =>
    snapshot({
      schemaVersion: 1,
      profile: {},
      records: [],
      visits: [],
      bookings: [],
      recordings: [],
    }),
  );
  assert.throws(() => credentials({ email: "bad", password: "test-password" }));
  assert.throws(() =>
    credentials({ email: "a@example.com", password: "short" }),
  );
  assert.doesNotThrow(() =>
    credentials({ email: "a@example.com", password: "Valid1!x" }),
  );
  assert.throws(() =>
    credentials({ email: "a@example.com", password: "lowercase1!" }),
  );
  assert.throws(() =>
    credentials({ email: "a@example.com", password: "NoNumbers!" }),
  );
  assert.throws(() =>
    credentials({ email: "a@example.com", password: "NoSymbol123" }),
  );
  assert.throws(() =>
    preparationInput({
      visit: {
        id: "visit",
        type: "test",
        concern: "test",
        goal: "",
        questions: [],
      },
      records: [{ id: "duplicate" }, { id: "duplicate" }],
    }),
  );
});
test("Gemini accepts exact source summaries and rejects truncated or injected output fields", async () => {
  process.env.GEMINI_API_KEY = "fictional-test-key";
  const mock =
    (object, finishReason = "STOP") =>
    async (url, options) => {
      assert.equal(new URL(url).hostname, "generativelanguage.googleapis.com");
      assert.equal(options.redirect, "error");
      return new Response(
        JSON.stringify({
          candidates: [
            {
              finishReason,
              content: { parts: [{ text: JSON.stringify(object) }] },
            },
          ],
        }),
      );
    };
  assert.equal(
    (
      await gemini(
        "summarize",
        source,
        mock({ summary: "No pain was reported." }),
      )
    ).summary,
    "No pain was reported.",
  );
  await assert.rejects(() =>
    gemini("summarize", source, mock({ summary: "cut" }, "MAX_TOKENS")),
  );
  await assert.rejects(() =>
    gemini(
      "summarize",
      source,
      mock({ summary: "valid", secret: "unrequested" }),
    ),
  );
});
test("Scribe returns ordered source timestamps and neutral speaker labels; rejects invalid timing", () => {
  const words = [
    {
      type: "word",
      text: "Follow",
      start: 0,
      end: 0.4,
      speaker_id: "speaker_0",
    },
    {
      type: "word",
      text: "up.",
      start: 0.5,
      end: 0.8,
      speaker_id: "speaker_0",
    },
  ];
  const result = scribeResult({ text: "Follow up.", words });
  assert.equal(result.segments[0].text, "Follow up.");
  assert.equal(result.segments[0].speaker, "Speaker 1");
  assert.equal(result.model, "scribe_v2");
  assert.throws(() =>
    scribeResult({
      text: "Test",
      words: [{ type: "word", text: "Test", start: 2, end: 1 }],
    }),
  );
});

// MARK: - The serverless preparation contract matches the concise web and Swift brief
test("provider failures distinguish request, access, quota and availability without exposing response bodies", async () => {
  const previousKey = process.env.GEMINI_API_KEY;
  process.env.GEMINI_API_KEY = "fictional-test-key";
  try {
    for (const [status, expected] of [
      [400, /request format/],
      [401, /do not have access/],
      [403, /do not have access/],
      [404, /model or operation/],
      [422, /request format/],
      [429, /rate or quota limit/],
      [503, /temporarily unavailable/],
    ]) {
      await assert.rejects(
        () =>
          gemini(
            "summarize",
            source,
            async () =>
              new Response("private-provider-details fictional-test-key", {
                status,
              }),
          ),
        (error) => {
          assert.match(error.message, expected);
          assert.equal(
            error.status,
            status === 429
              ? 429
              : status >= 500
                ? 503
                : [400, 422].includes(status)
                  ? 422
                  : 424,
          );
          assert.doesNotMatch(
            error.message,
            /private-provider-details|fictional-test-key|credits/,
          );
          if (status === 400) assert.doesNotMatch(error.message, /permissions/);
          return true;
        },
      );
    }
  } finally {
    if (previousKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previousKey;
  }
});

const briefInput = {
  visit: {
    id: "transient-visit",
    type: "Cardiology follow-up",
    concern: "Intermittent palpitations",
    goal: "Prepare for an upcoming appointment",
    questions: [],
  },
  records: Array.from({ length: 7 }, (_, index) => ({
    id: `source-${index + 1}`,
    title: "Fictional clinic note",
    date: "2026-09-12",
    version: 1,
    text: "The fictional patient reports brief palpitations without syncope.",
    summary: "",
  })),
};
function briefResponse(result) {
  return new Response(
    JSON.stringify({
      candidates: [
        {
          finishReason: "STOP",
          content: { parts: [{ text: JSON.stringify(result) }] },
        },
      ],
    }),
  );
}
test("preparation and summaries use the same configured model", async () => {
  const previousKey = process.env.GEMINI_API_KEY,
    previousModel = process.env.GEMINI_MODEL;
  process.env.GEMINI_API_KEY = "fictional-test-key";
  process.env.GEMINI_MODEL = "gemini-other-summary-model";
  try {
    let destination, payload;
    const result = await gemini("prepare", briefInput, async (url, options) => {
      destination = url;
      payload = JSON.parse(options.body);
      return briefResponse({
        overview: "Reason: Intermittent palpitations, per patient.",
        questions: [],
        selectedRecordIDs: ["source-1"],
      });
    });
    assert.equal(result.model, "gemini-other-summary-model");
    assert.match(
      destination,
      /models\/gemini-other-summary-model:generateContent$/,
    );
    assert.equal(payload.generationConfig.candidateCount, undefined);
    assert.equal(payload.generationConfig.temperature, undefined);
    assert.deepEqual(JSON.parse(payload.contents[0].parts[0].text), briefInput);
    const summary = await gemini("summarize", source, async (url) => {
      assert.match(url, /models\/gemini-other-summary-model:generateContent$/);
      return briefResponse({ summary: "No pain was reported." });
    });
    assert.equal(summary.model, "gemini-other-summary-model");
  } finally {
    if (previousKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previousKey;
    if (previousModel === undefined) delete process.env.GEMINI_MODEL;
    else process.env.GEMINI_MODEL = previousModel;
  }
});
test("preparation rejects overflow and invalid sources before returning a brief", async () => {
  const previousKey = process.env.GEMINI_API_KEY;
  process.env.GEMINI_API_KEY = "fictional-test-key";
  const valid = {
    overview: "Reason: Intermittent palpitations.",
    questions: [],
    selectedRecordIDs: [],
  };
  const invalid = [
    { ...valid, overview: "word ".repeat(181) },
    { ...valid, overview: Array(13).fill("Short line").join("\n") },
    { ...valid, overview: "é".repeat(1201) },
    { ...valid, questions: Array(4).fill("What follow-up is needed?") },
    { ...valid, questions: ["é".repeat(71)] },
    {
      ...valid,
      selectedRecordIDs: briefInput.records.map((record) => record.id),
    },
    { ...valid, selectedRecordIDs: ["source-1", "source-1"] },
    { ...valid, selectedRecordIDs: ["unknown-source"] },
  ];
  try {
    for (const result of invalid)
      await assert.rejects(
        () => gemini("prepare", briefInput, async () => briefResponse(result)),
        /Invalid preparation/,
      );
    const boundary = {
      ...valid,
      overview: Array(180).fill("word").join(" "),
      questions: Array(3).fill("What follow-up is needed?"),
      selectedRecordIDs: briefInput.records
        .slice(0, 6)
        .map((record) => record.id),
    };
    assert.deepEqual(
      await gemini("prepare", briefInput, async () => briefResponse(boundary)),
      { ...boundary, model: "gemini-flash-latest" },
    );
  } finally {
    if (previousKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previousKey;
  }
});
