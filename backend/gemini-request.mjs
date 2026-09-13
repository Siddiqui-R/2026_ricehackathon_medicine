// Purpose: Try the configured Flash model once, then the fixed Lite alias after a technical failure.
// Inputs: Server-owned model/options, injected fetch and an optional caller cancellation signal.
// Outputs: Successful envelope/model or sanitized terminal errors and bounded Lite retry metadata.
// Side effects: At most two Google requests, each limited to 35 seconds; no sleeping or persistence.
import { fail } from "./validation.mjs";
import { providerJSON } from "./provider-http.mjs";

// MARK: - A client can request only the fixed fallback, never provide a model identifier
export const GEMINI_FALLBACK_MODEL = "gemini-flash-lite-latest";
export function geminiFallbackHeader(value) {
  if (value === undefined) return false;
  if (value !== "true")
    fail(400, "X-Reva-Gemini-Fallback must be true when supplied.");
  return true;
}

// MARK: - Retry only transient transport/provider failures, never rejected content or configuration
export async function geminiRequest(
  primaryModel,
  request,
  fetcher,
  { fallbackOnly = false, signal } = {},
) {
  const models = fallbackOnly
    ? [GEMINI_FALLBACK_MODEL]
    : [primaryModel, GEMINI_FALLBACK_MODEL];
  for (let index = 0; index < models.length; index++) {
    signal?.throwIfAborted();
    const model = models[index];
    try {
      const envelope = await providerJSON(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        request,
        fetcher,
        { signal, timeoutMs: 35000 },
      );
      signal?.throwIfAborted();
      return { envelope, model };
    } catch (error) {
      signal?.throwIfAborted();
      if (![429, 503].includes(error?.status)) throw error;
      if (index + 1 < models.length) continue;
      const delay = Number(error.headers?.["Retry-After"]);
      error.headers = {
        ...error.headers,
        "X-Reva-Gemini-Fallback": "true",
        "Retry-After": String(
          Math.max(60, Number.isFinite(delay) ? delay : 60),
        ),
      };
      throw error;
    }
  }
}
