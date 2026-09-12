// Purpose: Exercise actual IndexedDB transactions and bundled-original validation in an isolated fake browser.
// Inputs: Synthetic snapshots, original Blobs and deliberately corrupt or competing persisted values.
// Outputs: Assertions for restart recovery, atomic CAS, original retention and no corrupt-data fallback.
// Side effects: Fake IndexedDB databases only; no real browser storage or outbound requests.
import { IDBFactory } from 'fake-indexeddb';
import { describe, expect, it, vi } from 'vitest';
import { IndexedDBRepository } from '../repository.ts';
import { seed } from './fixtures.ts';

// MARK: - Direct corruption injection models damaged persisted bytes instead of mocking repository behavior.
async function putRaw(factory: IDBFactory, name: string, store: string, key: string, value: unknown) {
  const db = await new Promise<IDBDatabase>((resolve, reject) => {
    const request = factory.open(name, 1);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction(store, 'readwrite');
    transaction.objectStore(store).put(value, key);
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error);
  });
  db.close();
}
describe('IndexedDB durability and ownership of writes', () => {
  it('restores the entire snapshot and original bytes after a repository restart', async () => {
    const factory = new IDBFactory(),
      first = new IndexedDBRepository('restart', factory),
      data = seed();
    const bytes = new Uint8Array([0, 255, 128, 64]);
    expect(await first.load()).toBeNull();
    await first.commit(data, 0, new Map([['scan.pdf', new Blob([bytes], { type: 'application/pdf' })]]));
    await first.close();
    const second = new IndexedDBRepository('restart', factory);
    expect(await second.load()).toEqual({ snapshot: data, revision: 1 });
    expect(new Uint8Array(await (await second.getAttachment('scan.pdf')).arrayBuffer())).toEqual(bytes);
    await second.close();
  });
  it('only allows one tab to commit a competing revision and retains the winning snapshot', async () => {
    const factory = new IDBFactory(),
      first = new IndexedDBRepository('tabs', factory),
      second = new IndexedDBRepository('tabs', factory);
    await first.commit(seed(), 0);
    const left = seed(),
      right = seed();
    left.profile.name = 'Left fictional edit';
    right.profile.name = 'Right fictional edit';
    const results = await Promise.allSettled([first.commit(left, 1), second.commit(right, 1)]);
    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    const rejected = results.find((result) => result.status === 'rejected') as PromiseRejectedResult;
    expect(rejected.reason.message).toContain('another tab');
    expect((await first.load())!.revision).toBe(2);
    await first.close();
    await second.close();
  });
  it('keeps old originals and state when a conflicting pull would replace both', async () => {
    const factory = new IDBFactory(),
      repository = new IndexedDBRepository('atomic', factory);
    const data = seed();
    await repository.commit(data, 0, new Map([['original.pdf', new Blob(['old original'])]]));
    await expect(
      repository.commit({ ...data, records: [] }, 0, new Map([['original.pdf', new Blob(['replacement'])]])),
    ).rejects.toThrow('another tab');
    expect(await (await repository.getAttachment('original.pdf')).text()).toBe('old original');
    expect((await repository.load())!.snapshot.records.length).toBe(data.records.length);
    await repository.close();
  });
  it('surfaces corrupt snapshots without seed fetch or silent reset; explicit reset can recover', async () => {
    const factory = new IDBFactory(),
      fetcher = vi.fn<typeof fetch>(),
      repository = new IndexedDBRepository('corrupt', factory, fetcher);
    await repository.commit(seed(), 0);
    await putRaw(factory, 'corrupt', 'snapshots', 'current', {
      revision: 1,
      snapshot: { schemaVersion: 17 },
    });
    await expect(repository.load()).rejects.toThrow('schemaVersion');
    expect(fetcher).not.toHaveBeenCalled();
    await repository.reset(seed());
    expect((await repository.load())!.revision).toBe(2);
    await repository.close();
  });
  it('does not replace a corrupt saved original with a demo or SPA response', async () => {
    const factory = new IDBFactory(),
      fetcher = vi.fn<typeof fetch>(),
      repository = new IndexedDBRepository('bad-original', factory, fetcher);
    await repository.commit(seed(), 0);
    await putRaw(factory, 'bad-original', 'attachments', 'source.pdf', 'not a Blob');
    await expect(repository.getAttachment('source.pdf')).rejects.toThrow('invalid');
    expect(fetcher).not.toHaveBeenCalled();
    await repository.close();
  });
  it('only falls back to manifest-listed demo originals with matching byte hashes', async () => {
    const bytes = new TextEncoder().encode('fictional original'),
      hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), (byte) =>
        byte.toString(16).padStart(2, '0'),
      ).join('');
    const fetcher = vi.fn<typeof fetch>().mockImplementation(async (path) =>
      path === '/demo/fixture-manifest.json'
        ? new Response(
            JSON.stringify({
              synthetic: true,
              sources: [{ filename: 'demo.txt', sha256: hash, bytes: bytes.length, mimeType: 'text/plain' }],
            }),
          )
        : new Response(bytes),
    );
    const repository = new IndexedDBRepository('demo', new IDBFactory(), fetcher);
    expect(await (await repository.getAttachment('demo.txt')).text()).toBe('fictional original');
    await expect(repository.getAttachment('missing.pdf')).rejects.toThrow('missing');
    expect(fetcher.mock.calls.map((call) => call[0])).not.toContain('/demo/missing.pdf');
    await repository.close();
  });
  it('rejects a bundled fallback with different bytes, including an HTML SPA fallback', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            synthetic: true,
            sources: [
              { filename: 'demo.pdf', sha256: '0'.repeat(64), bytes: 5, mimeType: 'application/pdf' },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(new Response('<html>wrong content</html>'));
    const repository = new IndexedDBRepository('manifest-mismatch', new IDBFactory(), fetcher);
    await expect(repository.getAttachment('demo.pdf')).rejects.toThrow('manifest');
    await repository.close();
  });
});
