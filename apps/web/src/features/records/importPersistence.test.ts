// Purpose: Verify imported originals and their records publish together despite failed save retries.
// Inputs: Synthetic records and two stores sharing an isolated fake IndexedDB database.
// Outputs: Assertions for unchanged state, absent abandoned keys, and byte-exact successful imports.
// Side effects: Test-owned fake browser storage only; no provider requests or real patient data.

import { IDBFactory } from 'fake-indexeddb';
import { describe, expect, it } from 'vitest';
import { IndexedDBRepository } from '../../core/repository';
import { RevaStore } from '../../core/store';
import { seed, transport } from '../../core/__tests__/fixtures';

// MARK: - Inspect the actual attachment store without the bundled-original fallback
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

// MARK: - A stale tab cannot leak originals; a refreshed store publishes exactly one import
describe('atomic document imports', () => {
  it('leaves no attachment keys after three stale retries and saves exact bytes after refreshing', async () => {
    const factory = new IDBFactory();
    const name = 'atomic-import';
    const first = new IndexedDBRepository(name, factory);
    const second = new IndexedDBRepository(name, factory);
    await first.commit(seed(), 0);
    const stale = new RevaStore(first, () => transport());
    const current = new RevaStore(second, () => transport());
    await stale.initialize();
    await current.initialize();
    await current.mutate((draft) => {
      draft.profile.name = 'Newer fictional tab edit';
    });
    const existing = await second.load();
    const bytes = new Uint8Array([0, 255, 10, 128, 42]);
    const original = new Blob([bytes], { type: 'application/pdf' });
    const imported = {
      ...seed().records[0],
      id: 'synthetic-import',
      title: 'Fictional imported source',
      sourceFilename: 'successful-import.pdf',
    };
    for (let retry = 0; retry < 3; retry++) {
      await expect(
        stale.saveRecord({ ...imported, sourceFilename: `abandoned-${retry}.pdf` }, undefined, original),
      ).rejects.toThrow('another tab');
      expect(await attachmentKeys(factory, name)).toEqual([]);
      expect(await second.load()).toEqual(existing);
    }
    const refreshed = new RevaStore(first, () => transport());
    await refreshed.initialize();
    await refreshed.saveRecord(imported, undefined, original);
    expect(await attachmentKeys(factory, name)).toEqual(['successful-import.pdf']);
    const saved = (await second.load())!.snapshot;
    expect(saved.records.filter((record) => record.id === imported.id)).toHaveLength(1);
    expect(saved.records.find((record) => record.id === imported.id)!.sourceFilename).toBe(
      'successful-import.pdf',
    );
    expect(new Uint8Array(await (await second.getAttachment('successful-import.pdf')).arrayBuffer())).toEqual(
      bytes,
    );
    expect(saved.profile.name).toBe('Newer fictional tab edit');
    await first.close();
    await second.close();
  });

  it('does not stage an original when its source filename is invalid', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('invalid-import', factory);
    await repository.commit(seed(), 0);
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    const existing = await repository.load();
    await expect(
      store.saveRecord(
        { ...seed().records[0], id: 'invalid-import', sourceFilename: '../invalid.pdf' },
        undefined,
        new Blob(['original']),
      ),
    ).rejects.toThrow();
    expect(await attachmentKeys(factory, 'invalid-import')).toEqual([]);
    expect(await repository.load()).toEqual(existing);
    await repository.close();
  });
});
