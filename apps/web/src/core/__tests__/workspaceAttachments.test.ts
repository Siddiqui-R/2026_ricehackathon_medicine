// Purpose: Keep source previews and saved visit audio inside their active account or demo workspace.
// Inputs: Separate fake IndexedDB databases, original blobs, mocked sync and failed transactions.
// Outputs: Assertions for repository isolation, syncable audio, atomic rollback and safe recording retries.
// Side effects: Fake IndexedDB and mocked transports only; no browser data or outbound requests.

import { IDBFactory, IDBObjectStore } from 'fake-indexeddb';
import { describe, expect, it, vi } from 'vitest';
import { emptyPersonalSnapshot } from '../account';
import type { AppSnapshot, VisitRecording } from '../models';
import { IndexedDBRepository } from '../repository';
import { RevaStore, type APITransport } from '../store';
import { syncMarkerKey } from '../syncMarker';
import { fakeStorage, seed, testUser, transport } from './fixtures';

function personalSnapshot(): AppSnapshot {
  const snapshot = emptyPersonalSnapshot(testUser);
  snapshot.visits = [{ ...seed().visits[0], report: null }];
  return snapshot;
}
function recording(): VisitRecording {
  return {
    id: 'private-recording',
    visitID: personalSnapshot().visits[0].id,
    title: 'Saved visit conversation',
    createdAt: '2026-09-12T12:00:00Z',
    duration: 20,
    audioFilename: 'private-recording.webm',
    segments: [],
    summary: 'Original personal notes',
    isSample: false,
    status: 'saved',
  };
}
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
function accountStore(repository: IndexedDBRepository, api: APITransport = transport()) {
  return new RevaStore(repository, () => api, {
    mode: 'account',
    token: 'synthetic-account-token',
    user: testUser,
    storage: fakeStorage({
      [syncMarkerKey(testUser.id)]: JSON.stringify({ serverRevision: 3, localRevision: 1 }),
    }),
    redirect: vi.fn(),
    syncDelay: 5,
  });
}

// MARK: - The active store supplies originals, even when another workspace has the same filename
describe('workspace attachment ownership', () => {
  it('keeps bound preview reads in their original account or demo repository', async () => {
    const factory = new IDBFactory();
    const first = new IndexedDBRepository('first-account', factory);
    const second = new IndexedDBRepository('second-account', factory);
    const demo = new IndexedDBRepository('demo', factory);
    const filename = 'same-source.txt';
    await first.commit(personalSnapshot(), 0, new Map([[filename, new Blob(['first account'])]]));
    await second.commit(personalSnapshot(), 0, new Map([[filename, new Blob(['second account'])]]));
    await demo.commit(personalSnapshot(), 0, new Map([[filename, new Blob(['fictional demo'])]]));
    const { getAttachment: firstRead } = accountStore(first);
    const pendingFirstRead = firstRead(filename);
    const { getAttachment: secondRead } = accountStore(second);
    const { getAttachment: demoRead } = new RevaStore(demo, () => transport());
    expect(await (await secondRead(filename)).text()).toBe('second account');
    expect(await (await demoRead(filename)).text()).toBe('fictional demo');
    expect(await (await pendingFirstRead).text()).toBe('first account');
    expect(await (await firstRead(filename)).text()).toBe('first account');
    await Promise.all([first.close(), second.close(), demo.close()]);
  });

  it('saves account documents and audio where previews, transcription and auto-sync read them', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('account-capture', factory);
    const demo = new IndexedDBRepository('demo-capture', factory);
    await repository.commit(personalSnapshot(), 0);
    await demo.commit(personalSnapshot(), 0);
    const uploadAttachment = vi.fn<APITransport['uploadAttachment']>(async () => {});
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const transcribe = vi.fn<APITransport['transcribe']>(async () => ({
      text: 'Words from the account recording.',
      model: 'mock-transcription',
      segments: [
        { id: 'segment-1', speaker: 'Speaker', start: 0, end: 10, text: 'Words from the account recording.' },
      ],
    }));
    const store = accountStore(
      repository,
      transport({
        pull: async () => ({ revision: 3, snapshot: personalSnapshot() }),
        uploadAttachment,
        push,
        transcribe,
      }),
    );
    await store.initialize();
    const source = {
      ...seed().records[0],
      id: 'account-source',
      sourceFilename: 'account-source.txt',
      mimeType: 'text/plain',
      isDemo: false,
      version: 1,
    };
    const document = new Blob(['account document'], { type: 'text/plain' });
    const audio = new Blob([new Uint8Array([0, 255, 64, 128])], { type: 'audio/webm' });
    await store.saveRecord(source, undefined, document);
    const savedRecording = recording();
    const { saveRecording, getAttachment } = store;
    await saveRecording(savedRecording, audio);
    expect(await (await getAttachment(source.sourceFilename)).text()).toBe('account document');
    expect(await (await getAttachment(savedRecording.audioFilename!)).arrayBuffer()).toEqual(
      await audio.arrayBuffer(),
    );
    await vi.waitFor(() => expect(push.mock.calls.at(-1)?.[0].recordings).toEqual([savedRecording]));
    const uploadedAudio = uploadAttachment.mock.calls.find(
      ([filename]) => filename === savedRecording.audioFilename,
    )?.[1];
    expect(uploadedAudio).toBeDefined();
    expect(await uploadedAudio!.arrayBuffer()).toEqual(await audio.arrayBuffer());
    await vi.waitFor(() => expect(store.getState().busy).toBe(false));
    await store.transcribeRecording(savedRecording.id);
    expect(transcribe.mock.calls[0][0]).toBe(savedRecording.audioFilename);
    expect(await transcribe.mock.calls[0][1].arrayBuffer()).toEqual(await audio.arrayBuffer());
    await vi.waitFor(() =>
      expect(push.mock.calls.at(-1)?.[0].recordings[0].segments[0]?.text).toBe(
        'Words from the account recording.',
      ),
    );
    expect(await attachmentKeys(factory, 'demo-capture')).toEqual([]);
    expect((await demo.load())!.snapshot.recordings).toEqual([]);
    await Promise.all([repository.close(), demo.close()]);
  });
});

// MARK: - Metadata and audio survive together; failed attempts never leave orphaned audio
describe('atomic recording capture', () => {
  it('keeps newer data on stale-tab retries and saves one original after reloading', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('recording-race', factory);
    const otherTab = new IndexedDBRepository('recording-race', factory);
    await repository.commit(personalSnapshot(), 0);
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    const winner = personalSnapshot();
    winner.profile.careNotes = 'Saved in another tab';
    await otherTab.commit(winner, 1);
    const audio = new Blob(['retained audio'], { type: 'audio/webm' });
    for (let attempt = 0; attempt < 3; attempt++) {
      await expect(store.saveRecording(recording(), audio)).rejects.toThrow('another tab');
      expect(await attachmentKeys(factory, 'recording-race')).toEqual([]);
      expect((await repository.load())!.snapshot).toEqual(winner);
    }
    const refreshed = new RevaStore(repository, () => transport());
    await refreshed.initialize();
    await refreshed.saveRecording(recording(), audio);
    expect((await repository.load())!.snapshot.recordings).toEqual([recording()]);
    expect(await attachmentKeys(factory, 'recording-race')).toEqual(['private-recording.webm']);
    expect(await (await refreshed.getAttachment('private-recording.webm')).text()).toBe('retained audio');
    await Promise.all([repository.close(), otherTab.close()]);
  });

  it('rolls back queued audio if the metadata write fails and safely retries the same capture', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('recording-abort', factory);
    await repository.commit(personalSnapshot(), 0);
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    const audio = new Blob(['unchanged original audio'], { type: 'audio/webm' });
    const put = IDBObjectStore.prototype.put;
    const failure = vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementation(function (
      this: IDBObjectStore,
      ...args: Parameters<IDBObjectStore['put']>
    ) {
      if (this.name === 'snapshots') throw new DOMException('Storage full', 'QuotaExceededError');
      return put.apply(this, args);
    });
    try {
      await expect(store.saveRecording(recording(), audio)).rejects.toThrow('Storage full');
    } finally {
      failure.mockRestore();
    }
    expect((await repository.load())!.snapshot.recordings).toEqual([]);
    expect(store.getState().snapshot!.recordings).toEqual([]);
    expect(await attachmentKeys(factory, 'recording-abort')).toEqual([]);
    await store.saveRecording(recording(), audio);
    expect((await repository.load())!.snapshot.recordings).toEqual([recording()]);
    expect(await (await store.getAttachment('private-recording.webm')).text()).toBe(
      'unchanged original audio',
    );
    await repository.close();
  });

  it('does not overwrite saved audio or publish audio for a deleted visit', async () => {
    const factory = new IDBFactory();
    const repository = new IndexedDBRepository('recording-guards', factory);
    await repository.commit(personalSnapshot(), 0);
    const store = new RevaStore(repository, () => transport());
    await store.initialize();
    const original = new Blob(['first original'], { type: 'audio/webm' });
    await store.saveRecording(recording(), original);
    await expect(
      store.saveRecording({ ...recording(), summary: 'replacement' }, new Blob(['replacement'])),
    ).rejects.toThrow('already saved');
    expect(await (await store.getAttachment('private-recording.webm')).text()).toBe('first original');
    expect((await repository.load())!.snapshot.recordings).toEqual([recording()]);
    await expect(
      store.saveRecording(
        {
          ...recording(),
          id: 'missing-visit-recording',
          visitID: 'deleted-visit',
          audioFilename: 'orphan.webm',
        },
        original,
      ),
    ).rejects.toThrow('visit is no longer available');
    expect(await attachmentKeys(factory, 'recording-guards')).toEqual(['private-recording.webm']);
    await repository.close();
  });
});
