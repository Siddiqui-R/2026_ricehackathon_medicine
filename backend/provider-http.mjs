// Purpose: Bound provider HTTP responses and distinguish permanent failures from transient outages.
// Inputs: Fixed-origin requests, an injected fetch implementation and untrusted upstream bytes.
// Outputs: Parsed JSON or a sanitized HTTP error with an optional bounded retry delay.
// Side effects: One HTTPS request; never logs or returns raw provider messages or credentials.
import { fail } from "./validation.mjs";

// MARK: - Read only the bounded error classification; provider text can contain source data
async function errorDetails(response) {
  const reader = response.body?.getReader();
  if (!reader) return {};
  const parts = [];
  let length = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.length;
      if (length > 65536) return {};
      parts.push(part.value);
    }
    const error = JSON.parse(Buffer.concat(parts).toString("utf8"))?.error;
    return {
      status: error?.status,
      reasons: Array.isArray(error?.details)
        ? error.details.map((detail) => detail?.reason)
        : [],
    };
  } catch {
    return {};
  } finally {
    await reader.cancel().catch(() => {});
  }
}

// MARK: - Permanent upstream failures must not become retryable 503 responses
async function rejectProviderResponse(response) {
  const details = await errorDetails(response);
  if (response.status === 429) {
    const delay = response.headers.get("retry-after");
    const seconds = /^\d{1,4}$/.test(delay || "")
      ? Math.min(3600, Math.max(1, Number(delay)))
      : 60;
    fail(
      429,
      "The provider's rate or quota limit was reached. Try again later.",
      {
        "Retry-After": String(seconds),
      },
    );
  }
  if (response.status === 408 || response.status >= 500)
    fail(
      503,
      "The provider is temporarily unavailable. Your saved data is unchanged.",
    );
  if (
    details.reasons?.some((reason) =>
      [
        "API_KEY_INVALID",
        "API_KEY_EXPIRED",
        "API_KEY_SERVICE_BLOCKED",
        "API_KEY_HTTP_REFERRER_BLOCKED",
        "API_KEY_IP_ADDRESS_BLOCKED",
      ].includes(reason),
    )
  )
    fail(
      424,
      "The provider rejected the server API key or its restrictions. Update the server's provider configuration.",
    );
  if (details.status === "FAILED_PRECONDITION")
    fail(
      424,
      "The provider's setup requirements are not met. Check the server project's region and billing configuration.",
    );
  if (response.status === 401 || response.status === 403)
    fail(
      424,
      "The server's provider credentials do not have access to this operation. Check the API key and its permissions.",
    );
  if (response.status === 404)
    fail(
      424,
      "The configured provider model or operation is unavailable. Check the server's model configuration.",
    );
  if ([400, 413, 415, 422].includes(response.status))
    fail(
      422,
      `The provider could not process this request (HTTP ${response.status}). Check the request format, supported file type and model settings.`,
    );
  fail(
    424,
    `The provider rejected this operation (HTTP ${response.status}). Check the server's provider configuration.`,
  );
}

// MARK: - One timed, redirect-free request and bounded success JSON
export async function providerJSON(url, options, fetcher) {
  let response;
  try {
    response = await fetcher(url, {
      ...options,
      redirect: "error",
      signal: AbortSignal.timeout(90000),
    });
  } catch {
    fail(
      503,
      "The provider could not be reached. Your saved data is unchanged.",
    );
  }
  if (!response.ok) await rejectProviderResponse(response);
  let bytes = 0;
  const parts = [];
  try {
    for await (const part of response.body) {
      bytes += part.length;
      if (bytes > 4 * 1024 * 1024)
        fail(
          422,
          "The provider response was too large. No AI result was saved.",
        );
      parts.push(part);
    }
  } catch (error) {
    if (error?.status) throw error;
    fail(
      503,
      "The provider response was interrupted. Your saved data is unchanged.",
    );
  }
  try {
    return JSON.parse(Buffer.concat(parts).toString("utf8"));
  } catch {
    fail(422, "The provider returned invalid JSON. No AI result was saved.");
  }
}
