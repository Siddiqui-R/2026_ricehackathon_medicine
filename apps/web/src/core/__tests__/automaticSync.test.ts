// Purpose: Exercise automatic account transfers under offline, concurrent-edit and browser lifecycle races.
// Inputs: A stateful synthetic server, local repositories and controllable clocks/downloads.
// Outputs: Assertions for convergence, original preservation, retries and session-safe cleanup.
// Side effects: Fake timers and in-memory state only; no provider or network requests.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { APIError } from '../api';
import { emptyPersonalSnapshot } from '../account';
import type { AppSnapshot, ServerState } from '../models';
import { RevaStore, type APITransport } from '../store';
import { capabilities, deferred, fakeStorage, MemoryRepository, seed, testUser, transport } from './fixtures';

// MARK: - A stateful server rejects stale writes instead of hiding revision races in fixed mocks.
function setup(snapshot = emptyPersonalSnapshot(testUser)) {
  let remote: ServerState = { revision: 1, snapshot: structuredClone(snapshot) };
  const repository = new MemoryRepository();
  repository.saved = { revision: 1, snapshot: structuredClone(snapshot) };
  repository.syncBase = structuredClone(remote);
  const files = new Map<string, Blob>();
  const api = transport({
    pull: vi.fn(async () => structuredClone(remote)),
    push: vi.fn(async (next, revision) => {
      if (revision !== remote.revision) throw new APIError(409, remote.revision);
      remote = { revision: revision + 1, snapshot: structuredClone(next) };
      return remote.revision;
    }),
    attachment: vi.fn(async (filename) => files.get(filename)!),
    uploadAttachment: vi.fn(async (filename, blob) => {
      files.set(filename, blob);
    }),
  });
  const store = new RevaStore(repository, () => api, {
    mode: 'account',
    token: 'fictional-account-token',
    user: testUser,
    storage: fakeStorage(),
    redirect: vi.fn(),
    syncDelay: 10,
    syncInterval: 1000,
  });
  return {
    store,
    repository,
    api,
    files,
    remote: () => remote,
    update: (edit: (snapshot: AppSnapshot) => void) => {
      edit(remote.snapshot);
      remote.revision += 1;
    },
  };
}
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

// MARK: - Background synchronization converges without a manual control or blocking local editing.
describe('automatic account synchronization lifecycle', () => {
  it('refreshes unavailable AI capabilities on the polling TTL without checking on every edit', async () => {
    vi.useFakeTimers();
    const { store, api } = setup();
    let configured = false;
    api.providers = vi.fn(async () => ({
      ...structuredClone(capabilities),
      gemini: { ...capabilities.gemini, configured },
    }));
    await store.initialize();
    const stop = store.startAutomaticSync();
    expect(store.getState().providers?.gemini.configured).toBe(false);
    await store.mutate((snapshot) => {
      snapshot.profile.careNotes = 'A local edit';
    });
    await vi.advanceTimersByTimeAsync(20);
    expect(api.providers).toHaveBeenCalledTimes(1);
    configured = true;
    await vi.advanceTimersByTimeAsync(60_000);
    expect(api.providers).toHaveBeenCalledTimes(2);
    expect(store.getState().providers?.gemini.configured).toBe(true);
    expect(store.getState().connectedAI).toBe(false);
    stop();
  });
  it.each(['focus', 'online'])(
    'refreshes newly configured AI on %s before the polling TTL',
    async (event) => {
      const target = new EventTarget();
      vi.stubGlobal('addEventListener', target.addEventListener.bind(target));
      vi.stubGlobal('removeEventListener', target.removeEventListener.bind(target));
      const { store, api } = setup();
      let configured = false;
      api.providers = vi.fn(async () => ({
        ...structuredClone(capabilities),
        gemini: { ...capabilities.gemini, configured },
      }));
      await store.initialize();
      const stop = store.startAutomaticSync();
      configured = true;
      target.dispatchEvent(new Event(event));
      await vi.waitFor(() => expect(store.getState().providers?.gemini.configured).toBe(true));
      expect(api.providers).toHaveBeenCalledTimes(2);
      expect(store.getState().connectedAI).toBe(false);
      stop();
    },
  );
  it('pulls other-device edits while idle and cleans up polling on unmount', async () => {
    vi.useFakeTimers();
    const { store, api, update } = setup();
    await store.initialize();
    const stop = store.startAutomaticSync();
    update((snapshot) => {
      snapshot.profile.careNotes = 'Written on another device';
    });
    await vi.advanceTimersByTimeAsync(1000);
    expect(store.getState().snapshot?.profile.careNotes).toBe('Written on another device');
    expect(api.push).not.toHaveBeenCalled();
    stop();
    const calls = vi.mocked(api.pull).mock.calls.length;
    await vi.advanceTimersByTimeAsync(5000);
    expect(api.pull).toHaveBeenCalledTimes(calls);
  });
  it('automatically refreshes on focus and reconnect', async () => {
    const target = new EventTarget();
    vi.stubGlobal('addEventListener', target.addEventListener.bind(target));
    vi.stubGlobal('removeEventListener', target.removeEventListener.bind(target));
    const { store, update } = setup();
    await store.initialize();
    const stop = store.startAutomaticSync();
    update((snapshot) => {
      snapshot.profile.careNotes = 'Focus update';
    });
    target.dispatchEvent(new Event('focus'));
    await vi.waitFor(() => expect(store.getState().snapshot?.profile.careNotes).toBe('Focus update'));
    update((snapshot) => {
      snapshot.profile.careNotes = 'Reconnect update';
    });
    target.dispatchEvent(new Event('online'));
    await vi.waitFor(() => expect(store.getState().snapshot?.profile.careNotes).toBe('Reconnect update'));
    stop();
  });
  it('keeps an offline first login editable and sends the new personal snapshot after reconnect', async () => {
    vi.useFakeTimers();
    const repository = new MemoryRepository();
    repository.saved = null;
    let offline = true;
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const api = transport({
      health: async () => {
        if (offline) throw new Error('Offline fixture');
        return 'Connected';
      },
      push,
    });
    const store = new RevaStore(repository, () => api, {
      mode: 'account',
      token: 'fictional',
      user: testUser,
      storage: fakeStorage(),
      syncDelay: 10,
    });
    await store.initialize();
    expect(store.getState()).toMatchObject({ loading: false, syncStatus: 'offline', error: null });
    await store.mutate((snapshot) => {
      snapshot.profile.careNotes = 'Saved while offline';
    });
    offline = false;
    await vi.advanceTimersByTimeAsync(20);
    expect(push).toHaveBeenCalledTimes(1);
    expect(push.mock.calls[0][0].profile).toMatchObject({ isDemo: false, careNotes: 'Saved while offline' });
  });
  it('retains local notes changed during an attachment download and uploads the combined snapshot', async () => {
    const { store, api, repository, files, remote, update } = setup();
    await store.initialize();
    const download = deferred<Blob>();
    api.attachment = vi.fn(() => download.promise);
    const record = { ...seed().records[0], sourceFilename: 'new-remote.pdf' };
    files.set('new-remote.pdf', new Blob(['remote source']));
    update((snapshot) => {
      snapshot.records.push(record);
    });
    const sync = store.pullFromServer();
    await vi.waitFor(() => expect(api.attachment).toHaveBeenCalled());
    await store.mutate((snapshot) => {
      snapshot.profile.careNotes = 'Typed during download';
    });
    download.resolve(new Blob(['remote source']));
    await sync;
    expect(remote().snapshot.profile.careNotes).toBe('Typed during download');
    expect(remote().snapshot.records).toHaveLength(1);
    expect(await repository.attachments.get('new-remote.pdf')!.text()).toBe('remote source');
    store.startAutomaticSync()();
  });
  it('restores the durable baseline after reload so independent offline changes merge', async () => {
    const { repository, api, remote, update } = setup();
    repository.saved!.snapshot.profile.careNotes = 'Offline before closing browser';
    repository.saved!.revision += 1;
    update((snapshot) => {
      snapshot.profile.conditions.push('Remote fixture');
    });
    const store = new RevaStore(repository, () => api, {
      mode: 'account',
      token: 'fixture',
      user: testUser,
      storage: fakeStorage(),
      syncDelay: 10,
    });
    await store.initialize();
    expect(remote().snapshot.profile).toMatchObject({
      careNotes: 'Offline before closing browser',
      conditions: ['Remote fixture'],
    });
    expect(repository.syncBase).toEqual(remote());
  });
  it('uploads changed originals under immutable names, including same-size replacements', async () => {
    const snapshot = emptyPersonalSnapshot(testUser);
    snapshot.records = [{ ...seed().records[0], sourceFilename: 'scan.pdf' }];
    const { store, repository, files, remote, api } = setup(snapshot);
    repository.attachments.set('scan.pdf', new Blob(['old!']));
    files.set('scan.pdf', new Blob(['old!']));
    await store.initialize();
    await store.saveRecord(
      { ...store.getState().snapshot!.records[0], text: 'First replacement' },
      undefined,
      new Blob(['new!']),
    );
    await store.pushToServer();
    const firstName = remote().snapshot.records[0].sourceFilename!;
    expect(firstName).toMatch(/^reva-[a-f0-9]{64}\.pdf$/);
    expect(await files.get(firstName)!.text()).toBe('new!');
    expect(await files.get('scan.pdf')!.text()).toBe('old!');
    await store.saveRecord(
      { ...store.getState().snapshot!.records[0], text: 'Second replacement' },
      undefined,
      new Blob(['next']),
    );
    await store.pushToServer();
    const secondName = remote().snapshot.records[0].sourceFilename!;
    expect(secondName).not.toBe(firstName);
    expect(await files.get(firstName)!.text()).toBe('new!');
    expect(await files.get(secondName)!.text()).toBe('next');
    expect(api.uploadAttachment).toHaveBeenCalledTimes(2);
    store.startAutomaticSync()();
  });
  it('downloads a legacy original changed remotely and keeps a separate usable copy of local bytes', async () => {
    const snapshot = emptyPersonalSnapshot(testUser);
    snapshot.records = [{ ...seed().records[0], sourceFilename: 'legacy.pdf' }];
    const { store, repository, files, remote, update } = setup(snapshot);
    repository.attachments.set('legacy.pdf', new Blob(['local original']));
    files.set('legacy.pdf', new Blob(['local original']));
    await store.initialize();
    update((next) => {
      next.records[0].text = 'Updated remote source';
      next.records[0].version += 1;
    });
    files.set('legacy.pdf', new Blob(['remote original']));
    await store.pullFromServer();
    const canonical = remote().snapshot.records.find((record) => record.id === snapshot.records[0].id)!;
    const recovery = remote().snapshot.records.find((record) => record.id.startsWith('sync-copy-'))!;
    expect(canonical.text).toBe('Updated remote source');
    expect(await files.get(canonical.sourceFilename!)!.text()).toBe('remote original');
    expect(recovery.text).toBe(snapshot.records[0].text);
    expect(await files.get(recovery.sourceFilename!)!.text()).toBe('local original');
    expect(recovery.title).toContain('saved on another device');
  });
  it('recovers concurrent local-tab edits before committing a new mutation', async () => {
    const { store, repository } = setup();
    await store.initialize();
    repository.saved!.snapshot.profile.conditions.push('Other tab');
    repository.saved!.revision += 1;
    await store.mutate((snapshot) => {
      snapshot.profile.careNotes = 'This tab';
    });
    expect(store.getState().snapshot?.profile).toMatchObject({
      careNotes: 'This tab',
      conditions: ['Other tab'],
    });
    store.startAutomaticSync()();
  });
  it('does not start polling or upload a demo merely because its token changed', async () => {
    vi.useFakeTimers();
    const api = transport({ pull: vi.fn(), push: vi.fn() });
    const store = new RevaStore(new MemoryRepository(), () => api);
    await store.initialize();
    store.setToken('another-demo-token');
    const stop = store.startAutomaticSync();
    await store.mutate((snapshot) => {
      snapshot.profile.careNotes = 'Local demo';
    });
    await vi.advanceTimersByTimeAsync(120_000);
    expect(api.pull).not.toHaveBeenCalled();
    expect(api.push).not.toHaveBeenCalled();
    stop();
  });
});
