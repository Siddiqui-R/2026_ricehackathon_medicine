// Purpose: Verify provider compatibility and sanitized permanent/transient failure boundaries.
// Inputs: Synthetic documents and mocked upstream responses; no external credentials.
// Outputs: Assertions on outgoing Gemini parameters, retry statuses and bounded response handling.
// Side effects: Temporary test-process environment values only; all HTTP is mocked.
import test from "node:test";
import assert from "node:assert/strict";
import { gemini } from "./providers.mjs";
import { providerJSON } from "./provider-http.mjs";

// MARK: - Gemini 3.8-compatible construction keeps the strict source/output schema
test("Gemini does not send unsupported sampling or candidate-count parameters", async () => {
  const previous = process.env.GEMINI_API_KEY;
  process.env.GEMINI_API_KEY = "fictional-test-key";
  try {
    await gemini(
      "summarize",
      {
        recordID: "synthetic-source",
        title: "Fictional note",
        text: "Fictional test source.",
      },
      async (_, options) => {
        const config = JSON.parse(options.body).generationConfig;
        for (const name of ["candidateCount", "temperature", "topP", "topK"])
          assert.equal(config[name], undefined);
        assert.equal(config.responseMimeType, "application/json");
        assert.deepEqual(config.responseJsonSchema.required, ["summary"]);
        assert.equal(config.responseJsonSchema.additionalProperties, false);
        assert.equal(config.maxOutputTokens, 8192);
        return new Response(
          JSON.stringify({
            candidates: [
              {
                finishReason: "STOP",
                content: {
                  parts: [
                    { text: JSON.stringify({ summary: "Fictional summary." }) },
                  ],
                },
              },
            ],
          }),
        );
      },
    );
  } finally {
    if (previous === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previous;
  }
});

// MARK: - Bad requests and provider credentials are not browser-session failures or outages
const sensitive = "source-text-and-credential-must-not-be-exposed";
test("permanent failures use 422 or 424 and never expose raw provider details", async () => {
  for (const [upstream, status, fragment, details] of [
    [400, 422, /request format/, {}],
    [
      400,
      424,
      /API key/,
      {
        details: [
          { reason: "API_KEY_INVALID", metadata: { source: sensitive } },
        ],
      },
    ],
    [400, 424, /region and billing/, { status: "FAILED_PRECONDITION" }],
    [401, 424, /credentials/, {}],
    [403, 424, /credentials/, {}],
    [404, 424, /model/, {}],
    [413, 422, /request format/, {}],
    [415, 422, /file type/, {}],
    [422, 422, /request format/, {}],
  ]) {
    await assert.rejects(
      () =>
        providerJSON(
          "https://provider.example",
          {},
          async () =>
            new Response(
              JSON.stringify({ error: { ...details, message: sensitive } }),
              { status: upstream },
            ),
        ),
      (error) => {
        assert.equal(error.status, status);
        assert.match(error.message, fragment);
        assert.ok(!error.message.includes(sensitive));
        assert.ok(!error.message.includes("credits"));
        return true;
      },
    );
  }
});

test("transient responses stay retryable and quota retry delays are bounded", async () => {
  for (const status of [408, 500, 502, 503, 504])
    await assert.rejects(
      () =>
        providerJSON(
          "https://provider.example",
          {},
          async () => new Response(sensitive, { status }),
        ),
      (error) => error.status === 503 && !error.message.includes(sensitive),
    );
  await assert.rejects(
    () =>
      providerJSON("https://provider.example", {}, async () => {
        throw new Error(sensitive);
      }),
    (error) => error.status === 503 && !error.message.includes(sensitive),
  );
  for (const [delay, expected] of [
    ["120", "120"],
    ["9999", "3600"],
    ["invalid", "60"],
    ["0", "1"],
  ])
    await assert.rejects(
      () =>
        providerJSON(
          "https://provider.example",
          {},
          async () =>
            new Response(sensitive, {
              status: 429,
              headers: { "Retry-After": delay },
            }),
        ),
      (error) =>
        error.status === 429 && error.headers["Retry-After"] === expected,
    );
});

// MARK: - Even malicious or interrupted upstream bodies stay bounded and sanitized
test("oversized error bodies are cancelled and invalid success JSON is nonretryable", async () => {
  let cancelled = false;
  await assert.rejects(
    () =>
      providerJSON(
        "https://provider.example",
        {},
        async () =>
          new Response(
            new ReadableStream({
              pull(controller) {
                controller.enqueue(new Uint8Array(65537));
              },
              cancel() {
                cancelled = true;
              },
            }),
            { status: 400 },
          ),
      ),
    (error) => error.status === 422,
  );
  assert.equal(cancelled, true);
  await assert.rejects(
    () =>
      providerJSON(
        "https://provider.example",
        {},
        async () => new Response(sensitive),
      ),
    (error) => error.status === 422 && !error.message.includes(sensitive),
  );
  await assert.rejects(
    () =>
      providerJSON(
        "https://provider.example",
        {},
        async () =>
          new Response(
            new ReadableStream({
              start(controller) {
                controller.error(new Error(sensitive));
              },
            }),
          ),
      ),
    (error) => error.status === 503 && !error.message.includes(sensitive),
  );
});
