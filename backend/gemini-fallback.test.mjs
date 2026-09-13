// Purpose: Verify Flash/Lite sequencing, cancellation, retry metadata and conditional source-based titles.
// Inputs: Fictional notes, server-only test configuration and injected HTTP responses.
// Outputs: Assertions for model attribution, bounded retry headers and terminal output validation.
// Side effects: Test-process environment only. Every provider call is mocked.
import test from "node:test";
import assert from "node:assert/strict";
import { gemini } from "./providers.mjs";
import {
  geminiFallbackHeader,
  GEMINI_FALLBACK_MODEL,
} from "./gemini-request.mjs";

// MARK: - Synthetic provider fixtures and private test configuration
const source = {
  recordID: "source",
  title: "Fictional note",
  date: "2026-09-12",
  text: "A fictional discussion mentions no fever.",
};
const response = (output) =>
  new Response(
    JSON.stringify({
      candidates: [
        {
          finishReason: "STOP",
          content: { parts: [{ text: JSON.stringify(output) }] },
        },
      ],
    }),
  );
async function configured(run) {
  const key = process.env.GEMINI_API_KEY,
    model = process.env.GEMINI_MODEL;
  process.env.GEMINI_API_KEY = "fictional-fallback-test-key";
  delete process.env.GEMINI_MODEL;
  try {
    await run();
  } finally {
    if (key === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = key;
    if (model === undefined) delete process.env.GEMINI_MODEL;
    else process.env.GEMINI_MODEL = model;
  }
}

// MARK: - Immediate fallback changes attribution and subsequent retries stay on Lite
for (const upstream of [408, 429, 500, 503, "network"])
  test(`Flash ${upstream} failure immediately tries Lite and returns its model`, () =>
    configured(async () => {
      const models = [];
      const result = await gemini("summarize", source, async (url, options) => {
        models.push(new URL(url).pathname.split("/").at(-1).split(":")[0]);
        assert.equal(options.redirect, "error");
        assert.ok(options.signal instanceof AbortSignal);
        if (models.length === 1) {
          if (upstream === "network")
            throw new Error("private upstream detail");
          return new Response("private upstream detail", { status: upstream });
        }
        return response({ summary: "No fever was reported." });
      });
      assert.deepEqual(models, ["gemini-flash-latest", GEMINI_FALLBACK_MODEL]);
      assert.equal(result.model, GEMINI_FALLBACK_MODEL);
    }));

test("Lite-only retries send one request; exhausted Lite failures mark at least 60 seconds", () =>
  configured(async () => {
    for (const [status, upstreamDelay, expectedDelay] of [
      [429, "1", "60"],
      [429, "180", "180"],
      [503, undefined, "60"],
    ]) {
      let calls = 0;
      await assert.rejects(
        () =>
          gemini(
            "summarize",
            source,
            async (url) => {
              calls++;
              assert.ok(
                url.endsWith(`/${GEMINI_FALLBACK_MODEL}:generateContent`),
              );
              return new Response("private detail", {
                status,
                headers: upstreamDelay ? { "Retry-After": upstreamDelay } : {},
              });
            },
            { fallbackOnly: true },
          ),
        (error) => {
          assert.equal(error.status, status);
          assert.equal(error.headers["X-Reva-Gemini-Fallback"], "true");
          assert.equal(error.headers["Retry-After"], expectedDelay);
          assert.ok(!error.message.includes("private detail"));
          return true;
        },
      );
      assert.equal(calls, 1);
    }
    let calls = 0;
    await assert.rejects(
      () =>
        gemini("summarize", source, async () => {
          calls++;
          return new Response("temporary", { status: 503 });
        }),
      (error) => error.headers["X-Reva-Gemini-Fallback"] === "true",
    );
    assert.equal(calls, 2);
  }));

test("permanent provider or generated-output failures do not trigger fallback or retry markers", () =>
  configured(async () => {
    for (const output of [
      400,
      401,
      403,
      404,
      { summary: "Result — invalid punctuation." },
      { summary: "Here is a summary of your health." },
      { summary: "Valid.", title: "Unrequested title" },
    ]) {
      let calls = 0;
      await assert.rejects(
        () =>
          gemini("summarize", source, async () => {
            calls++;
            return typeof output === "number"
              ? new Response("private details", { status: output })
              : response(output);
          }),
        (error) =>
          [422, 424].includes(error.status) &&
          error.headers["X-Reva-Gemini-Fallback"] === undefined,
      );
      assert.equal(calls, 1);
    }
  }));

test("caller cancellation prevents both initial and fallback requests", () =>
  configured(async () => {
    for (const preAborted of [true, false]) {
      const controller = new AbortController();
      let calls = 0;
      if (preAborted) controller.abort();
      await assert.rejects(
        () =>
          gemini(
            "summarize",
            source,
            async () => {
              calls++;
              controller.abort();
              return new Response("temporary", { status: 503 });
            },
            { signal: controller.signal },
          ),
        (error) => error.name === "AbortError",
      );
      assert.equal(calls, preAborted ? 0 : 1);
    }
  }));

// MARK: - Titles are requested explicitly, bounded in bytes and never silently cleaned
test("requested titles preserve source input and require plain bounded generated wording", () =>
  configured(async () => {
    const input = {
      ...source,
      generateTitle: true,
      text: source.text + " Original source — preserve punctuation.",
    };
    const title = "Fever discussion";
    const result = await gemini("summarize", input, async (_, options) => {
      const body = JSON.parse(options.body);
      assert.deepEqual(JSON.parse(body.contents[0].parts[0].text), input);
      assert.deepEqual(body.generationConfig.responseJsonSchema.required, [
        "summary",
        "title",
      ]);
      assert.match(
        body.systemInstruction.parts[0].text,
        /CLINICAL WRITING CRITERIA/,
      );
      return response({ summary: "No fever was reported.", title });
    });
    assert.equal(result.title, title);
    for (const invalidTitle of [
      undefined,
      "",
      "é".repeat(61),
      "Title\nsecond line",
      "**Decorated**",
      "Heading — discussion",
    ]) {
      let calls = 0;
      await assert.rejects(
        () =>
          gemini("summarize", input, async () => {
            calls++;
            return response({
              summary: "No fever was reported.",
              ...(invalidTitle === undefined ? {} : { title: invalidTitle }),
            });
          }),
        (error) => error.status === 422,
      );
      assert.equal(calls, 1);
    }
  }));

test("invalid title request fields and arbitrary model headers fail before provider use", () =>
  configured(async () => {
    for (const invalid of [
      { generateTitle: "true" },
      { generateTitle: null },
      { date: "" },
      { date: 123 },
      { date: "x".repeat(41) },
    ]) {
      await assert.rejects(
        () =>
          gemini("summarize", { ...source, ...invalid }, async () => {
            assert.fail("provider must not run");
          }),
        (error) => error.status === 400,
      );
    }
    assert.equal(geminiFallbackHeader(undefined), false);
    assert.equal(geminiFallbackHeader("true"), true);
    for (const invalid of [
      "false",
      "gemini-custom",
      "true,true",
      ["true"],
      "TRUE",
      "true ",
    ])
      assert.throws(
        () => geminiFallbackHeader(invalid),
        (error) => error.status === 400,
      );
  }));

// MARK: - Syntactically valid but non-object envelopes are terminal, never unhandled outages
test("null provider envelope is terminal structured-output failure", () =>
  configured(async () => {
    let calls = 0;
    await assert.rejects(
      () =>
        gemini("summarize", source, async () => {
          calls++;
          return new Response("null");
        }),
      (error) => error.status === 422,
    );
    assert.equal(calls, 1);
  }));
