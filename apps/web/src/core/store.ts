import {
  briefContextSignature,
  briefVisit,
  briefSources,
  clinicalBrief,
  type ClinicalBrief,
  type VisitBriefInput,
} from './visitBrief';
import { demoClinicalBrief } from './demoVisitBrief';
// Purpose: Coordinate durable browser edits, automatic account synchronization and connected actions.
// Inputs: UI intents, an injectable repository/API factory, reviewed provider requests and, in account
//         mode, the signed-in session (token, user) with injectable storage/redirect boundaries.
// Outputs: Observable state with durable snapshots, notices, capability flags and explicit failures.
// Side effects: Serial IndexedDB writes; explicit provider requests in demo mode; automatic account
//               pull/merge/push with offline retries, and session-bound redirects on HTTP 401.
import type {
  AppSnapshot,
  MedicalRecord,
  ProviderStatus,
  ServerState,
  Visit,
  VisitRecording,
} from './models.ts';
import {
  currentSummary,
  generateReport,
  localExcerpt,
  nowISO,
  reportSignature,
  uid,
  validateSnapshot,
} from './domain.ts';
import {
  clearRecordingSummary,
  createMemoryRecord,
  hasRecordingSummary,
  invalidateChangedRecordingSummaries,
  reconcileMemory,
  recordingTranscript,
  upsertRecord,
} from './mutations.ts';
import { APIError, RevaAPI } from './api.ts';
import { AuthAPI, type AuthTransport } from './auth.ts';
import { emptyPersonalSnapshot } from './account.ts';
import {
  browserStorage,
  clearSession,
  readSession,
  SESSION_KEY,
  type SessionUser,
  type StorageLike,
} from './session.ts';
import { clearSyncMarker, readSyncMarker, writeSyncMarker } from './syncMarker.ts';
import {
  LocalConflictError,
  repository,
  type SnapshotRepository,
  type StoredSnapshot,
} from './repository.ts';
import { mergeSnapshots, sameSyncValue } from './syncMerge.ts';
import { calendarDay } from './dates';
import { recordingInstant } from './recordingDates';
import { recordDateContext } from './recordDates';
import type { GeminiRetryState } from './geminiRetry';

// MARK: - Observable values deliberately exclude credentials from durable snapshot state.
export interface RevaState {
  snapshot: AppSnapshot | null;
  loading: boolean;
  error: string | null;
  notice: string | null;
  busy: boolean;
  providerWork: boolean;
  providers: ProviderStatus | null;
  connectedAI: boolean;
  token: string;
  serverRevision: number | null;
  mode: 'demo' | 'account';
  syncStatus: 'local' | 'syncing' | 'saved' | 'offline';
  syncError: string | null;
  lastSyncedAt: string | null;
  account: { user: SessionUser; expiresAt: string | null } | null;
}
export type APITransport = Pick<
  RevaAPI,
  | 'health'
  | 'providers'
  | 'pull'
  | 'push'
  | 'uploadAttachment'
  | 'attachment'
  | 'summarize'
  | 'prepare'
  | 'transcribe'
>;
// Demo mode keeps the public local token and manual sync; account mode binds one signed-in session.
export interface DemoOptions {
  mode?: 'demo';
}
export interface AccountOptions {
  mode: 'account';
  token: string;
  user: SessionUser;
  expiresAt?: string | null;
  storage?: StorageLike | null;
  redirect?: (path: string) => void;
  authFactory?: (token: string) => AuthTransport;
  syncDelay?: number;
  syncInterval?: number;
}
export type StoreOptions = DemoOptions | AccountOptions;
export const SESSION_ENDED_PATH = '/login?reason=session';
export const SESSION_ENDED_NOTICE = 'Your session ended. Log in again to continue.';
export const SERVER_DIFFERS_NOTICE =
  'Simultaneous edits were kept as labeled recovery copies. You can review them in your workspace.';
function message(error: unknown): string {
  return error instanceof Error
    ? error.message
    : 'This action could not finish. Your previous saved data was kept.';
}
function originals(snapshot: AppSnapshot): Map<string, string | undefined> {
  const names = new Map<string, string | undefined>();
  snapshot.records.forEach((record) => {
    if (record.sourceFilename) names.set(record.sourceFilename, record.mimeType ?? undefined);
  });
  snapshot.recordings.forEach((recording) => {
    if (recording.audioFilename) names.set(recording.audioFilename, audioType(recording.audioFilename));
  });
  return names;
}
function audioType(filename: string): string | undefined {
  return (
    {
      m4a: 'audio/mp4',
      mp4: 'audio/mp4',
      mp3: 'audio/mpeg',
      wav: 'audio/wav',
      webm: 'audio/webm',
      ogg: 'audio/ogg',
    } as Record<string, string>
  )[filename.split('.').pop()?.toLowerCase() ?? ''];
}

// A transport that finishes late after abort cannot keep the workspace busy or publish its result.
function providerResult<T>(signal: AbortSignal, request: () => Promise<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const abort = () =>
      reject(new DOMException('Analysis canceled. Your saved data was kept.', 'AbortError'));
    if (signal.aborted) {
      abort();
      return;
    }
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve()
      .then(() => {
        signal.throwIfAborted();
        return request();
      })
      .then(resolve, reject)
      .finally(() => {
        signal.removeEventListener('abort', abort);
      });
  });
}

// MARK: - A testable store serializes commits and publishes only after storage succeeds.
export class RevaStore {
  private state: RevaState = {
    snapshot: null,
    loading: true,
    error: null,
    notice: null,
    busy: false,
    providerWork: false,
    providers: null,
    connectedAI: false,
    token: 'reva-local-demo-token',
    serverRevision: null,
    mode: 'demo',
    syncStatus: 'local',
    syncError: null,
    lastSyncedAt: null,
    account: null,
  };
  private listeners = new Set<() => void>();
  private localRevision = 0;
  private writes: Promise<unknown> = Promise.resolve();
  private initialization?: Promise<void>;
  private identity = 0;
  private recordingRequests = new Set<string>();
  private providerRequests = new Map<AbortController, Promise<void>>();
  private mustPull = false;
  private readonly account: AccountOptions | null;
  private readonly storage: StorageLike | null;
  private readonly redirect: (path: string) => void;
  private readonly authFactory: (token: string) => AuthTransport;
  private readonly syncDelay: number;
  private syncTimer: ReturnType<typeof setTimeout> | null = null;
  private syncPending = false;
  private sessionEnded = false;
  private uploaded = new Set<string>();
  private syncBase: ServerState | null = null;
  private syncTask: Promise<void> | null = null;
  private syncEnabled = true;
  private syncFailures = 0;
  private providersCheckedAt: number | null = null;
  private lifecycleCleanup: (() => void) | null = null;
  constructor(
    private readonly persistence: SnapshotRepository = repository,
    private readonly apiFactory: (token: string) => APITransport = (token) => new RevaAPI(token),
    options: StoreOptions = {},
  ) {
    this.account = options.mode === 'account' ? options : null;
    this.storage = this.account
      ? this.account.storage === undefined
        ? browserStorage()
        : this.account.storage
      : null;
    this.redirect = this.account?.redirect ?? ((path) => location.replace(path));
    this.authFactory = this.account?.authFactory ?? ((token) => new AuthAPI(token));
    this.syncDelay = this.account?.syncDelay ?? 1500;
    if (this.account)
      this.state = {
        ...this.state,
        token: this.account.token,
        mode: 'account',
        syncStatus: 'syncing',
        account: { user: this.account.user, expiresAt: this.account.expiresAt ?? null },
      };
  }
  getState = (): RevaState => this.state;
  isWorkspaceActive = (): boolean => !this.sessionEnded;
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  private publish(patch: Partial<RevaState>): void {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((listener) => listener());
  }
  private adopt(saved: StoredSnapshot): void {
    this.localRevision = saved.revision;
    this.publish({ snapshot: saved.snapshot });
  }
  private requiredSnapshot(): AppSnapshot {
    if (!this.state.snapshot)
      throw new Error('Load or explicitly restore this workspace before making changes.');
    return this.state.snapshot;
  }
  private queue<T>(work: () => Promise<T>): Promise<T> {
    const pending = this.writes.then(work);
    this.writes = pending.catch(() => undefined);
    return pending;
  }
  private async edit(
    change: (draft: AppSnapshot) => void | Promise<void>,
    attachments?: ReadonlyMap<string, Blob>,
  ): Promise<void> {
    try {
      await this.queue(async () => {
        const previous = this.requiredSnapshot();
        const draft = structuredClone(previous);
        await change(draft);
        invalidateChangedRecordingSummaries(previous, draft);
        let candidate = validateSnapshot(draft);
        for (let attempt = 0; ; attempt++) {
          try {
            this.adopt(await this.persistence.commit(candidate, this.localRevision, attachments));
            break;
          } catch (error) {
            if (!this.account || !(error instanceof LocalConflictError) || attempt >= 3) throw error;
            const latest = await this.persistence.load();
            if (!latest) throw error;
            candidate = mergeSnapshots(previous, candidate, latest.snapshot).snapshot;
            this.adopt(latest);
          }
        }
      });
      this.scheduleSync();
    } catch (error) {
      this.reportError(error);
      throw error;
    }
  }
  // User actions use the busy flag. Background synchronization has its own independent status.
  private async action(work: () => Promise<void>, quiet = false): Promise<void> {
    if (this.state.busy) throw new Error('Another connected action is still running. Wait for it to finish.');
    this.publish(quiet ? { busy: true } : { busy: true, error: null, notice: null });
    try {
      await work();
    } catch (error) {
      this.reportError(error);
      throw error;
    } finally {
      this.publish({ busy: false });
      if (this.syncPending) this.scheduleSync();
    }
  }
  private assertIdentity(identity: number): void {
    if (identity !== this.identity || this.sessionEnded)
      throw new Error('The workspace token changed during this request. Its result was not applied.');
  }
  // All provider timers and fetches belong to the active workspace, including background work.
  private async providerAction<T>(
    work: (signal: AbortSignal) => Promise<T>,
    external?: AbortSignal,
  ): Promise<T> {
    const controller = new AbortController();
    const abort = () => controller.abort();
    external?.addEventListener('abort', abort, { once: true });
    if (external?.aborted || this.sessionEnded) controller.abort();
    let finish!: () => void;
    const finished = new Promise<void>((resolve) => {
      finish = resolve;
    });
    this.providerRequests.set(controller, finished);
    this.publish({ providerWork: true });
    try {
      controller.signal.throwIfAborted();
      return await work(controller.signal);
    } finally {
      external?.removeEventListener('abort', abort);
      this.providerRequests.delete(controller);
      this.publish({ providerWork: this.providerRequests.size > 0 });
      finish();
    }
  }
  cancelProviderWork = async (): Promise<void> => {
    const requests = [...this.providerRequests];
    requests.forEach(([controller]) => controller.abort());
    await Promise.all(requests.map(([, finished]) => finished));
  };

  // MARK: - Startup distinguishes absent state from corruption and never replays interrupted work.
  initialize = (): Promise<void> => {
    if (!this.initialization)
      this.initialization = this.account ? this.initializeAccount() : this.initializeDemo();
    return this.initialization;
  };
  private async initializeDemo(): Promise<void> {
    try {
      const existing = await this.persistence.load();
      this.adopt(existing ?? (await this.persistence.commit(await this.persistence.seed(), 0)));
      await this.refreshDemoLabels();
    } catch (error) {
      this.reportError(error);
    } finally {
      this.publish({ loading: false });
    }
  }
  // Update only untouched bundled samples; edited records and original source wording stay intact.
  private async refreshDemoLabels(): Promise<void> {
    const labels: Record<string, [string[], string]> = {
      'demo-record-symptom-diary': [
        ['Nausea and palpitation diary - date needs review', 'Scanned symptom note - date needs review'],
        'Weekly symptom diary',
      ],
      'demo-record-labs': [['Laboratory results for symptom review'], 'Bloodwork · September 7'],
      'demo-record-ecg': [['Resting ECG note for palpitation review'], 'Resting ECG · September 7'],
    };
    for (const record of this.state.snapshot?.records ?? []) {
      const label = labels[record.id];
      if (!record.isDemo || record.version !== 1 || !label?.[0].includes(record.title)) continue;
      await this.saveRecord(
        {
          ...record,
          title: label[1],
          status: 'ready',
          tags: record.tags.filter((tag) => tag !== 'needs review'),
        },
        record.version,
      );
    }
  }
  notify = (notice: string): void => this.publish({ notice, error: null });
  // In account mode an HTTP 401 means the session is gone: clear it, say so, and leave the workspace.
  reportError = (error: unknown): void => {
    if (this.account && error instanceof APIError && error.status === 401) {
      this.endSession(SESSION_ENDED_NOTICE, SESSION_ENDED_PATH);
      return;
    }
    this.publish({ error: message(error), notice: null });
  };
  clearFeedback = (): void => this.publish({ notice: null, error: null });
  mutate = (change: (draft: AppSnapshot) => void): Promise<void> => this.edit(change);
  resetDemo = (): Promise<void> =>
    this.action(async () => {
      if (this.account) throw new Error('Original-record restoration is not available inside a signed-in workspace.');
      const seed = await this.persistence.seed();
      await this.queue(async () => {
        this.adopt(await this.persistence.reset(seed));
        this.mustPull = false;
        this.publish({ loading: false, serverRevision: null });
      });
      this.notify('Original records restored in this browser.');
    });
  setToken = (token: string): void => {
    if (token === this.state.token) return;
    if (this.account) {
      this.reportError(new Error('Your account session is the workspace token; log out to switch accounts.'));
      return;
    }
    if (this.state.busy && !this.state.providerWork) {
      this.reportError(
        new Error('Wait for the current action to finish before changing the workspace token.'),
      );
      return;
    }
    void this.cancelProviderWork();
    this.identity += 1;
    this.mustPull = false;
    this.publish({ token, providers: null, serverRevision: null, connectedAI: false, notice: null });
  };
  setConnectedAI = (connectedAI: boolean): void => {
    if (connectedAI && !this.state.providers?.gemini.configured) {
      this.reportError(new Error('Check a server with configured AI before enabling connected preparation.'));
      return;
    }
    this.publish({ connectedAI });
  };

  // MARK: - Account startup works offline; every reconciliation pulls, merges, then pushes local edits.
  private async initializeAccount(): Promise<void> {
    try {
      const existing = await this.persistence.load();
      this.adopt(existing ?? (await this.persistence.commit(emptyPersonalSnapshot(this.account!.user), 0)));
      this.syncBase =
        (await this.persistence.loadSyncBase?.()) ??
        (existing
          ? null
          : {
              revision: 0,
              snapshot: structuredClone(this.requiredSnapshot()),
            });
    } catch (error) {
      this.reportError(error);
      this.publish({ loading: false });
      return;
    }
    this.publish({ loading: false });
    await this.autoSync();
  }
  private async rememberSync(
    serverRevision: number,
    localRevision: number,
    snapshot: AppSnapshot,
  ): Promise<void> {
    if (!this.account) return;
    const base = { revision: serverRevision, snapshot: structuredClone(snapshot) };
    await this.persistence.saveSyncBase?.(base);
    this.syncBase = base;
    writeSyncMarker(this.account.user.id, { serverRevision, localRevision }, this.storage);
  }
  private endSession(notice: string | null, path: string): void {
    if (this.sessionEnded) return;
    this.sessionEnded = true;
    void this.cancelProviderWork();
    this.cancelSync();
    this.lifecycleCleanup?.();
    const currentSession = readSession(this.storage);
    const replaced = currentSession && currentSession.token !== this.state.token;
    if (!replaced) clearSession(this.storage);
    this.publish(notice ? { notice, error: null } : {});
    this.redirect(replaced ? '/app' : path);
  }

  // MARK: - Polling and browser wake events keep read-only devices current, with bounded offline retries.
  startAutomaticSync = (): (() => void) => {
    if (!this.account || this.sessionEnded) return () => {};
    this.lifecycleCleanup?.();
    this.syncEnabled = true;
    const wake = (refreshProviders = false) => {
      if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
      if (refreshProviders) this.providersCheckedAt = null;
      void this.initialize().then(() => {
        if (refreshProviders && this.syncTask) this.scheduleSync(0);
        else return this.autoSync();
      });
    };
    const resume = () => wake(true);
    const visibility = () => wake(true);
    const sessionChanged = (event: StorageEvent) => {
      if (event.key !== SESSION_KEY && event.key !== null) return;
      if (readSession(this.storage)?.token !== this.state.token)
        this.endSession(SESSION_ENDED_NOTICE, SESSION_ENDED_PATH);
    };
    globalThis.addEventListener?.('online', resume);
    globalThis.addEventListener?.('focus', resume);
    globalThis.addEventListener?.('storage', sessionChanged);
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', visibility);
    const interval = setInterval(wake, this.account.syncInterval ?? 30_000);
    const cleanup = () => {
      clearInterval(interval);
      globalThis.removeEventListener?.('online', resume);
      globalThis.removeEventListener?.('focus', resume);
      globalThis.removeEventListener?.('storage', sessionChanged);
      if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', visibility);
      this.syncEnabled = false;
      this.cancelSync();
      if (this.lifecycleCleanup === cleanup) this.lifecycleCleanup = null;
    };
    this.lifecycleCleanup = cleanup;
    void this.initialize();
    return cleanup;
  };
  private scheduleSync(delay = this.syncDelay): void {
    if (!this.account || this.sessionEnded || !this.syncEnabled) return;
    this.syncPending = true;
    if (this.syncTimer) clearTimeout(this.syncTimer);
    this.syncTimer = setTimeout(() => {
      this.syncTimer = null;
      void this.autoSync();
    }, delay);
  }
  private cancelSync(): void {
    if (this.syncTimer) clearTimeout(this.syncTimer);
    this.syncTimer = null;
    this.syncPending = false;
  }
  private async autoSync(): Promise<void> {
    if (!this.account || this.sessionEnded || !this.syncEnabled || !this.state.snapshot) return;
    if (this.syncTask) {
      await this.syncTask.catch(() => undefined);
      return;
    }
    if (this.state.busy) {
      this.scheduleSync();
      return;
    }
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      this.publish({
        syncStatus: 'offline',
        syncError: 'Changes are saved on this device and will sync when you reconnect.',
      });
      this.scheduleSync(30_000);
      return;
    }
    this.cancelSync();
    this.publish({ syncStatus: 'syncing', syncError: null });
    const task = this.synchronizeAccount();
    this.syncTask = task;
    try {
      await task;
      this.syncFailures = 0;
      if (!this.sessionEnded)
        this.publish({
          syncStatus: this.syncPending ? 'syncing' : 'saved',
          syncError: null,
          lastSyncedAt: nowISO(),
        });
    } catch (error) {
      if (error instanceof APIError && error.status === 401) this.reportError(error);
      else if (!this.sessionEnded) {
        this.publish({
          syncStatus: 'offline',
          syncError: `Saved on this device. Sync will retry automatically. ${message(error)}`,
        });
        this.syncFailures += 1;
        this.scheduleSync(Math.min(60_000, 3000 * 2 ** Math.min(this.syncFailures - 1, 5)));
      }
    } finally {
      this.syncTask = null;
      if (this.syncPending && !this.syncTimer) this.scheduleSync();
    }
  }
  private async synchronizeAccount(): Promise<void> {
    const identity = this.identity,
      api = this.apiFactory(this.state.token);
    if (!this.state.providers) {
      const found = await this.discover(api);
      this.assertIdentity(identity);
      this.providersCheckedAt = Date.now();
      this.publish({
        providers: found.providers,
        connectedAI: this.state.connectedAI && found.providers.gemini.configured,
      });
      await this.reconcileAccountRemote(api, found.remote, found.revision, identity);
    } else {
      // Server keys can be configured after login. Refresh on wake or at most once per minute;
      // ordinary local edits reuse the cached capabilities and never opt the user into connected AI.
      if (this.providersCheckedAt === null || Date.now() - this.providersCheckedAt >= 60_000) {
        const providers = await api.providers();
        this.assertIdentity(identity);
        this.providersCheckedAt = Date.now();
        this.publish({ providers, connectedAI: this.state.connectedAI && providers.gemini.configured });
      }
      const found = await this.readRemote(api);
      this.assertIdentity(identity);
      await this.reconcileAccountRemote(api, found.remote, found.revision, identity);
    }
    // Another device can save after our read. Retry from its new revision without replacing either edit.
    for (let attempt = 0; attempt < 4; attempt++) {
      await this.writes;
      this.assertIdentity(identity);
      if (this.syncBase && sameSyncValue(this.syncBase.snapshot, this.requiredSnapshot())) return;
      try {
        await this.push(true);
        return;
      } catch (error) {
        if (!(error instanceof APIError) || error.status !== 409 || attempt === 3) throw error;
        const found = await this.readRemote(api);
        this.assertIdentity(identity);
        await this.reconcileAccountRemote(api, found.remote, found.revision, identity);
      }
    }
  }
  private async readRemote(api: APITransport): Promise<{ remote: ServerState | null; revision: number }> {
    try {
      const remote = await api.pull();
      return { remote, revision: remote.revision };
    } catch (error) {
      if (!(error instanceof APIError) || error.status !== 404 || error.revision === null) throw error;
      return { remote: null, revision: error.revision };
    }
  }
  private async reconcileAccountRemote(
    api: APITransport,
    remote: ServerState | null,
    revision: number,
    identity: number,
  ): Promise<void> {
    await this.writes;
    this.assertIdentity(identity);
    if (!remote) {
      this.publish({ serverRevision: revision });
      this.mustPull = false;
      this.syncBase = null;
      this.uploaded.clear();
      return;
    }
    const attachments = new Map<string, Blob>();
    const priorMarker = readSyncMarker(this.account!.user.id, this.storage);
    const knownFiles = this.syncBase
      ? originals(this.syncBase.snapshot)
      : priorMarker?.serverRevision === remote.revision
        ? originals(remote.snapshot)
        : new Map<string, string | undefined>();
    const localFiles = originals(this.requiredSnapshot());
    for (const [filename, type] of originals(remote.snapshot)) {
      this.assertIdentity(identity);
      // Original names are stable. Already shared files stay cached; new device files download first.
      const fileOwners = (snapshot: AppSnapshot | undefined) => [
        ...(snapshot?.records.filter((record) => record.sourceFilename === filename) ?? []),
        ...(snapshot?.recordings.filter((recording) => recording.audioFilename === filename) ?? []),
      ];
      const immutable = /^reva-[a-f0-9]{64}(?:\.[a-z0-9]{1,10})?$/.test(filename);
      const ownersUnchanged = this.syncBase
        ? sameSyncValue(fileOwners(this.syncBase.snapshot), fileOwners(remote.snapshot))
        : priorMarker?.serverRevision === remote.revision;
      if (knownFiles.has(filename) && localFiles.has(filename) && (immutable || ownersUnchanged)) {
        try {
          await this.persistence.getAttachment(filename);
          continue;
        } catch {
          /* Download missing cache. */
        }
      }
      const blob = await api.attachment(filename);
      if (immutable && (await this.blobHash(blob)) !== filename.slice(5, 69))
        throw new Error(
          'A downloaded original did not match its saved content fingerprint. The existing local file was kept.',
        );
      attachments.set(filename, type ? blob.slice(0, blob.size, type) : blob);
    }
    await this.queue(async () => {
      this.assertIdentity(identity);
      for (let attempt = 0; ; attempt++) {
        const durable = await this.persistence.load();
        if (durable && durable.revision !== this.localRevision) this.adopt(durable);
        const local = structuredClone(this.requiredSnapshot());
        const originalConflicts = { records: new Set<string>(), recordings: new Set<string>() };
        // If two devices reused a filename for different bytes, retain this device's original separately.
        for (const [filename, remoteBlob] of [...attachments]) {
          if (!originals(local).has(filename)) continue;
          let localBlob: Blob;
          try {
            localBlob = await this.persistence.getAttachment(filename);
          } catch {
            continue;
          }
          const localHash = await this.blobHash(localBlob);
          if (localHash === (await this.blobHash(remoteBlob))) continue;
          const extension = filename.includes('.') ? `.${filename.split('.').pop()}` : '';
          const preserved = `sync-original-${localHash}${extension}`;
          attachments.set(preserved, localBlob);
          local.records.forEach((record) => {
            if (record.sourceFilename !== filename) return;
            record.sourceFilename = preserved;
            if (remote.snapshot.records.some((item) => item.id === record.id))
              originalConflicts.records.add(record.id);
          });
          local.recordings.forEach((recording) => {
            if (recording.audioFilename !== filename) return;
            recording.audioFilename = preserved;
            if (remote.snapshot.recordings.some((item) => item.id === recording.id))
              originalConflicts.recordings.add(recording.id);
          });
        }
        const marker = readSyncMarker(this.account!.user.id, this.storage);
        const base =
          this.syncBase?.snapshot ??
          (marker?.serverRevision === remote.revision
            ? remote.snapshot
            : marker?.localRevision === this.localRevision
              ? this.requiredSnapshot()
              : null);
        const merged = mergeSnapshots(base, local, remote.snapshot, originalConflicts);
        this.assertIdentity(identity);
        try {
          if (!sameSyncValue(this.requiredSnapshot(), merged.snapshot) || attachments.size)
            this.adopt(await this.persistence.commit(merged.snapshot, this.localRevision, attachments));
          this.mustPull = false;
          this.publish({ serverRevision: remote.revision });
          await this.rememberSync(
            remote.revision,
            sameSyncValue(merged.snapshot, remote.snapshot) ? this.localRevision : 0,
            remote.snapshot,
          );
          if (merged.recovered) this.notify(SERVER_DIFFERS_NOTICE);
          return;
        } catch (error) {
          if (!(error instanceof LocalConflictError) || attempt >= 3) throw error;
        }
      }
    });
  }
  private async blobHash(blob: Blob): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer());
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  }
  private async normalizeAccountOriginals(identity: number): Promise<void> {
    if (!this.account) return;
    await this.queue(async () => {
      const snapshot = structuredClone(this.requiredSnapshot());
      const attachments = new Map<string, Blob>();
      for (const [filename] of originals(snapshot)) {
        const blob = await this.persistence.getAttachment(filename);
        const hash = await this.blobHash(blob);
        const extension = filename.split('.').pop()?.toLowerCase();
        const suffix =
          filename.includes('.') && extension && /^[a-z0-9]{1,10}$/.test(extension) ? `.${extension}` : '';
        const immutable = `reva-${hash}${suffix}`;
        if (immutable === filename) continue;
        attachments.set(immutable, blob);
        snapshot.records.forEach((record) => {
          if (record.sourceFilename === filename) record.sourceFilename = immutable;
        });
        snapshot.recordings.forEach((recording) => {
          if (recording.audioFilename === filename) recording.audioFilename = immutable;
        });
      }
      this.assertIdentity(identity);
      if (attachments.size)
        this.adopt(await this.persistence.commit(snapshot, this.localRevision, attachments));
    });
  }

  // MARK: - Account actions revoke sessions on the server before leaving the workspace.
  accountUser = (): SessionUser | null => this.account?.user ?? null;
  private requireAuth(): AuthTransport {
    if (!this.account) throw new Error('Account actions are available only in a signed-in workspace.');
    return this.authFactory(this.state.token);
  }
  private async flushBeforeLeaving(): Promise<void> {
    try {
      await this.syncTask;
    } catch {
      /* Local edits survive an offline logout. */
    }
    if (!this.syncPending && this.syncBase && sameSyncValue(this.syncBase.snapshot, this.state.snapshot))
      return;
    this.cancelSync();
    try {
      await this.synchronizeAccount();
    } catch {
      /* Chunk: Unsent edits stay in the local copy; the next login pushes them. */
    }
  }
  private async revoke(everywhere: boolean): Promise<void> {
    await this.cancelProviderWork();
    const auth = this.requireAuth();
    await this.writes;
    await this.flushBeforeLeaving();
    try {
      if (everywhere) await auth.logoutAll();
      else await auth.logout();
    } catch (error) {
      if (!(error instanceof APIError && error.status === 401)) throw error;
    }
    this.endSession(null, '/');
  }
  logout = async (): Promise<void> => {
    await this.cancelProviderWork();
    await this.action(() => this.revoke(false));
  };
  logoutAll = async (): Promise<void> => {
    await this.cancelProviderWork();
    await this.action(() => this.revoke(true));
  };
  changePassword = (currentPassword: string, newPassword: string): Promise<void> =>
    this.action(async () => {
      const auth = this.requireAuth();
      try {
        await auth.changePassword(currentPassword, newPassword);
      } catch (error) {
        if (error instanceof APIError && error.status === 401)
          throw new Error('The current password is incorrect. Your password was not changed.');
        throw error;
      }
      this.notify('Password changed. Your other sessions were logged out.');
    });
  deleteAccount = async (password: string): Promise<void> => {
    await this.cancelProviderWork();
    await this.action(async () => {
      const auth = this.requireAuth();
      await this.writes;
      try {
        await auth.deleteAccount(password);
      } catch (error) {
        if (error instanceof APIError && error.status === 401)
          throw new Error('The password is incorrect. Your account was not deleted.');
        throw error;
      }
      this.cancelSync();
      clearSyncMarker(this.account!.user.id, this.storage);
      try {
        await this.persistence.destroy?.();
      } catch {
        /* Chunk: The server copy is gone; a lingering local database only holds this user's own data. */
      }
      this.endSession(null, '/');
    });
  };

  // MARK: - Source and visit editing retain exact user-authored questions, notes and versions.
  // Every preview and capture stays bound to this workspace's repository, including account stores.
  getAttachment = (filename: string): Promise<Blob> => this.persistence.getAttachment(filename);
  // Imports publish their original in the same transaction as the source, including on retry.
  saveRecord = (record: MedicalRecord, expectedVersion?: number, original?: Blob): Promise<void> =>
    this.edit(
      (draft) => {
        if (original && !record.sourceFilename) throw new Error('The original filename is missing.');
        upsertRecord(draft, record, expectedVersion);
      },
      original && record.sourceFilename ? new Map([[record.sourceFilename, original]]) : undefined,
    );
  // Recording metadata and original audio commit together, so a failed save can safely be retried.
  saveRecording = (recording: VisitRecording, original: Blob): Promise<void> =>
    this.edit(
      (draft) => {
        if (!recording.audioFilename) throw new Error('The original audio filename is missing.');
        if (recording.visitID && !draft.visits.some((visit) => visit.id === recording.visitID))
          throw new Error('This visit is no longer available.');
        if (draft.recordings.some((saved) => saved.id === recording.id))
          throw new Error('This recording was already saved. Close this dialog to review it.');
        draft.recordings.push(structuredClone(recording));
      },
      recording.audioFilename ? new Map([[recording.audioFilename, original]]) : undefined,
    );
  deleteRecord = (id: string): Promise<void> =>
    this.edit((draft) => {
      draft.records = draft.records.filter((record) => record.id !== id);
      draft.visits.forEach((visit) => {
        visit.pinnedRecordIDs = visit.pinnedRecordIDs.filter((recordID) => recordID !== id);
      });
    });
  saveVisit = (visit: Visit): Promise<void> =>
    this.edit((draft) => {
      const saved = structuredClone(visit);
      if (!saved.title.trim() || !Number.isFinite(Date.parse(saved.date)))
        throw new Error('Enter a visit title and valid date.');
      if (saved.report) {
        saved.report.questions = [...saved.questions];
        saved.report.notes = saved.notes;
      }
      const index = draft.visits.findIndex((item) => item.id === saved.id);
      if (index < 0) draft.visits.push(saved);
      else draft.visits[index] = saved;
    });
  saveMemory = (
    recordingID: string,
    correctedSegmentTexts?: Record<string, string>,
    expectedTranscript?: string,
  ): Promise<void> =>
    this.edit((draft) => {
      if (
        expectedTranscript !== undefined &&
        JSON.stringify(draft.recordings.find((recording) => recording.id === recordingID)?.segments) !==
          expectedTranscript
      )
        throw new Error(
          'The transcript changed while this editor was open. Reopen it before correcting the words.',
        );
      reconcileMemory(draft, recordingID, correctedSegmentTexts);
      const recording = draft.recordings.find((item) => item.id === recordingID);
      if (
        correctedSegmentTexts &&
        recording?.audioFilename &&
        !recording.isSample &&
        !hasRecordingSummary(recording)
      )
        recording.status = 'processing-analyzing';
    });

  // MARK: - Summary publication checks the captured source before applying provider text.
  summarizeRecord = (id: string): Promise<void> =>
    this.providerAction((signal) =>
      this.action(async () => {
        const original = structuredClone(this.requiredSnapshot().records.find((record) => record.id === id));
        if (!original) throw new Error('This record is no longer available.');
        if (!this.state.connectedAI) {
          await this.edit((draft) => {
            const latest = draft.records.find((record) => record.id === id);
            if (!latest) throw new Error('This record is no longer available.');
            upsertRecord(draft, {
              ...latest,
              summary: localExcerpt(latest.text, latest.isDemo),
              summaryModel: undefined,
              summaryGeneratedAt: undefined,
            });
          });
          this.notify('Original-text excerpt saved.');
          return;
        }
        const identity = this.identity,
          result = await providerResult(signal, () =>
            this.apiFactory(this.state.token).summarize(original, signal),
          );
        signal.throwIfAborted();
        this.assertIdentity(identity);
        if (!result.summary.trim())
          throw new Error('The AI returned no summary. Your previous summary was kept.');
        await this.edit((draft) => {
          signal.throwIfAborted();
          this.assertIdentity(identity);
          const latest = draft.records.find((record) => record.id === id);
          if (!latest || latest.version !== original.version || latest.text !== original.text)
            throw new Error(
              'This record changed during summarization. Your edits were kept; retry with the current source.',
            );
          upsertRecord(draft, {
            ...latest,
            summary: result.summary,
            summaryModel: result.model,
            summaryGeneratedAt: nowISO(),
          });
        });
        this.notify('AI summary saved. Review it against the original source.');
      }),
    );

  // Always call the server on request; this result is never written to the appointment log.
  generateVisitBrief = (input: VisitBriefInput, external?: AbortSignal): Promise<ClinicalBrief> =>
    this.providerAction(async (signal) => {
      const identity = this.identity;
      const snapshot = structuredClone(this.requiredSnapshot());
      if (this.state.mode === 'demo' && snapshot.profile.isDemo) {
        signal.throwIfAborted();
        return demoClinicalBrief(snapshot, input);
      }
      const visit = briefVisit(input),
        sources = briefSources(snapshot);
      try {
        const result = await providerResult(signal, () =>
          this.apiFactory(this.state.token).prepare(visit, sources, signal),
        );
        signal.throwIfAborted();
        this.assertIdentity(identity);
        if (briefContextSignature(snapshot) !== briefContextSignature(this.requiredSnapshot()))
          throw new Error(
            'Your records or profile changed. Generate a new brief with the current information.',
          );
        return clinicalBrief(snapshot, visit, sources, result);
      } catch (error) {
        if (!(error instanceof Error && error.name === 'AbortError')) this.reportError(error);
        throw error;
      }
    }, external);

  // MARK: - Reports preserve source signatures and authoritative questions through asynchronous work.
  prepareVisit = (id: string): Promise<void> =>
    this.providerAction((signal) =>
      this.action(async () => {
        const snapshot = structuredClone(this.requiredSnapshot()),
          original = snapshot.visits.find((visit) => visit.id === id);
        if (!original) throw new Error('This visit is no longer available.');
        const identity = this.identity,
          connected = this.state.connectedAI,
          api = connected ? this.apiFactory(this.state.token) : null;
        const signature = await reportSignature(original, snapshot.records);
        const candidates = snapshot.records
          .filter((record) => record.text.trim())
          .map((record) => ({ ...record, summary: currentSummary(record) }));
        if (connected && !candidates.length)
          throw new Error(
            'Add readable sources before using connected preparation, or turn it off to prepare locally.',
          );
        this.assertIdentity(identity);
        const result = api
          ? await providerResult(signal, () => api.prepare(original, candidates, signal))
          : null;
        signal.throwIfAborted();
        this.assertIdentity(identity);
        if (
          result &&
          result.selectedRecordIDs.some((recordID) => !candidates.some((record) => record.id === recordID))
        )
          throw new Error('The AI returned an unknown source. No report was saved.');
        await this.edit(async (draft) => {
          signal.throwIfAborted();
          this.assertIdentity(identity);
          const latest = draft.visits.find((visit) => visit.id === id);
          if (!latest || signature !== (await reportSignature(latest, draft.records)))
            throw new Error(
              'Sources or visit details changed during preparation. Your edits were kept; prepare again.',
            );
          if (result) {
            const selected = new Set([...result.selectedRecordIDs, ...latest.pinnedRecordIDs]);
            const report = await generateReport(
              { ...latest, pinnedRecordIDs: [...selected] },
              draft.records.filter((record) => selected.has(record.id)),
            );
            report.sourceSignature = signature;
            report.generationModel = result.model;
            report.isDemo = false;
            report.sections.splice(Math.min(1, report.sections.length), 0, {
              id: uid(),
              title: 'AI preparation overview · review with your clinician',
              body: result.overview,
              sources: [],
            });
            if (
              !original.report &&
              !original.questions.length &&
              JSON.stringify(latest.questions) === JSON.stringify(original.questions)
            )
              latest.questions = [...result.questions];
            report.questions = [...latest.questions];
            report.notes = latest.notes;
            latest.report = report;
          } else {
            const report = await generateReport(latest, draft.records);
            latest.questions = [...report.questions];
            latest.report = report;
          }
          this.assertIdentity(identity);
        });
        this.notify(
          result
            ? 'AI-assisted brief ready. Review its overview and original source excerpts.'
            : 'Visit brief ready with original source excerpts.',
        );
      }),
    );

  // MARK: - Transcription keeps original audio and rejects mismatched or edited transcript results.
  private async recordingAction(
    id: string,
    work: (signal: AbortSignal) => Promise<void>,
    background: boolean,
    external?: AbortSignal,
  ) {
    if (this.recordingRequests.has(id)) throw new Error('This recording is already being processed.');
    this.recordingRequests.add(id);
    try {
      await this.providerAction(
        (signal) => (background ? work(signal) : this.action(() => work(signal))),
        external,
      );
    } catch (error) {
      if (background && error instanceof APIError && error.status === 401) this.reportError(error);
      throw error;
    } finally {
      this.recordingRequests.delete(id);
    }
  }
  transcribeRecording = (id: string, external?: AbortSignal, background = false): Promise<void> =>
    this.recordingAction(
      id,
      async (signal) => {
        const checkCancellation = () => {
          if (signal?.aborted)
            throw new DOMException('Transcription canceled. Your audio was kept.', 'AbortError');
        };
        checkCancellation();
        const original = structuredClone(
          this.requiredSnapshot().recordings.find((recording) => recording.id === id),
        );
        if (!original || original.isSample || !original.audioFilename)
          throw new Error('Save a real audio recording before requesting transcription.');
        if (!this.state.providers?.transcription.configured)
          throw new Error('Check a server with configured transcription first.');
        const identity = this.identity,
          blob = await this.persistence.getAttachment(original.audioFilename);
        const type = audioType(original.audioFilename) ?? blob.type.split(';')[0];
        if (
          ![
            'audio/mp4',
            'audio/m4a',
            'audio/x-m4a',
            'audio/wav',
            'audio/x-wav',
            'audio/mpeg',
            'audio/webm',
            'audio/ogg',
          ].includes(type)
        )
          throw new Error(
            'This recording format is not supported for transcription. Its original audio is preserved.',
          );
        this.assertIdentity(identity);
        const result = await providerResult(signal, () =>
          this.apiFactory(this.state.token).transcribe(
            original.audioFilename!,
            blob.slice(0, blob.size, type),
            signal,
          ),
        );
        checkCancellation();
        this.assertIdentity(identity);
        if (
          !result.text.trim() ||
          !result.segments.length ||
          new Set(result.segments.map((segment) => segment.id)).size !== result.segments.length ||
          result.segments.some(
            (segment) =>
              !segment.id ||
              !segment.text.trim() ||
              !Number.isFinite(segment.start) ||
              !Number.isFinite(segment.end) ||
              segment.start < 0 ||
              segment.end < segment.start ||
              segment.end > original.duration + 5,
          )
        )
          throw new Error(
            'The transcript did not match valid audio timestamps. Your previous transcript was kept.',
          );
        await this.edit((draft) => {
          checkCancellation();
          this.assertIdentity(identity);
          const latest = draft.recordings.find((recording) => recording.id === id);
          if (
            !latest ||
            latest.audioFilename !== original.audioFilename ||
            JSON.stringify(latest.segments) !== JSON.stringify(original.segments)
          )
            throw new Error('Audio or transcript changed during transcription. Your edits were kept.');
          if (
            original.status === 'processing-retranscribing' ||
            JSON.stringify(latest.segments) !== JSON.stringify(result.segments)
          )
            clearRecordingSummary(latest);
          latest.segments = result.segments;
          latest.transcriptionModel = result.model;
          latest.status = background ? 'processing-analyzing' : 'ready';
          if (draft.records.some((record) => record.sourceRecordingID === id || record.id === `memory-${id}`))
            reconcileMemory(
              draft,
              id,
              Object.fromEntries(result.segments.map((segment) => [segment.id, segment.text])),
            );
        });
        if (!background)
          this.notify('Transcript saved. Review the words and speakers against the original recording.');
      },
      background,
      external,
    );

  // MARK: - Appointment summaries use only the exact saved transcript and reject stale or canceled work.
  summarizeRecording = (
    id: string,
    external?: AbortSignal,
    background = false,
    onRetry?: (retry: GeminiRetryState | null) => void,
  ): Promise<void> =>
    this.recordingAction(
      id,
      async (signal) => {
        const snapshot = this.requiredSnapshot();
        const original = structuredClone(snapshot.recordings.find((recording) => recording.id === id));
        if (
          !original ||
          !original.segments.length ||
          original.segments.some((segment) => !segment.text.trim())
        )
          throw new Error('Transcribe this appointment before summarizing it.');
        if (!this.state.providers?.gemini.configured)
          throw new Error('Check a server with configured AI before summarizing this appointment.');
        const checkCancellation = () => {
          if (signal?.aborted)
            throw new DOMException('Summarization canceled. Your saved audio was kept.', 'AbortError');
        };
        const identity = this.identity;
        const source: MedicalRecord = {
          id: original.id,
          title: original.title,
          text: recordingTranscript(original),
          summary: '',
          notes: '',
          kind: 'Recording',
          provider: '',
          date: calendarDay(new Date(recordingInstant(original))),
          dateSource: original.capturedAt ? 'recorded' : original.savedAt ? 'added' : undefined,
          uploadedAt: original.savedAt ?? original.createdAt,
          pageCount: 1,
          tags: [],
          status: 'ready',
          isDemo: original.isSample,
          version: 1,
        };
        checkCancellation();
        const generateTitle = original.titleSource === 'date';
        const result = await providerResult(signal, () =>
          this.apiFactory(this.state.token).summarize(source, signal, {
            generateTitle,
            date: recordDateContext(source),
            onRetry,
          }),
        );
        checkCancellation();
        this.assertIdentity(identity);
        if (!result.summary.trim() || !result.model.trim())
          throw new Error('The AI returned no usable summary. Your previous summary was kept.');
        const generatedTitle = generateTitle ? result.title?.trim() : undefined;
        if (
          generateTitle &&
          (!generatedTitle ||
            new TextEncoder().encode(generatedTitle).length > 120 ||
            /[\r\n\u0000-\u001f]/.test(generatedTitle))
        )
          throw new Error('The AI returned no usable recording title. Your saved recording was kept.');
        await this.edit((draft) => {
          checkCancellation();
          this.assertIdentity(identity);
          const latest = draft.recordings.find((recording) => recording.id === id);
          if (
            !latest ||
            latest.visitID !== original.visitID ||
            latest.createdAt !== original.createdAt ||
            latest.capturedAt !== original.capturedAt ||
            latest.savedAt !== original.savedAt ||
            (!generateTitle && latest.title !== original.title) ||
            latest.audioFilename !== original.audioFilename ||
            latest.duration !== original.duration ||
            latest.isSample !== original.isSample ||
            JSON.stringify(latest.segments) !== JSON.stringify(original.segments)
          )
            throw new Error(
              'The transcript or recording changed during summarization. Your edits were kept; summarize again.',
            );
          const automaticTitle =
            generatedTitle && latest.titleSource === 'date' && latest.title === original.title;
          if (automaticTitle) {
            latest.title = generatedTitle;
            latest.titleSource = 'ai';
          } else if (generateTitle && latest.title !== original.title && latest.titleSource === 'date') {
            latest.titleSource = 'user';
          }
          latest.aiSummary = result.summary;
          latest.aiSummaryModel = result.model;
          latest.aiSummaryGeneratedAt = nowISO();
          const index = draft.records.findIndex(
            (record) => record.id === `memory-${id}` || record.sourceRecordingID === id,
          );
          if (index >= 0) {
            const memory = createMemoryRecord(latest, draft, true);
            if (automaticTitle && memory.title === `${original.title} · memory`) {
              memory.title = `${latest.title} · memory`;
              if (memory.version === draft.records[index].version) memory.version += 1;
            }
            draft.records[index] = memory;
          }
        });
        if (!background)
          this.notify('Appointment summary saved. Review it against the transcript and original audio.');
      },
      background,
      external,
    );

  // MARK: - Revision-aware discovery and explicit synchronization.
  private async discover(api: APITransport): Promise<Discovery> {
    const health = await api.health(),
      providers = await api.providers();
    try {
      const remote = await api.pull();
      return { health, providers, remote, revision: remote.revision };
    } catch (error) {
      if (!(error instanceof APIError) || error.status !== 404 || error.revision === null) throw error;
      return { health, providers, remote: null, revision: error.revision };
    }
  }
  checkServer = (): Promise<void> =>
    this.action(async () => {
      const identity = this.identity,
        api = this.apiFactory(this.state.token),
        found = await this.discover(api);
      this.assertIdentity(identity);
      const known = this.state.serverRevision;
      this.publish({
        providers: found.providers,
        connectedAI: this.state.connectedAI && found.providers.gemini.configured,
      });
      if (this.mustPull || (known !== null && known !== found.revision)) {
        this.mustPull = true;
        this.notify(
          `${found.health}. The server has a different revision; pull and review it before pushing.`,
        );
      } else {
        this.publish({ serverRevision: found.revision });
        this.notify(`${found.health}. Provider availability checked.`);
      }
    });
  // Account originals use content-addressed names and digests, so concurrent uploads cannot replace bytes.
  private async push(quiet: boolean): Promise<void> {
    if (this.state.serverRevision === null || this.mustPull)
      throw new Error('Check the connection or pull the server’s latest copy before pushing.');
    await this.writes;
    await this.normalizeAccountOriginals(this.identity);
    const snapshot = structuredClone(this.requiredSnapshot()),
      identity = this.identity,
      revision = this.state.serverRevision,
      localRevision = this.localRevision,
      api = this.apiFactory(this.state.token);
    for (const [filename, type] of originals(snapshot)) {
      const blob = await this.persistence.getAttachment(filename);
      const key = `${filename}\u0000${this.account ? await this.blobHash(blob) : blob.size}`;
      if (this.account && this.uploaded.has(key)) continue;
      this.assertIdentity(identity);
      await api.uploadAttachment(filename, type ? blob.slice(0, blob.size, type) : blob);
      if (this.account) this.uploaded.add(key);
    }
    this.assertIdentity(identity);
    try {
      const next = await api.push(snapshot, revision);
      this.assertIdentity(identity);
      this.publish({ serverRevision: next });
      await this.rememberSync(next, localRevision, snapshot);
      if (!quiet)
        this.notify(
          localRevision === this.localRevision
            ? 'Browser snapshot and originals sent to the server.'
            : 'Captured snapshot sent. Newer browser edits remain local; push again to send them.',
        );
      else if (localRevision !== this.localRevision) this.scheduleSync();
    } catch (error) {
      if (error instanceof APIError && error.status === 409 && identity === this.identity && !this.account)
        this.mustPull = true;
      throw error;
    }
  }
  pushToServer = (): Promise<void> => (this.account ? this.autoSync() : this.action(() => this.push(false)));
  // Downloads every original first, then replaces the local copy in one transaction.
  private async applyRemote(
    api: APITransport,
    remote: ServerState,
    identity: number,
    localRevision: number,
  ): Promise<void> {
    const attachments = new Map<string, Blob>();
    for (const [filename, type] of originals(remote.snapshot)) {
      this.assertIdentity(identity);
      const blob = await api.attachment(filename);
      attachments.set(filename, type ? blob.slice(0, blob.size, type) : blob);
    }
    this.assertIdentity(identity);
    await this.queue(async () => {
      this.assertIdentity(identity);
      if (localRevision !== this.localRevision)
        throw new Error(
          'You edited this browser workspace during the download. Your edits were kept. Review them before pulling again.',
        );
      this.adopt(await this.persistence.commit(remote.snapshot, localRevision, attachments));
      this.mustPull = false;
      this.publish({ serverRevision: remote.revision });
      await this.rememberSync(remote.revision, this.localRevision, remote.snapshot);
    });
  }
  pullFromServer = (): Promise<void> =>
    this.account
      ? this.autoSync()
      : this.action(async () => {
          await this.writes;
          const identity = this.identity,
            localRevision = this.localRevision,
            api = this.apiFactory(this.state.token),
            remote = await api.pull();
          await this.applyRemote(api, remote, identity, localRevision);
          this.notify('Server snapshot and all originals saved in this browser.');
        });
}
interface Discovery {
  health: string;
  providers: ProviderStatus;
  remote: ServerState | null;
  revision: number;
}
