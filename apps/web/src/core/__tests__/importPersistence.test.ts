// Purpose: Verify imported records and unchanged originals publish atomically through the real store.
// Inputs: Isolated IndexedDB repositories, competing revisions and injected transaction failures.
// Outputs: Assertions that failed retries leak no original keys and successful imports retain originals.
// Side effects: Fake IndexedDB only; no real browser data, network, or provider calls.

import { IDBFactory, IDBObjectStore } from 'fake-indexeddb';
import { describe, expect, it, vi } from 'vitest';
import { IndexedDBRepository } from '../repository';
import { RevaStore } from '../store';
import { seed, transport } from './fixtures';

// MARK: - Inspect stored keys directly so missing-file fallback cannot conceal a leaked original
async function attachmentKeys(factory: IDBFactory, name: string): Promise<IDBValidKey[]> {
  const db = await new Promise<IDBDatabase>((resolve, reject) => {
    const request = factory.open(name, 1);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  try {
    return await new Promise((resolve, reject) => {
      const transaction = db.transaction('attachments', 'readonly');
      const request = transaction.objectStore('attachments').getAllKeys();
      transaction.oncomplete = () => resolve(request.result);
      transaction.onabort = () => reject(transaction.error);
    });
  } finally {
    db.close();
  }
}
function imported(index: number) {
  return {
    ...seed().records[0],
    id: `new-import-${index}`,
    sourceFilename: `new-import-${index}.txt`,
    mimeType: 'text/plain',
    isDemo: false,
    version: 1,
  };
}

// MARK: - The same original can be retried without publishing orphaned bytes on any failed attempt
describe('atomic imported source saving', () => {
  it('leaks no keys across three stale-tab retries, then saves exactly one unchanged original', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('import-race', factory);
    const otherTab = new IndexedDBRepository('import-race', factory);
    const original = new Blob([new Uint8Array([0, 255, 13, 10, 65])], { type: 'text/plain' });
    const retained = new Blob(['Previously retained original']);
    await repository.commit(seed(), 0, new Map([['retained.txt', retained]]));
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    const before = structuredClone(store.getState().snapshot);
    const winner = seed();
    winner.profile.careNotes = 'Saved by another tab';
    await otherTab.commit(winner, 1);

    for (let attempt = 0; attempt < 3; attempt++) {
      await expect(store.saveRecord(imported(attempt), undefined, original)).rejects.toThrow('another tab');
      expect(store.getState().snapshot).toEqual(before);
      expect(await repository.load()).toEqual({ snapshot: winner, revision: 2 });
      expect(await attachmentKeys(factory, 'import-race')).toEqual(['retained.txt']);
    }

    const refreshed = new RevaStore(repository, () => transport());
    await refreshed.initialize();
    const record = imported(3);
    await refreshed.saveRecord(record, undefined, original);
    expect(await attachmentKeys(factory, 'import-race')).toEqual(['new-import-3.txt', 'retained.txt']);
    expect(refreshed.getState().snapshot!.records.filter((item) => item.id === record.id)).toHaveLength(1);
    expect(await (await repository.getAttachment(record.sourceFilename)).arrayBuffer()).toEqual(
      await original.arrayBuffer(),
    );
    await refreshed.deleteRecord(record.id);
    expect(await attachmentKeys(factory, 'import-race')).toEqual(['new-import-3.txt', 'retained.txt']);
    expect(await (await repository.getAttachment('retained.txt')).text()).toBe(await retained.text());
    await repository.close();
    await otherTab.close();
  });

  it('rolls back an original already queued for writing when snapshot storage fails, then retries', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('import-abort', factory);
    await repository.commit(seed(), 0);
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    const before = structuredClone(store.getState().snapshot);
    const record = imported(0);
    const original = new Blob(['Unchanged original']);
    const put = IDBObjectStore.prototype.put;
    const failure = vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementation(function (
      this: IDBObjectStore,
      value,
      key,
    ) {
      if (this.name === 'snapshots') throw new DOMException('Storage is full', 'QuotaExceededError');
      return put.call(this, value, key);
    });
    try {
      await expect(store.saveRecord(record, undefined, original)).rejects.toThrow('Storage is full');
    } finally {
      failure.mockRestore();
    }
    expect(store.getState().snapshot).toEqual(before);
    expect((await repository.load())!.snapshot).toEqual(before);
    expect(await attachmentKeys(factory, 'import-abort')).toEqual([]);
    await store.saveRecord(record, undefined, original);
    expect(await attachmentKeys(factory, 'import-abort')).toEqual([record.sourceFilename]);
    expect(await (await repository.getAttachment(record.sourceFilename)).text()).toBe('Unchanged original');
    await repository.close();
  });

  it('keeps an existing source and original when its expected source version is stale', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('import-version', factory);
    const data = seed();
    const record = data.records[0];
    await repository.commit(data, 0, new Map([[record.sourceFilename!, new Blob(['Valid original'])]]));
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    await expect(
      store.saveRecord({ ...record, title: 'Unsaved title' }, record.version - 1, new Blob(['Replacement'])),
    ).rejects.toThrow();
    expect(store.getState().snapshot).toEqual(data);
    expect(await (await repository.getAttachment(record.sourceFilename!)).text()).toBe('Valid original');
    await repository.close();
  });
});
