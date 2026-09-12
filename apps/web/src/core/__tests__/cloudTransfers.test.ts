import { expect, it, vi } from 'vitest';
import { RevaAPI } from '../api';
it('stages a large original in bounded chunks before replacing its stable attachment', async () => {
  const fetcher = vi.fn<typeof fetch>().mockImplementation(async () => new Response(null, { status: 204 }));
  const api = new RevaAPI('fictional-token', fetcher, true);
  await api.uploadAttachment(
    'fictional.txt',
    new Blob([new Uint8Array(4 * 1024 * 1024)], { type: 'text/plain' }),
  );
  expect(fetcher).toHaveBeenCalledTimes(3);
  const calls = fetcher.mock.calls;
  expect(String(calls[0][0])).toContain('/v1/transfers/');
  expect((calls[0][1]?.body as Blob).size).toBe(3 * 1024 * 1024);
  expect((calls[1][1]?.body as Blob).size).toBe(1024 * 1024);
  expect(calls[2][1]?.body).toBeUndefined();
  expect(new Headers(calls[2][1]?.headers).get('X-Reva-Upload')).toBeTruthy();
});
it('downloads ranges with an immutable content tag and rejects mixed versions', async () => {
  const fetcher = vi
    .fn<typeof fetch>()
    .mockResolvedValueOnce(
      new Response('abc', { status: 206, headers: { 'Content-Range': 'bytes 0-2/6', ETag: '"one"' } }),
    )
    .mockResolvedValueOnce(
      new Response('def', { status: 206, headers: { 'Content-Range': 'bytes 3-5/6', ETag: '"one"' } }),
    );
  expect(await (await new RevaAPI('token', fetcher, true).attachment('fixture.txt')).text()).toBe('abcdef');
  expect(new Headers(fetcher.mock.calls[1][1]?.headers).get('If-Match')).toBe('"one"');
  const mixed = vi
    .fn<typeof fetch>()
    .mockResolvedValueOnce(
      new Response('abc', { status: 206, headers: { 'Content-Range': 'bytes 0-2/6', ETag: '"one"' } }),
    )
    .mockResolvedValueOnce(
      new Response('xyz', { status: 206, headers: { 'Content-Range': 'bytes 3-5/6', ETag: '"two"' } }),
    );
  await expect(new RevaAPI('token', mixed, true).attachment('fixture.txt')).rejects.toThrow('changed');
});
