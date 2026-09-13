// Purpose: Verify the account-mode store reconciles with the server, auto-syncs and ends sessions safely.
// Inputs: A memory repository, a controllable API transport, a fake auth transport, fake Storage and a redirect spy.
// Outputs: Assertions for first-login snapshots, download, divergence, 401 handling, debounce, de-dup and account actions.
// Side effects: Test memory only; no request reaches a network, provider or real browser storage.
import { describe, expect, it, vi } from 'vitest';
import { APIError } from '../api.ts';
import { accountDatabaseName, DEMO_DATABASE, emptyPersonalSnapshot, initialsFor } from '../account.ts';
import { SESSION_KEY, type StoredSession } from '../session.ts';
import { RevaStore, SESSION_ENDED_NOTICE, SESSION_ENDED_PATH } from '../store.ts';
import { syncMarkerKey } from '../syncMarker.ts';
import type { APITransport } from '../store.ts';
import type { ServerState } from '../models.ts';
import type { AuthTransport } from '../auth.ts';
import {
  authTransport,
  deferred,
  fakeStorage,
  MemoryRepository,
  seed,
  testUser,
  transport,
} from './fixtures.ts';
import type { AISummary } from '../models';

// MARK: - Setup: one signed-in store over injectable boundaries with a very short sync delay.
const session = (): StoredSession => ({
  token: 'synthetic-session-token',
  expiresAt: '2026-10-12T12:00:00Z',
  user: { ...testUser },
});
const marker = (serverRevision: number, localRevision: number) =>
  JSON.stringify({ serverRevision, localRevision });
function accountStore({
  repository = new MemoryRepository(),
  api = transport(),
  auth = authTransport(),
  entries = {} as Record<string, string>,
  syncDelay = 5,
}: {
  repository?: MemoryRepository;
  api?: APITransport;
  auth?: AuthTransport;
  entries?: Record<string, string>;
  syncDelay?: number;
} = {}) {
  const storage = fakeStorage({ [SESSION_KEY]: JSON.stringify(session()), ...entries }),
    redirect = vi.fn<(path: string) => void>();
  const store = new RevaStore(repository, () => api, {
    mode: 'account',
    token: session().token,
    user: testUser,
    expiresAt: session().expiresAt,
    storage,
    redirect,
    authFactory: () => auth,
    syncDelay,
  });
  return { store, repository, api, auth, storage, redirect };
}
const emptyLocal = () => {
  const repository = new MemoryRepository();
  repository.saved = null;
  return repository;
};
const settle = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));
const originalCount = (snapshot = seed()) =>
  new Set([
    ...snapshot.records.flatMap((record) => (record.sourceFilename ? [record.sourceFilename] : [])),
    ...snapshot.recordings.flatMap((recording) => (recording.audioFilename ? [recording.audioFilename] : [])),
  ]).size;

// MARK: - Naming and the empty personal snapshot never borrow the fictional demo.
describe('account identity helpers', () => {
  it('unwinds busy provider work before logout even when its transport ignores abort', async () => {
    const result = deferred<AISummary>();
    const summarize = vi.fn<APITransport['summarize']>(() => result.promise);
    const logout = vi.fn(async () => {});
    const { store } = accountStore({ api: transport({ summarize }), auth: authTransport({ logout }) });
    await store.initialize();
    store.setConnectedAI(true);
    const record = store.getState().snapshot!.records[0];
    const pending = store.summarizeRecord(record.id);
    const rejected = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    await vi.waitFor(() => expect(summarize).toHaveBeenCalledOnce());
    expect(store.getState()).toMatchObject({ busy: true, providerWork: true });
    await store.cancelProviderWork();
    expect(store.getState()).toMatchObject({ busy: false, providerWork: false });
    expect(summarize.mock.calls[0][1]!.aborted).toBe(true);
    await store.logout();
    expect(logout).toHaveBeenCalledOnce();
    result.resolve({ summary: 'Late response must never be applied', model: 'fake-model' });
    await rejected;
    expect(store.getState().snapshot!.records.find((item) => item.id === record.id)!.summary).toBe(
      record.summary,
    );
  });
  it('derives a stable per-user database name that differs from the demo database', async () => {
    const name = await accountDatabaseName(testUser.id);
    expect(name).toMatch(/^reva-account-[0-9a-f]{16}-v1$/);
    expect(await accountDatabaseName(testUser.id)).toBe(name);
    expect(await accountDatabaseName('u_other')).not.toBe(name);
    expect(name).not.toBe(DEMO_DATABASE);
    await expect(accountDatabaseName('')).rejects.toThrow();
  });
  it('builds a validated empty snapshot around the signed-in user', () => {
    const snapshot = emptyPersonalSnapshot(testUser);
    expect(snapshot.profile).toMatchObject({
      id: testUser.id,
      name: 'Synthetic Person',
      initials: 'SP',
      isDemo: false,
      allergies: [],
      medications: [],
      conditions: [],
    });
    expect(snapshot.records).toEqual([]);
    expect(snapshot.visits).toEqual([]);
    expect(snapshot.bookings).toEqual([]);
    expect(snapshot.recordings).toEqual([]);
    expect(initialsFor('Ada')).toBe('A');
    expect(initialsFor('  ')).toBe('');
  });
});

// MARK: - First login: the server decides whether this browser starts empty, downloads or must review.
describe('account startup reconciliation', () => {
  it('pushes an empty personal snapshot when both sides are empty', async () => {
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const { store, repository, storage } = accountStore({
      repository: emptyLocal(),
      api: transport({ push }),
    });
    await store.initialize();
    expect(push).toHaveBeenCalledTimes(1);
    const [pushed, base] = push.mock.calls[0];
    expect(base).toBe(0);
    expect(pushed.profile).toMatchObject({ id: testUser.id, name: 'Synthetic Person', isDemo: false });
    expect(pushed.records).toEqual([]);
    expect(store.getState()).toMatchObject({
      mode: 'account',
      loading: false,
      error: null,
      serverRevision: 1,
    });
    expect(store.getState().snapshot!.profile.isDemo).toBe(false);
    expect(repository.saved).toMatchObject({ revision: 1 });
    expect(JSON.parse(storage.data.get(syncMarkerKey(testUser.id))!)).toEqual({
      serverRevision: 1,
      localRevision: 1,
    });
    expect(store.accountUser()).toEqual(testUser);
  });
  it('downloads the server copy with its originals when only the server has data', async () => {
    const remote = seed();
    const attachment = vi.fn<APITransport['attachment']>(async () => new Blob(['synthetic remote original']));
    const push = vi.fn<APITransport['push']>();
    const { store, repository } = accountStore({
      repository: emptyLocal(),
      api: transport({ pull: async () => ({ revision: 4, snapshot: remote }), attachment, push }),
    });
    await store.initialize();
    expect(store.getState().snapshot).toEqual(remote);
    expect(store.getState()).toMatchObject({ serverRevision: 4, loading: false, error: null });
    expect(store.getState().syncStatus).toBe('saved');
    expect(attachment).toHaveBeenCalledTimes(originalCount());
    expect(repository.attachments.size).toBe(originalCount());
    await settle();
    expect(push).not.toHaveBeenCalled();
  });
  it('preserves unknown-baseline local items and automatically sends their merged copy', async () => {
    let remote: ServerState = { revision: 3, snapshot: { ...seed(), records: [] } };
    const push = vi.fn<APITransport['push']>(async (snapshot, revision) => {
      remote = { revision: revision + 1, snapshot: structuredClone(snapshot) };
      return remote.revision;
    });
    const { store } = accountStore({ api: transport({ pull: async () => structuredClone(remote), push }) });
    await store.initialize();
    expect(store.getState().snapshot!.records.length).toBe(seed().records.length);
    expect(push).toHaveBeenCalledTimes(1);
    expect(push.mock.calls[0][1]).toBe(3);
    expect(remote.snapshot.records.length).toBe(seed().records.length);
    await store.mutate((draft) => {
      draft.profile.careNotes = 'Another automatic edit';
    });
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(2));
    expect(remote.snapshot.profile.careNotes).toBe('Another automatic edit');
    expect(store.getState().syncStatus).toBe('saved');
  });
  it('pushes a local copy the server has never seen', async () => {
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const { store } = accountStore({ api: transport({ push }) });
    await store.initialize();
    expect(store.getState().notice).toBeNull();
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(1));
    expect(push.mock.calls[0][0].records.length).toBe(seed().records.length);
    expect(push.mock.calls[0][1]).toBe(0);
    expect(store.getState().serverRevision).toBe(1);
  });
  it('trusts the remembered in-sync revision and only pushes when the local copy moved', async () => {
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const api = transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push });
    const quiet = accountStore({ api, entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) } });
    await quiet.store.initialize();
    expect(quiet.store.getState()).toMatchObject({ notice: null, serverRevision: 3 });
    await settle();
    expect(push).not.toHaveBeenCalled();
    const repository = new MemoryRepository();
    repository.saved!.snapshot.profile.careNotes = 'Changed while offline';
    const moved = accountStore({ repository, api, entries: { [syncMarkerKey(testUser.id)]: marker(3, 0) } });
    await moved.store.initialize();
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(1));
    expect(push.mock.calls[0][1]).toBe(3);
  });
});

// MARK: - Auto-sync: debounced, quiet, de-duplicating originals, and never after the session ended.
describe('account auto-sync', () => {
  it('sends one push for a burst of edits and remembers the new in-sync revisions', async () => {
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const { store, storage, repository } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
      syncDelay: 20,
    });
    await store.initialize();
    await store.mutate((draft) => {
      draft.profile.careNotes = 'one';
    });
    await store.mutate((draft) => {
      draft.profile.careNotes = 'two';
    });
    await store.mutate((draft) => {
      draft.profile.careNotes = 'three';
    });
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(1));
    await settle(80);
    expect(push).toHaveBeenCalledTimes(1);
    expect(push.mock.calls[0][0].profile.careNotes).toBe('three');
    expect(store.getState()).toMatchObject({ serverRevision: 4, busy: false, error: null, notice: null });
    expect(JSON.parse(storage.data.get(syncMarkerKey(testUser.id))!)).toEqual({
      serverRevision: 4,
      localRevision: repository.saved!.revision,
    });
  });
  it('uploads each original once per session even across several pushes', async () => {
    const uploadAttachment = vi.fn<APITransport['uploadAttachment']>(async () => {});
    let remote = { revision: 3, snapshot: seed() };
    const push = vi.fn<APITransport['push']>(async (snapshot, revision) => {
      remote = { revision: revision + 1, snapshot: structuredClone(snapshot) };
      return remote.revision;
    });
    const { store } = accountStore({
      api: transport({ pull: async () => structuredClone(remote), push, uploadAttachment }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await store.mutate((draft) => {
      draft.profile.careNotes = 'first';
    });
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(1));
    expect(uploadAttachment).toHaveBeenCalledTimes(originalCount(store.getState().snapshot!));
    await store.mutate((draft) => {
      draft.profile.careNotes = 'second';
    });
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(2));
    expect(uploadAttachment).toHaveBeenCalledTimes(originalCount(store.getState().snapshot!));
  });
  it('still re-uploads originals on every manual push in demo mode', async () => {
    const uploadAttachment = vi.fn<APITransport['uploadAttachment']>(async () => {});
    const store = new RevaStore(new MemoryRepository(), () => transport({ uploadAttachment }));
    await store.initialize();
    await store.checkServer();
    await store.pushToServer();
    await store.pushToServer();
    expect(uploadAttachment).toHaveBeenCalledTimes(originalCount() * 2);
  });
  it('reconciles a 409 and retries the save automatically with both devices edits', async () => {
    let remote = { revision: 3, snapshot: seed() };
    const push = vi
      .fn<APITransport['push']>()
      .mockImplementationOnce(async () => {
        remote.snapshot.profile.conditions.push('Synthetic other-device condition');
        remote.revision = 5;
        throw new APIError(409, 5);
      })
      .mockImplementation(async (snapshot, revision) => {
        remote = { revision: revision + 1, snapshot: structuredClone(snapshot) };
        return remote.revision;
      });
    const { store } = accountStore({
      api: transport({ pull: async () => structuredClone(remote), push }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await store.mutate((draft) => {
      draft.profile.careNotes = 'My offline note';
    });
    await vi.waitFor(() => expect(push).toHaveBeenCalledTimes(2));
    expect(push.mock.calls.map((call) => call[1])).toEqual([3, 5]);
    expect(remote.snapshot.profile.careNotes).toBe('My offline note');
    expect(remote.snapshot.profile.conditions).toContain('Synthetic other-device condition');
    expect(store.getState()).toMatchObject({ syncStatus: 'saved', error: null });
  });
});

// MARK: - An HTTP 401 ends the session: storage cleared, one notice, one redirect, no further sync.
describe('session end on 401', () => {
  it('does not clear a newer session established by another tab when the old request is rejected', async () => {
    const { store, storage, redirect } = accountStore({
      api: transport({
        health: async () => {
          throw new APIError(401);
        },
      }),
    });
    const replacement = {
      ...session(),
      token: 'newer-session-for-another-account',
      user: { ...testUser, id: 'u_other' },
    };
    storage.setItem(SESSION_KEY, JSON.stringify(replacement));
    await store.initialize();
    expect(JSON.parse(storage.data.get(SESSION_KEY)!)).toEqual(replacement);
    expect(redirect).toHaveBeenCalledWith('/app');
  });
  it('clears the stored session and redirects when startup discovery is rejected', async () => {
    const { store, storage, redirect } = accountStore({
      api: transport({
        health: async () => {
          throw new APIError(401);
        },
      }),
    });
    await store.initialize();
    expect(storage.data.has(SESSION_KEY)).toBe(false);
    expect(redirect).toHaveBeenCalledTimes(1);
    expect(redirect).toHaveBeenCalledWith(SESSION_ENDED_PATH);
    expect(store.getState()).toMatchObject({ notice: SESSION_ENDED_NOTICE, error: null, loading: false });
    expect(store.getState().snapshot).not.toBeNull();
  });
  it('ends the session once when an auto-sync push is rejected and stops syncing', async () => {
    const push = vi.fn<APITransport['push']>().mockRejectedValue(new APIError(401));
    const { store, storage, redirect } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await store.mutate((draft) => {
      draft.profile.careNotes = 'unsent';
    });
    await vi.waitFor(() => expect(redirect).toHaveBeenCalledWith(SESSION_ENDED_PATH));
    expect(storage.data.has(SESSION_KEY)).toBe(false);
    expect(store.getState().notice).toBe(SESSION_ENDED_NOTICE);
    await store.mutate((draft) => {
      draft.profile.careNotes = 'after the end';
    });
    await settle();
    expect(push).toHaveBeenCalledTimes(1);
    expect(redirect).toHaveBeenCalledTimes(1);
    expect(store.getState().snapshot!.profile.careNotes).toBe('after the end');
  });
  it('keeps the demo store on the same 401 path it always had', async () => {
    const store = new RevaStore(new MemoryRepository(), () =>
      transport({
        health: async () => {
          throw new APIError(401);
        },
      }),
    );
    await store.initialize();
    await expect(store.checkServer()).rejects.toMatchObject({ status: 401 });
    expect(store.getState().error).toMatch(/did not accept/);
  });
});

// MARK: - Account actions: a wrong password is an error, not an ended session; leaving is deliberate.
describe('account actions', () => {
  it('logs out after flushing unsent edits and clears the session', async () => {
    const push = vi.fn<APITransport['push']>(async (_snapshot, revision) => revision + 1);
    const logout = vi.fn<AuthTransport['logout']>(async () => {});
    const { store, storage, redirect } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push }),
      auth: authTransport({ logout }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
      syncDelay: 10_000,
    });
    await store.initialize();
    await store.mutate((draft) => {
      draft.profile.careNotes = 'flush me';
    });
    await store.logout();
    expect(push).toHaveBeenCalledTimes(1);
    expect(push.mock.invocationCallOrder[0]).toBeLessThan(logout.mock.invocationCallOrder[0]);
    expect(logout).toHaveBeenCalledTimes(1);
    expect(storage.data.has(SESSION_KEY)).toBe(false);
    expect(redirect).toHaveBeenCalledWith('/');
  });
  it('logs out everywhere through the dedicated route and tolerates an already-ended session', async () => {
    const logoutAll = vi.fn<AuthTransport['logoutAll']>().mockRejectedValue(new APIError(401));
    const { store, storage, redirect } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push: vi.fn() }),
      auth: authTransport({ logoutAll }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await store.logoutAll();
    expect(logoutAll).toHaveBeenCalledTimes(1);
    expect(storage.data.has(SESSION_KEY)).toBe(false);
    expect(redirect).toHaveBeenCalledWith('/');
    expect(store.getState().notice).toBeNull();
  });
  it('keeps the session when logging out fails for another reason', async () => {
    const { store, storage, redirect } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push: vi.fn() }),
      auth: authTransport({
        logout: async () => {
          throw new Error('Network unreachable');
        },
      }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await expect(store.logout()).rejects.toThrow('Network unreachable');
    expect(storage.data.has(SESSION_KEY)).toBe(true);
    expect(redirect).not.toHaveBeenCalled();
    expect(store.getState().error).toBe('Network unreachable');
  });
  it('reports a wrong current password without ending the session', async () => {
    const changePassword = vi
      .fn<AuthTransport['changePassword']>()
      .mockRejectedValueOnce(new APIError(401))
      .mockResolvedValueOnce(undefined);
    const { store, storage, redirect } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push: vi.fn() }),
      auth: authTransport({ changePassword }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await expect(store.changePassword('wrong password', 'new password 22')).rejects.toThrow(
      'current password is incorrect',
    );
    expect(storage.data.has(SESSION_KEY)).toBe(true);
    expect(redirect).not.toHaveBeenCalled();
    await store.changePassword('old password 1', 'new password 22');
    expect(changePassword).toHaveBeenLastCalledWith('old password 1', 'new password 22');
    expect(store.getState().notice).toMatch(/Password changed/);
  });
  it('deletes the account only with the right password, then removes the local copy and session', async () => {
    const deleteAccount = vi
      .fn<AuthTransport['deleteAccount']>()
      .mockRejectedValueOnce(new APIError(401))
      .mockResolvedValueOnce(undefined);
    const { store, repository, storage, redirect } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push: vi.fn() }),
      auth: authTransport({ deleteAccount }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await expect(store.deleteAccount('wrong password')).rejects.toThrow('account was not deleted');
    expect(repository.destroyed).toBe(false);
    expect(storage.data.has(SESSION_KEY)).toBe(true);
    await store.deleteAccount('old password 1');
    expect(deleteAccount).toHaveBeenLastCalledWith('old password 1');
    expect(repository.destroyed).toBe(true);
    expect(storage.data.has(SESSION_KEY)).toBe(false);
    expect(storage.data.has(syncMarkerKey(testUser.id))).toBe(false);
    expect(redirect).toHaveBeenCalledWith('/');
  });
  it('refuses demo-only controls inside an account workspace', async () => {
    const { store } = accountStore({
      api: transport({ pull: async () => ({ revision: 3, snapshot: seed() }), push: vi.fn() }),
      entries: { [syncMarkerKey(testUser.id)]: marker(3, 1) },
    });
    await store.initialize();
    await expect(store.resetDemo()).rejects.toThrow('not available inside');
    store.setToken('another-token');
    expect(store.getState().token).toBe('synthetic-session-token');
    expect(store.getState().error).toMatch(/log out to switch accounts/);
  });
  it('rejects account actions in demo mode', async () => {
    const store = new RevaStore(new MemoryRepository(), () => transport());
    await store.initialize();
    expect(store.accountUser()).toBeNull();
    await expect(store.logout()).rejects.toThrow('signed-in workspace');
    expect(store.getState().mode).toBe('demo');
  });
});
