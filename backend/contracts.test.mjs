// Purpose: Check strict input/output validation with fictional fixtures and a mocked provider.
import test from "node:test";
import assert from "node:assert/strict";
import { snapshot, credentials, preparationInput } from "./validation.mjs";
import { gemini, scribeResult } from "./providers.mjs";
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
