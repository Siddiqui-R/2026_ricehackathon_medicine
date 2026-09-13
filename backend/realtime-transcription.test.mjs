import assert from "node:assert/strict";
import test from "node:test";
import { realtimeTranscriptionToken } from "./providers.mjs";

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
    assert.equal(url, "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe");
    assert.equal(options.method, "POST");
    assert.equal(options.redirect, "error");
    assert.equal(options.headers["xi-api-key"], "synthetic-private-key");
    return Response.json({ token: "synthetic-one-use-token", ignored: "private metadata" });
  });
  assert.deepEqual(result, { token: "synthetic-one-use-token" });
  for (const token of [null, "", "bad\nvalue", "x".repeat(8193)]) {
    await assert.rejects(
      realtimeTranscriptionToken(async () => Response.json({ token })),
      (error) => error.status === 502,
    );
  }
  delete process.env.ELEVENLABS_API_KEY;
  await assert.rejects(realtimeTranscriptionToken(async () => { calls++; }), (error) => error.status === 424);
  assert.equal(calls, 1);
});
