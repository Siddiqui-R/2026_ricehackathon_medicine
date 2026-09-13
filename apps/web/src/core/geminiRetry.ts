// Purpose: Retry temporary Gemini failures without tying minute-long waits to a server request.
// Inputs: An authenticated attempt function, cancellation and optional progress callbacks.
// Outputs: The first successful result, or a terminal validation/configuration/cancellation error.
// Side effects: Abortable timers and sequential attempts. After Flash and Lite fail, waits are 60 * 2^n seconds.

export interface GeminiRetryState {
  retryAt: number;
  /** Zero for the first delayed retry, immediately after the first Flash-Lite failure. */
  attempt: number;
}
export interface GeminiRequestOptions {
  generateTitle?: boolean;
  date?: string;
  onRetry?: (retry: GeminiRetryState | null) => void;
}
interface RetryableFailure {
  status?: number;
  retryAfter?: number | null;
  geminiFallback?: boolean;
}
function temporary(error: unknown): boolean {
  if (error instanceof TypeError) return true; // Fetch failed before receiving an HTTP response.
  const status = (error as RetryableFailure | null)?.status;
  return status !== undefined && [408, 429, 500, 502, 503, 504].includes(status);
}
function canceled(signal?: AbortSignal) {
  if (signal?.aborted)
    throw new DOMException('Analysis canceled. Your saved sources were kept.', 'AbortError');
}

// MARK: - Chunk long waits to avoid browser timer overflow; cancellation releases every timer/listener.
export function waitForGemini(milliseconds: number, signal?: AbortSignal): Promise<void> {
  canceled(signal);
  return new Promise((resolve, reject) => {
    const until = Date.now() + milliseconds;
    let timer: ReturnType<typeof setTimeout>;
    const cleanup = () => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    };
    const abort = () => {
      cleanup();
      reject(new DOMException('Analysis canceled. Your saved sources were kept.', 'AbortError'));
    };
    const tick = () => {
      const remaining = until - Date.now();
      if (remaining <= 0) {
        cleanup();
        resolve();
      } else timer = setTimeout(tick, Math.min(remaining, 2_147_483_647));
    };
    signal?.addEventListener('abort', abort, { once: true });
    tick();
  });
}

// MARK: - The server tries Flash then Lite once; later client attempts explicitly request only Lite.
export async function retryGemini<T>(
  request: (fallbackOnly: boolean) => Promise<T>,
  signal?: AbortSignal,
  onRetry?: (retry: GeminiRetryState | null) => void,
  wait = waitForGemini,
): Promise<T> {
  let fallbackOnly = false;
  let delayedAttempt = 0;
  try {
    for (;;) {
      canceled(signal);
      try {
        const result = await request(fallbackOnly);
        canceled(signal);
        return result;
      } catch (error) {
        canceled(signal);
        if (!temporary(error)) throw error;
        const failure = error as RetryableFailure;
        // Without a server exhaustion marker the first request may have failed in transit.
        // Give Lite its immediate attempt, except when a rate-limit response explicitly asks us to wait.
        if (!fallbackOnly && !failure.geminiFallback && failure.status !== 429) {
          fallbackOnly = true;
          continue;
        }
        fallbackOnly = true;
        const delay = Math.max(60_000 * 2 ** delayedAttempt, (failure.retryAfter ?? 0) * 1000);
        if (!Number.isSafeInteger(delay) || !Number.isSafeInteger(Date.now() + delay)) throw error;
        onRetry?.({ retryAt: Date.now() + delay, attempt: delayedAttempt });
        delayedAttempt += 1;
        await wait(delay, signal);
        onRetry?.(null);
      }
    }
  } finally {
    onRetry?.(null);
  }
}
