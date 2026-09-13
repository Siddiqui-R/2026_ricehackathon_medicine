// Purpose: Verify the real browser HTTP boundary without network or provider credentials.
// Inputs: Mock fetch responses and synthetic JSON/original bytes.
// Outputs: Assertions for auth, fixed paths, CAS revisions, size bounds and provider validation.
// Side effects: Test memory only; every fetch is injected.
import { describe, expect, it, vi } from 'vitest';
import {
  APIError,
  attachmentID,
  attachmentMetadataName,
  boundedBytes,
  RevaAPI,
  uploadContentType,
} from '../api.ts';
import { seed } from './fixtures.ts';

// MARK: - Native state headers and wire shapes remain exact, including tombstone revisions.
describe('same-origin API contract', () => {
  it('requests a one-use live token with owner auth, cancellation and no audio or body', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ token: 'synthetic-live-token' }));
    const controller = new AbortController();
    const api = new RevaAPI('synthetic-owner', fetcher);
    expect(await api.realtimeTranscriptionToken(controller.signal)).toBe('synthetic-live-token');
    expect(fetcher.mock.calls[0][0]).toBe('/v1/audio/realtime-token');
    expect(fetcher.mock.calls[0][1]).toMatchObject({
      method: 'POST',
      cache: 'no-store',
      redirect: 'error',
      body: undefined,
      headers: { Authorization: 'Bearer synthetic-owner' },
    });
    controller.abort();
    await expect(api.realtimeTranscriptionToken(controller.signal)).rejects.toMatchObject({
      name: 'AbortError',
    });
    expect(fetcher).toHaveBeenCalledOnce();
    fetcher.mockResolvedValue(Response.json({ token: 'invalid\nvalue' }));
    await expect(api.realtimeTranscriptionToken()).rejects.toThrow('could not be opened');
  });
  it('sends owner authentication and the exact state CAS body', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify({ revision: 9 })));
    const api = new RevaAPI('private-test-token', fetcher),
      data = seed();
    expect(await api.push(data, 8)).toBe(9);
    const [path, options] = fetcher.mock.calls[0];
    expect(path).toBe('/v1/state');
    expect(options).toMatchObject({
      method: 'PUT',
      credentials: 'omit',
      redirect: 'error',
      cache: 'no-store',
      headers: { Authorization: 'Bearer private-test-token' },
    });
    expect(JSON.parse(options!.body as string)).toEqual({ baseRevision: 8, snapshot: data });
  });
  it.each([0, 12])('preserves empty state tombstone revision %i', async (revision) => {
    const api = new RevaAPI(
      'test',
      vi
        .fn<typeof fetch>()
        .mockResolvedValue(
          new Response('', { status: 404, headers: { 'X-State-Revision': String(revision) } }),
        ),
    );
    await expect(api.pull()).rejects.toMatchObject({ status: 404, revision });
  });
  it('rejects a missing empty-state revision and retains conflict metadata', async () => {
    const api = new RevaAPI(
      'test',
      vi
        .fn<typeof fetch>()
        .mockResolvedValueOnce(new Response('', { status: 404 }))
        .mockResolvedValueOnce(new Response('', { status: 409, headers: { 'X-State-Revision': '7' } })),
    );
    await expect(api.pull()).rejects.toMatchObject({ revision: null });
    await expect(api.push(seed(), 2)).rejects.toMatchObject({ status: 409, revision: 7 });
  });
  it('uploads untouched original bytes under a SHA256 filename ID and safe ASCII metadata', async () => {
    const filename = 'Jordan’s résumé.pdf',
      bytes = new Uint8Array([0, 255, 3, 17]);
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(null, { status: 204 }));
    await new RevaAPI('test', fetcher).uploadAttachment(
      filename,
      new Blob([bytes], { type: 'application/pdf' }),
    );
    const [path, options] = fetcher.mock.calls[0];
    expect(path).toBe(`/v1/attachments/${await attachmentID(filename)}`);
    expect(options!.headers).toMatchObject({
      'X-Filename': 'Jordan_s r_sum_.pdf',
      'Content-Type': 'application/pdf',
    });
    expect(new Uint8Array(await (options!.body as Blob).arrayBuffer())).toEqual(bytes);
    expect(attachmentMetadataName('../bad\nfile')).toBe('document');
    expect(uploadContentType('audio/webm;codecs=opus')).toBe('audio/webm');
    expect(uploadContentType('text/html')).toBe('application/octet-stream');
  });
  it('restores binary original bytes and rejects unsafe source paths without fetching', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(
        new Response(new Uint8Array([1, 0, 250]), { headers: { 'Content-Type': 'audio/webm' } }),
      );
    const api = new RevaAPI('test', fetcher),
      blob = await api.attachment('source.webm');
    expect(blob.type).toBe('audio/webm');
    expect(new Uint8Array(await blob.arrayBuffer())).toEqual(new Uint8Array([1, 0, 250]));
    await expect(api.attachment('../other')).rejects.toThrow('filename');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('rejects malformed snapshots and bounds streamed response bytes', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response(JSON.stringify({ revision: 1, snapshot: { schemaVersion: 999 } })));
    await expect(new RevaAPI('test', fetcher).pull()).rejects.toThrow('schemaVersion');
    await expect(boundedBytes(new Response('12345'), 4)).rejects.toThrow('size limit');
    await expect(
      boundedBytes(new Response('small', { headers: { 'Content-Length': '100' } }), 10),
    ).rejects.toThrow('size limit');
  });
});

// MARK: - Provider schemas and authentic media types are validated before publication.
describe('provider wire validation', () => {
  it('sends browser audio under its actual container type and validates returned segments', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(
        JSON.stringify({
          text: 'Fictional speech',
          segments: [{ id: 's1', speaker: 'Speaker', text: 'Fictional speech', start: 0, end: 2 }],
          model: 'mock',
        }),
      ),
    );
    const result = await new RevaAPI('test', fetcher).transcribe(
      'recording.webm',
      new Blob(['synthetic'], { type: 'audio/webm;codecs=opus' }),
    );
    expect(result.segments[0].end).toBe(2);
    expect(fetcher.mock.calls[0][1]!.headers).toMatchObject({ 'Content-Type': 'audio/webm' });
  });
  it('fails malformed provider response shapes and reports configured-service errors', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify({ summary: null, model: 'mock' })))
      .mockResolvedValueOnce(new Response('', { status: 503 }));
    const api = new RevaAPI('test', fetcher);
    await expect(api.summarize(seed().records[0])).rejects.toThrow('invalid text');
    await expect(api.providers()).rejects.toBeInstanceOf(APIError);
  });
});
