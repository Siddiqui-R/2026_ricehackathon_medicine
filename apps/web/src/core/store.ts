import {
  briefContextSignature,
  briefVisit,
  briefSources,
  clinicalBrief,
  type ClinicalBrief,
  type VisitBriefInput,
} from './visitBrief';
// Purpose: Coordinate durable browser state, source-aware edits and deliberate connected actions.
// Inputs: UI intents, an injectable repository/API factory, reviewed provider requests and, in account
//         mode, the signed-in session (token, user) with injectable storage/redirect boundaries.
// Outputs: Observable state with durable snapshots, notices, capability flags and explicit failures.
// Side effects: Serial IndexedDB writes; explicit sync/provider requests in demo mode; in account mode a
//               debounced push after each local commit, and a cleared session plus redirect on HTTP 401.
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
  invalidateChangedRecordingSummaries,
  reconcileMemory,
  recordingTranscript,
  upsertRecord,
} from './mutations.ts';
import { APIError, RevaAPI } from './api.ts';
import { AuthAPI, type AuthTransport } from './auth.ts';
import { emptyPersonalSnapshot } from './account.ts';
import { browserStorage, clearSession, type SessionUser, type StorageLike } from './session.ts';
import { clearSyncMarker, readSyncMarker, writeSyncMarker } from './syncMarker.ts';
import { repository, type SnapshotRepository, type StoredSnapshot } from './repository.ts';

// MARK: - Observable values deliberately exclude credentials from durable snapshot state.
export interface RevaState {
  snapshot: AppSnapshot | null;
  loading: boolean;
  error: string | null;
  notice: string | null;
  busy: boolean;
  providers: ProviderStatus | null;
  connectedAI: boolean;
  token: string;
  serverRevision: number | null;
  mode: 'demo' | 'account';
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
}
export type StoreOptions = DemoOptions | AccountOptions;
export const SESSION_ENDED_PATH = '/login?reason=session';
export const SESSION_ENDED_NOTICE = 'Your session ended. Log in again to continue.';
export const SERVER_DIFFERS_NOTICE = 'The server copy differs; pull to review it.';
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

// MARK: - A testable store serializes commits and publishes only after storage succeeds.
export class RevaStore {
  private state: RevaState = {
    snapshot: null,
    loading: true,
    error: null,
    notice: null,
    busy: false,
    providers: null,
    connectedAI: false,
    token: 'reva-local-demo-token',
    serverRevision: null,
    mode: 'demo',
    account: null,
  };
  private listeners = new Set<() => void>();
  private localRevision = 0;
  private writes: Promise<unknown> = Promise.resolve();
  private initialization?: Promise<void>;
  private identity = 0;
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
        account: { user: this.account.user, expiresAt: this.account.expiresAt ?? null },
      };
  }
  getState = (): RevaState => this.state;
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
        this.adopt(await this.persistence.commit(validateSnapshot(draft), this.localRevision, attachments));
      });
      this.scheduleSync();
    } catch (error) {
      this.reportError(error);
      throw error;
    }
  }
  // Quiet actions (auto-sync) keep the current notice; a failure still reaches the error banner.
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
      if (this.account) throw new Error('The demo is not available inside an account workspace.');
      const seed = await this.persistence.seed();
      await this.queue(async () => {
        this.adopt(await this.persistence.reset(seed));
        this.mustPull = false;
        this.publish({ loading: false, serverRevision: null });
      });
      this.notify('Demo restored in this browser.');
    });
  setToken = (token: string): void => {
    if (token === this.state.token) return;
    if (this.account) {
      this.reportError(new Error('Your account session is the workspace token; log out to switch accounts.'));
      return;
    }
    if (this.state.busy) {
      this.reportError(
        new Error('Wait for the current action to finish before changing the workspace token.'),
      );
      return;
    }
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

  // MARK: - Account startup: local first, then reconcile with the server without discarding either copy.
  private async initializeAccount(): Promise<void> {
    let existing: StoredSnapshot | null = null;
    try {
      existing = await this.persistence.load();
      if (existing) this.adopt(existing);
    } catch (error) {
      this.reportError(error);
      this.publish({ loading: false });
      return;
    }
    try {
      await this.reconcileWithServer(existing);
    } catch (error) {
      this.reportError(error);
    }
    this.publish({ loading: false });
  }
  private async reconcileWithServer(existing: StoredSnapshot | null): Promise<void> {
    const account = this.account!,
      identity = this.identity,
      api = this.apiFactory(this.state.token),
      found = await this.discover(api);
    this.assertIdentity(identity);
    this.publish({ providers: found.providers });
    if (existing) {
      this.positionAgainstServer(found);
      return;
    }
    if (found.remote) {
      await this.applyRemote(api, found.remote, identity, 0);
      this.notify('Your account data was downloaded to this browser.');
      return;
    }
    const empty = emptyPersonalSnapshot(account.user);
    await this.queue(async () => {
      this.assertIdentity(identity);
      this.adopt(await this.persistence.commit(empty, 0));
    });
    const localRevision = this.localRevision;
    this.publish({ serverRevision: found.revision });
    const next = await api.push(empty, found.revision);
    this.assertIdentity(identity);
    this.publish({ serverRevision: next });
    this.rememberSync(next, localRevision);
  }
  // With a local copy present, the remembered in-sync revision decides whether pushing is safe.
  private positionAgainstServer(found: Discovery): void {
    const marker = readSyncMarker(this.account!.user.id, this.storage);
    if (!found.remote) {
      this.publish({ serverRevision: found.revision });
      this.scheduleSync();
      return;
    }
    if (marker && marker.serverRevision === found.remote.revision) {
      this.publish({ serverRevision: found.remote.revision });
      if (marker.localRevision !== this.localRevision) this.scheduleSync();
      return;
    }
    this.mustPull = true;
    this.publish({ serverRevision: found.remote.revision });
    this.notify(SERVER_DIFFERS_NOTICE);
  }
  private rememberSync(serverRevision: number, localRevision: number): void {
    if (this.account) writeSyncMarker(this.account.user.id, { serverRevision, localRevision }, this.storage);
  }
  private endSession(notice: string | null, path: string): void {
    if (this.sessionEnded) return;
    this.sessionEnded = true;
    this.cancelSync();
    clearSession(this.storage);
    if (notice) this.publish({ notice, error: null });
    this.redirect(path);
  }

  // MARK: - Auto-sync: a debounced quiet push after local commits, never while busy or behind the server.
  private scheduleSync(): void {
    if (!this.account || this.sessionEnded) return;
    this.syncPending = true;
    if (this.syncTimer) clearTimeout(this.syncTimer);
    this.syncTimer = setTimeout(() => {
      this.syncTimer = null;
      void this.autoSync();
    }, this.syncDelay);
  }
  private cancelSync(): void {
    if (this.syncTimer) clearTimeout(this.syncTimer);
    this.syncTimer = null;
    this.syncPending = false;
  }
  private async autoSync(): Promise<void> {
    if (!this.account || this.sessionEnded || this.mustPull) {
      this.syncPending = false;
      return;
    }
    if (this.state.busy) return;
    this.syncPending = false;
    try {
      await this.action(async () => {
        if (this.state.serverRevision === null) {
          const identity = this.identity,
            api = this.apiFactory(this.state.token),
            found = await this.discover(api);
          this.assertIdentity(identity);
          this.publish({
            providers: found.providers,
            connectedAI: this.state.connectedAI && found.providers.gemini.configured,
          });
          this.positionAgainstServer(found);
          if (this.mustPull) return;
        }
        await this.push(true);
      }, true);
    } catch {
      /* Chunk: The action already showed the error banner; the local snapshot is untouched. */
    }
  }

  // MARK: - Account actions revoke sessions on the server before leaving the workspace.
  accountUser = (): SessionUser | null => this.account?.user ?? null;
  private requireAuth(): AuthTransport {
    if (!this.account) throw new Error('Account actions are available only in a signed-in workspace.');
    return this.authFactory(this.state.token);
  }
  private async flushBeforeLeaving(): Promise<void> {
    if (!this.syncPending || this.mustPull || this.state.serverRevision === null) return;
    this.cancelSync();
    try {
      await this.push(true);
    } catch {
      /* Chunk: Unsent edits stay in the local copy; the next login pushes them. */
    }
  }
  private async revoke(everywhere: boolean): Promise<void> {
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
  logout = (): Promise<void> => this.action(() => this.revoke(false));
  logoutAll = (): Promise<void> => this.action(() => this.revoke(true));
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
  deleteAccount = (password: string): Promise<void> =>
    this.action(async () => {
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
    });

  // MARK: - Summary publication checks the captured source before applying provider text.
  summarizeRecord = (id: string): Promise<void> =>
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
          });
        });
        this.notify('Original-text excerpt saved.');
        return;
      }
      const identity = this.identity,
        result = await this.apiFactory(this.state.token).summarize(original);
      this.assertIdentity(identity);
      if (!result.summary.trim())
        throw new Error('The AI returned no summary. Your previous summary was kept.');
      await this.edit((draft) => {
        this.assertIdentity(identity);
        const latest = draft.records.find((record) => record.id === id);
        if (!latest || latest.version !== original.version || latest.text !== original.text)
          throw new Error(
            'This record changed during summarization. Your edits were kept; retry with the current source.',
          );
        upsertRecord(draft, { ...latest, summary: result.summary, summaryModel: result.model });
      });
      this.notify('AI summary saved. Review it against the original source.');
    });

  // Always call the server on request; this result is never written to the appointment log.
  generateVisitBrief = async (input: VisitBriefInput): Promise<ClinicalBrief> => {
    const identity = this.identity;
    const snapshot = structuredClone(this.requiredSnapshot());
    const visit = briefVisit(input),
      sources = briefSources(snapshot);
    try {
      const result = await this.apiFactory(this.state.token).prepare(visit, sources);
      this.assertIdentity(identity);
      if (briefContextSignature(snapshot) !== briefContextSignature(this.requiredSnapshot()))
        throw new Error(
          'Your records or profile changed. Generate a new brief with the current information.',
        );
      return clinicalBrief(snapshot, visit, sources, result);
    } catch (error) {
      this.reportError(error);
      throw error;
    }
  };

  // MARK: - Reports preserve source signatures and authoritative questions through asynchronous work.
  prepareVisit = (id: string): Promise<void> =>
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
      const result = api ? await api.prepare(original, candidates) : null;
      this.assertIdentity(identity);
      if (
        result &&
        result.selectedRecordIDs.some((recordID) => !candidates.some((record) => record.id === recordID))
      )
        throw new Error('The AI returned an unknown source. No report was saved.');
      await this.edit(async (draft) => {
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
    });

  // MARK: - Transcription keeps original audio and rejects mismatched or edited transcript results.
  transcribeRecording = (id: string): Promise<void> =>
    this.action(async () => {
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
      const result = await this.apiFactory(this.state.token).transcribe(
        original.audioFilename,
        blob.slice(0, blob.size, type),
      );
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
        this.assertIdentity(identity);
        const latest = draft.recordings.find((recording) => recording.id === id);
        if (
          !latest ||
          latest.audioFilename !== original.audioFilename ||
          JSON.stringify(latest.segments) !== JSON.stringify(original.segments)
        )
          throw new Error('Audio or transcript changed during transcription. Your edits were kept.');
        if (JSON.stringify(latest.segments) !== JSON.stringify(result.segments))
          clearRecordingSummary(latest);
        latest.segments = result.segments;
        latest.transcriptionModel = result.model;
        latest.status = 'ready';
        if (draft.records.some((record) => record.sourceRecordingID === id || record.id === `memory-${id}`))
          reconcileMemory(
            draft,
            id,
            Object.fromEntries(result.segments.map((segment) => [segment.id, segment.text])),
          );
      });
      this.notify('Transcript saved. Review the words and speakers against the original recording.');
    });

  // MARK: - Appointment summaries use only the exact saved transcript and reject stale or canceled work.
  summarizeRecording = (id: string, signal?: AbortSignal): Promise<void> =>
    this.action(async () => {
      const snapshot = this.requiredSnapshot();
      const original = structuredClone(snapshot.recordings.find((recording) => recording.id === id));
      if (!original || !original.segments.length || original.segments.some((segment) => !segment.text.trim()))
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
        date: original.createdAt,
        uploadedAt: original.createdAt,
        pageCount: 1,
        tags: [],
        status: 'ready',
        isDemo: original.isSample,
        version: 1,
      };
      checkCancellation();
      const result = await this.apiFactory(this.state.token).summarize(source, signal);
      checkCancellation();
      this.assertIdentity(identity);
      if (!result.summary.trim() || !result.model.trim())
        throw new Error('The AI returned no usable summary. Your previous summary was kept.');
      await this.edit((draft) => {
        checkCancellation();
        this.assertIdentity(identity);
        const latest = draft.recordings.find((recording) => recording.id === id);
        if (
          !latest ||
          latest.visitID !== original.visitID ||
          latest.createdAt !== original.createdAt ||
          latest.title !== original.title ||
          latest.audioFilename !== original.audioFilename ||
          latest.duration !== original.duration ||
          latest.isSample !== original.isSample ||
          JSON.stringify(latest.segments) !== JSON.stringify(original.segments)
        )
          throw new Error(
            'The transcript or recording changed during summarization. Your edits were kept; summarize again.',
          );
        latest.aiSummary = result.summary;
        latest.aiSummaryModel = result.model;
        latest.aiSummaryGeneratedAt = nowISO();
        const index = draft.records.findIndex(
          (record) => record.id === `memory-${id}` || record.sourceRecordingID === id,
        );
        if (index >= 0) draft.records[index] = createMemoryRecord(latest, draft, true);
      });
      this.notify('Appointment summary saved. Review it against the transcript and original audio.');
    });

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
  // Originals uploaded earlier in this account session under the same filename and size are skipped.
  private async push(quiet: boolean): Promise<void> {
    if (this.state.serverRevision === null || this.mustPull)
      throw new Error('Check the connection or pull the server’s latest copy before pushing.');
    await this.writes;
    const snapshot = structuredClone(this.requiredSnapshot()),
      identity = this.identity,
      revision = this.state.serverRevision,
      localRevision = this.localRevision,
      api = this.apiFactory(this.state.token);
    for (const [filename, type] of originals(snapshot)) {
      const blob = await this.persistence.getAttachment(filename);
      const key = `${filename}\u0000${blob.size}`;
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
      this.rememberSync(next, localRevision);
      if (!quiet)
        this.notify(
          localRevision === this.localRevision
            ? 'Browser snapshot and originals sent to the server.'
            : 'Captured snapshot sent. Newer browser edits remain local; push again to send them.',
        );
      else if (localRevision !== this.localRevision) this.scheduleSync();
    } catch (error) {
      if (error instanceof APIError && error.status === 409 && identity === this.identity)
        this.mustPull = true;
      throw error;
    }
  }
  pushToServer = (): Promise<void> => this.action(() => this.push(false));
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
      this.rememberSync(remote.revision, this.localRevision);
    });
  }
  pullFromServer = (): Promise<void> =>
    this.action(async () => {
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
