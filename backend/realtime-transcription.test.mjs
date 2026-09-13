// Purpose: Verify bounded live-token minting and independent final transcription with fictional input.
// Inputs: Mock provider responses, synthetic bytes and test-process server configuration.
// Outputs: Assertions for private-key isolation, timeout/cancellation and saved-audio fallback support.
// Side effects: Temporary test-process configuration only. No network, microphone or real audio is used.
import assert from "node:assert/strict";
import test from "node:test";
import { realtimeTranscriptionToken, transcribe } from "./providers.mjs";

test("live transcription exposes only a one-use token from a fixed provider origin", async (t) => {
  const previous = process.env.ELEVENLABS_API_KEY;
  t.after(() => {
    if (previous === undefined) delete process.env.ELEVENLABS_API_KEY;
    else process.env.ELEVENLABS_API_KEY = previous;
  });
  process.env.ELEVENLABS_API_KEY = "synthetic-private-key";
  let calls = 0;
  const result = await realtimeTranscriptionToken(async (url, options) => {
    calls++;
    assert.equal(
      url,
      "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe",
    );
    assert.equal(options.method, "POST");
    assert.equal(options.redirect, "error");
    assert.equal(options.headers["xi-api-key"], "synthetic-private-key");
    return Response.json({
      token: "synthetic-one-use-token",
      ignored: "private metadata",
    });
  });
  assert.deepEqual(result, { token: "synthetic-one-use-token" });
  for (const token of [null, "", "bad\nvalue", "x".repeat(8193)]) {
    await assert.rejects(
      realtimeTranscriptionToken(async () => Response.json({ token })),
      (error) => error.status === 502,
    );
  }
  delete process.env.ELEVENLABS_API_KEY;
  await assert.rejects(
    realtimeTranscriptionToken(async () => {
      calls++;
    }),
    (error) => error.status === 424,
  );
  assert.equal(calls, 1);
});

// MARK: - Fake private configuration never reaches the response DTO or sanitized provider errors
function configured(t) {
  const previous = process.env.ELEVENLABS_API_KEY;
  process.env.ELEVENLABS_API_KEY = "synthetic-private-key";
  t.after(() => {
    if (previous === undefined) delete process.env.ELEVENLABS_API_KEY;
    else process.env.ELEVENLABS_API_KEY = previous;
  });
}

test("token minting stops before the browser deadline and never retries a timed-out token", async (t) => {
  configured(t);
  const deadline = new AbortController();
  t.mock.method(AbortSignal, "timeout", (milliseconds) => {
    assert.equal(milliseconds, 12000);
    return deadline.signal;
  });
  let calls = 0;
  await assert.rejects(
    realtimeTranscriptionToken(async (_, options) => {
      calls++;
      return new Promise((_, reject) => {
        options.signal.addEventListener(
          "abort",
          () => reject(options.signal.reason),
          { once: true },
        );
        queueMicrotask(() =>
          deadline.abort(
            new DOMException("synthetic private detail", "TimeoutError"),
          ),
        );
      });
    }),
    (error) =>
      error.status === 503 &&
      !error.message.includes("synthetic private detail"),
  );
  assert.equal(calls, 1);
});

test("cancelled or abandoned token requests stop provider work without a replacement token", async (t) => {
  configured(t);
  for (const preAborted of [true, false]) {
    const controller = new AbortController();
    let calls = 0;
    if (preAborted) controller.abort();
    await assert.rejects(
      realtimeTranscriptionToken(
        async (_, options) => {
          calls++;
          return new Promise((_, reject) => {
            options.signal.addEventListener(
              "abort",
              () => reject(options.signal.reason),
              { once: true },
            );
            queueMicrotask(() => controller.abort());
          });
        },
        { signal: controller.signal },
      ),
      (error) => error.name === "AbortError",
    );
    assert.equal(calls, preAborted ? 0 : 1);
  }
});

test("live-token provider failures expose neither API credentials nor upstream details", async (t) => {
  configured(t);
  for (const [upstream, expected] of [
    [400, 422],
    [401, 424],
    [403, 424],
    [429, 429],
    [503, 503],
  ]) {
    await assert.rejects(
      realtimeTranscriptionToken(async () =>
        Response.json(
          {
            error: {
              message: "synthetic-private-key and private provider details",
            },
          },
          { status: upstream },
        ),
      ),
      (error) => {
        assert.equal(error.status, expected);
        assert.ok(!error.message.includes("synthetic-private-key"));
        assert.ok(!error.message.includes("private provider details"));
        return true;
      },
    );
  }
});

// MARK: - Live-token availability does not gate transcription of the preserved original after save
test("failed live setup still allows final batch transcription of unchanged original bytes", async (t) => {
  configured(t);
  const original = Buffer.from([0, 1, 2, 255]);
  const before = Buffer.from(original);
  await assert.rejects(
    realtimeTranscriptionToken(
      async () => new Response("temporary", { status: 503 }),
    ),
    (error) => error.status === 503,
  );
  let calls = 0;
  const result = await transcribe(
    original,
    { "content-type": "audio/webm", "x-filename": "synthetic.webm" },
    async (url, options) => {
      calls++;
      assert.equal(url, "https://api.elevenlabs.io/v1/speech-to-text");
      assert.equal(options.body.get("model_id"), "scribe_v2");
      assert.equal(options.body.get("diarize"), "true");
      assert.equal(options.body.get("timestamps_granularity"), "word");
      const file = options.body.get("file");
      assert.equal(file.type, "audio/webm");
      assert.equal(file.name, "synthetic.webm");
      assert.deepEqual(Buffer.from(await file.arrayBuffer()), before);
      return Response.json({
        text: "Fictional speech.",
        words: [
          {
            type: "word",
            text: "Fictional speech.",
            start: 0,
            end: 1,
            speaker_id: "speaker_0",
          },
        ],
      });
    },
  );
  assert.equal(calls, 1);
  assert.deepEqual(original, before);
  assert.deepEqual(result, {
    text: "Fictional speech.",
    segments: [
      {
        id: "scribe-segment-0",
        text: "Fictional speech.",
        start: 0,
        end: 1,
        speaker: "Speaker 1",
      },
    ],
    model: "scribe_v2",
  });
});

// MARK: - Run the real route/auth handler with only the database and provider network replaced
// Module mocking is isolated in a child process so ordinary backend tests keep real module contracts.
test("realtime HTTP route requires authentication, disables caching and cancels abandoned minting", async () => {
  const { execFileSync } = await import("node:child_process");
  const databaseURL = new URL("./database.mjs", import.meta.url).href;
  const handlerURL = new URL("../api/reva.mjs", import.meta.url).href;
  const script = `
    import assert from "node:assert/strict";
    import { mock } from "node:test";
    import { Readable } from "node:stream";
    import { EventEmitter } from "node:events";
    mock.module(${JSON.stringify(databaseURL)}, { namedExports: {
      migrate: async () => {},
      database: () => ({ query: async (sql) => {
        if (sql.startsWith("INSERT INTO reva_web_limits")) return { rows: [{ count: 1 }] };
        if (sql.startsWith("DELETE FROM reva_web_limits") || sql.startsWith("SELECT u.*")) return { rows: [] };
        assert.fail("Unexpected database operation");
      } }),
      transaction: async () => assert.fail("Unexpected transaction"),
    } });
    const { default: handler } = await import(${JSON.stringify(handlerURL)});
    process.env.ELEVENLABS_API_KEY = "synthetic-private-key";
    process.env.REVA_TOKENS = JSON.stringify({ "synthetic-static-token-1234567890": "synthetic-owner" });
    class ResponseCapture extends EventEmitter {
      headers = new Map(); body = ""; destroyed = false; writableEnded = false; headersSent = false;
      setHeader(name, value) { this.headers.set(name.toLowerCase(), value); }
      end(value) { this.body = value?.toString() || ""; this.writableEnded = true; }
      destroy() { this.destroyed = true; this.emit("close"); }
    }
    let calls = 0, activeResponse, observedSignal;
    globalThis.fetch = async (url, options) => {
      calls++;
      assert.equal(url, "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe");
      assert.equal(options.headers["xi-api-key"], "synthetic-private-key");
      observedSignal = options.signal;
      if (activeResponse) {
        return new Promise((_, reject) => {
          options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
          queueMicrotask(() => activeResponse.destroy());
        });
      }
      return Response.json({ token: "synthetic-one-use-token", privateDetail: "synthetic-private-key" });
    };
    async function request(authorization, { disconnect = false, body = "" } = {}) {
      const req = Readable.from(body ? [Buffer.from(body)] : []);
      req.method = "POST"; req.url = "/v1/audio/realtime-token";
      req.headers = authorization ? { authorization } : {};
      req.aborted = false;
      const res = new ResponseCapture();
      activeResponse = disconnect ? res : undefined;
      await handler(req, res);
      assert.equal(res.headers.get("cache-control"), "no-store");
      assert.ok(!res.body.includes("synthetic-private-key"));
      assert.equal(req.listenerCount("aborted"), 0);
      assert.equal(res.listenerCount("close"), 0);
      return res;
    }
    assert.equal((await request()).statusCode, 401);
    assert.equal((await request("Bearer unknown-token-123456789012345")).statusCode, 401);
    assert.equal(calls, 0);
    const authorization = "Bearer synthetic-static-token-1234567890";
    const valid = await request(authorization);
    assert.equal(valid.statusCode, 200);
    assert.deepEqual(JSON.parse(valid.body), { token: "synthetic-one-use-token" });
    assert.equal(calls, 1);
    assert.equal((await request(authorization, { body: "unexpected" })).statusCode, 413);
    assert.equal(calls, 1);
    await request(authorization, { disconnect: true });
    assert.equal(calls, 2);
    assert.equal(observedSignal.aborted, true);
    process.stdout.write("realtime route contract verified");
  `;
  const output = execFileSync(
    process.execPath,
    [
      "--experimental-test-module-mocks",
      "--input-type=module",
      "--eval",
      script,
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  );
  assert.equal(output, "realtime route contract verified");
});
