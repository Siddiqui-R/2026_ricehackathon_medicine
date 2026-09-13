// Purpose: Verify the requested Flash/Lite backoff schedule, cancellation and authenticated retry headers.
// Inputs: Synthetic provider failures, fake time and injected HTTP responses.
// Outputs: No delay before the immediate fallback; 60/120/240-second waits after Lite fails.
// Side effects: Test memory and fake timers only, with no provider calls or real waiting.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { APIError, RevaAPI } from '../api';
import { retryGemini, waitForGemini } from '../geminiRetry';
import { seed } from './fixtures';

afterEach(() => vi.useRealTimers());
const exhausted = (status = 503, retryAfter: number | null = null) =>
  new APIError(status, null, 'Temporary provider failure.', retryAfter, true);

describe('Gemini fallback and backoff', () => {
  it('starts n at zero after the first Lite failure and keeps all delayed retries on Lite', async () => {
    const attempt = vi
      .fn<(fallback: boolean) => Promise<string>>()
      .mockRejectedValueOnce(exhausted())
      .mockRejectedValueOnce(exhausted(429))
      .mockRejectedValueOnce(exhausted())
      .mockResolvedValue('summary');
    const wait = vi.fn(async (_delay: number, _signal?: AbortSignal) => {});
    const progress = vi.fn();
    expect(await retryGemini(attempt, undefined, progress, wait)).toBe('summary');
    expect(attempt.mock.calls.map(([fallback]) => fallback)).toEqual([false, true, true, true]);
    expect(wait.mock.calls.map(([delay]) => delay)).toEqual([60_000, 120_000, 240_000]);
    expect(progress.mock.calls.filter(([state]) => state).map(([state]) => state.attempt)).toEqual([0, 1, 2]);
    expect(progress).toHaveBeenLastCalledWith(null);
  });
  it('tries Lite immediately if the initial request fails before the server responds', async () => {
    const attempt = vi
      .fn<(fallback: boolean) => Promise<string>>()
      .mockRejectedValueOnce(new TypeError('Failed to fetch'))
      .mockRejectedValueOnce(exhausted())
      .mockResolvedValue('summary');
    const wait = vi.fn(async (_delay: number, _signal?: AbortSignal) => {});
    await retryGemini(attempt, undefined, undefined, wait);
    expect(attempt.mock.calls).toEqual([[false], [true], [true]]);
    expect(wait).toHaveBeenCalledExactlyOnceWith(60_000, undefined);
  });
  it.each([400, 401, 403, 404, 409, 422, 424])('does not keep retrying terminal HTTP %s', async (status) => {
    const attempt = vi.fn().mockRejectedValue(new APIError(status));
    const wait = vi.fn(async (_delay: number, _signal?: AbortSignal) => {});
    await expect(retryGemini(attempt, undefined, undefined, wait)).rejects.toMatchObject({ status });
    expect(attempt).toHaveBeenCalledOnce();
    expect(wait).not.toHaveBeenCalled();
  });
  it('honors a provider Retry-After longer than the exponential delay', async () => {
    const attempt = vi.fn().mockRejectedValueOnce(exhausted(429, 180)).mockResolvedValue('ready');
    const wait = vi.fn(async (_delay: number, _signal?: AbortSignal) => {});
    await retryGemini(attempt, undefined, undefined, wait);
    expect(wait).toHaveBeenCalledExactlyOnceWith(180_000, undefined);
  });
  it('aborts a scheduled wait without another provider request', async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const attempt = vi.fn().mockRejectedValue(exhausted());
    const progress = vi.fn();
    const task = retryGemini(attempt, controller.signal, progress);
    const rejection = expect(task).rejects.toMatchObject({ name: 'AbortError' });
    await vi.advanceTimersByTimeAsync(0);
    expect(progress.mock.calls[0][0].attempt).toBe(0);
    controller.abort();
    await rejection;
    await vi.advanceTimersByTimeAsync(60_000);
    expect(attempt).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });
  it('does not overflow browser timers for long exponential waits', async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const wait = waitForGemini(3_000_000_000, controller.signal);
    const rejection = expect(wait).rejects.toMatchObject({ name: 'AbortError' });
    await vi.advanceTimersByTimeAsync(1);
    expect(vi.getTimerCount()).toBe(1);
    controller.abort();
    await rejection;
    expect(vi.getTimerCount()).toBe(0);
  });
  it('carries title/date context and requests only Lite after the server exhausts its pair', async () => {
    vi.useFakeTimers();
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ reason: 'Try later.' }), {
          status: 429,
          headers: {
            'Content-Type': 'application/json',
            'X-Reva-Gemini-Fallback': 'true',
            'Retry-After': '60',
          },
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            summary: 'Review of existing records.',
            title: 'Records review',
            model: 'gemini-flash-lite-latest',
          }),
        ),
      );
    const progress = vi.fn();
    const record = seed().records[0];
    const task = new RevaAPI('synthetic-token', fetcher).summarize(record, undefined, {
      generateTitle: true,
      date: '2026-09-12',
      onRetry: progress,
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(fetcher).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(59_999);
    expect(fetcher).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(1);
    await expect(task).resolves.toMatchObject({ title: 'Records review', model: 'gemini-flash-lite-latest' });
    expect(fetcher.mock.calls[1][1]?.headers).toMatchObject({
      'X-Reva-Gemini-Fallback': 'true',
      Authorization: 'Bearer synthetic-token',
    });
    expect(JSON.parse(fetcher.mock.calls[1][1]!.body as string)).toMatchObject({
      recordID: record.id,
      date: '2026-09-12',
      generateTitle: true,
    });
  });
  it('does not present an upload date as a clinical event date in any analysis request', async () => {
    const fetcher = vi.fn<typeof fetch>().mockImplementation(async (_url, options) => {
      const path = String(_url);
      if (path.endsWith('/summarize'))
        return new Response(JSON.stringify({ summary: 'Source reviewed.', model: 'mock' }));
      if (path.endsWith('/prepare'))
        return new Response(
          JSON.stringify({
            overview: 'Review the supplied report.',
            questions: [],
            selectedRecordIDs: [],
            model: 'mock',
          }),
        );
      return new Response(
        JSON.stringify({
          allergies: [],
          medications: [],
          conditions: [],
          surgeriesAndImplants: [],
          careNotes: [],
          model: 'mock',
        }),
      );
    });
    const snapshot = seed();
    const record = { ...snapshot.records[0], date: '2026-09-12', dateSource: 'added' as const };
    snapshot.records = [record];
    const api = new RevaAPI('synthetic-token', fetcher);
    const { profileSources } = await import('../medicalProfileAI');
    await api.summarize(record);
    await api.prepare(snapshot.visits[0], [record]);
    await api.medicalProfile(profileSources(snapshot));
    const bodies = fetcher.mock.calls.map(([, options]) => JSON.parse(options!.body as string));
    expect(bodies[0].date).toBe('Added 2026-09-12; event date unknown');
    expect(bodies[1].records[0].date).toBe(bodies[0].date);
    expect(bodies[2].records[0].date).toBe(bodies[0].date);
  });
});
