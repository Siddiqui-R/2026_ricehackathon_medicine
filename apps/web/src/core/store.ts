// Purpose: Coordinate durable browser state, source-aware edits and deliberate connected actions.
// Inputs: UI intents, an injectable repository/API factory and reviewed provider requests.
// Outputs: Observable state with durable snapshots, notices, capability flags and explicit failures.
// Side effects: Serial IndexedDB writes and explicit same-origin sync/provider requests; no automatic calls.
import type { AppSnapshot, BookingRequest, MedicalRecord, ProviderStatus, Visit } from './models.ts';
import { generateReport, localExcerpt, reportSignature, uid, validateSnapshot } from './domain.ts';
import { reconcileMemory, upsertRecord, validateBooking } from './mutations.ts';
import { APIError, RevaAPI } from './api.ts';
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
  | 'startCall'
  | 'callStatus'
>;
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
  };
  private listeners = new Set<() => void>();
  private localRevision = 0;
  private writes: Promise<unknown> = Promise.resolve();
  private initialization?: Promise<void>;
  private identity = 0;
  private mustPull = false;
  constructor(
    private readonly persistence: SnapshotRepository = repository,
    private readonly apiFactory: (token: string) => APITransport = (token) => new RevaAPI(token),
  ) {}
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
        const draft = structuredClone(this.requiredSnapshot());
        await change(draft);
        this.adopt(await this.persistence.commit(validateSnapshot(draft), this.localRevision, attachments));
      });
    } catch (error) {
      this.reportError(error);
      throw error;
    }
  }
  private async action(work: () => Promise<void>): Promise<void> {
    if (this.state.busy) throw new Error('Another connected action is still running. Wait for it to finish.');
    this.publish({ busy: true, error: null, notice: null });
    try {
      await work();
    } catch (error) {
      this.reportError(error);
      throw error;
    } finally {
      this.publish({ busy: false });
    }
  }
  private assertIdentity(identity: number): void {
    if (identity !== this.identity)
      throw new Error('The workspace token changed during this request. Its result was not applied.');
  }

  // MARK: - Startup distinguishes absent state from corruption and never replays interrupted work.
  initialize = (): Promise<void> => {
    if (!this.initialization)
      this.initialization = (async () => {
        try {
          const existing = await this.persistence.load();
          this.adopt(existing ?? (await this.persistence.commit(await this.persistence.seed(), 0)));
          if (
            this.state.snapshot?.bookings.some((request) =>
              request.isLive ? request.status === 'starting' : ['queued', 'calling'].includes(request.status),
            )
          ) {
            await this.edit((draft) =>
              draft.bookings.forEach((request) => {
                if (request.isLive && request.status === 'starting') request.status = 'unknown';
                else if (!request.isLive && ['queued', 'calling'].includes(request.status))
                  request.status = 'needsUser';
              }),
            );
          }
        } catch (error) {
          this.reportError(error);
        } finally {
          this.publish({ loading: false });
        }
      })();
    return this.initialization;
  };
  notify = (notice: string): void => this.publish({ notice, error: null });
  reportError = (error: unknown): void => this.publish({ error: message(error), notice: null });
  clearFeedback = (): void => this.publish({ notice: null, error: null });
  mutate = (change: (draft: AppSnapshot) => void): Promise<void> => this.edit(change);
  resetDemo = (): Promise<void> =>
    this.action(async () => {
      const seed = await this.persistence.seed();
      await this.queue(async () => {
        this.adopt(await this.persistence.reset(seed));
        this.mustPull = false;
        this.publish({ loading: false, serverRevision: null });
      });
      this.notify('Fictional demo restored in this browser.');
    });
  setToken = (token: string): void => {
    if (token === this.state.token) return;
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

  // MARK: - Source and visit editing retain exact user-authored questions, notes and versions.
  // Imports publish their original in the same transaction as the source, including on retry.
  saveRecord = (record: MedicalRecord, expectedVersion?: number, original?: Blob): Promise<void> =>
    this.edit(
      (draft) => {
        if (original && !record.sourceFilename) throw new Error('The original filename is missing.');
        upsertRecord(draft, record, expectedVersion);
      },
      original && record.sourceFilename ? new Map([[record.sourceFilename, original]]) : undefined,
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
  saveMemory = (recordingID: string, correctedSegmentTexts?: Record<string, string>): Promise<void> =>
    this.edit((draft) => reconcileMemory(draft, recordingID, correctedSegmentTexts));

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
      const candidates = snapshot.records.filter((record) => record.text.trim());
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

  // MARK: - A durable unique intent precedes an explicitly reviewed outbound call.
  startCall = (request: BookingRequest): Promise<void> =>
    this.action(async () => {
      validateBooking(request);
      if (!this.state.providers?.booking.configured || !this.state.providers.liveCallsEnabled)
        throw new Error('Live appointment calls are not enabled on this server.');
      if (!/^\+[1-9]\d{7,14}$/.test(request.phone))
        throw new Error('Use an international clinic phone number, such as +13125550123.');
      const identity = this.identity,
        api = this.apiFactory(this.state.token),
        patientName = this.requiredSnapshot().profile.name;
      await this.edit((draft) => {
        if (draft.bookings.some((existing) => existing.id === request.id))
          throw new Error(
            'This call request already exists. Check its status instead of starting another call.',
          );
        if (!draft.visits.some((visit) => visit.id === request.visitID))
          throw new Error('This visit no longer exists.');
        draft.bookings.push({
          ...structuredClone(request),
          isLive: true,
          status: 'starting',
          confirmedVisitID: undefined,
          providerConversationID: undefined,
          providerTranscript: undefined,
        });
      });
      try {
        this.assertIdentity(identity);
        const result = await api.startCall({
          requestID: request.id,
          clinic: request.clinic,
          phone: request.phone,
          reason: request.reason,
          earliest: request.earliest,
          latest: request.latest,
          timeZone: request.timeZone,
          preferences: request.preferences,
          patientName,
          consent: true,
        });
        this.assertIdentity(identity);
        await this.edit((draft) => {
          this.assertIdentity(identity);
          const saved = draft.bookings.find((item) => item.id === request.id);
          if (saved) {
            saved.providerConversationID = result.conversationID;
            saved.status = result.status;
          }
        });
        this.notify(
          'Call request accepted. Check its status and review the outcome; no appointment has been confirmed.',
        );
      } catch (error) {
        try {
          await this.edit((draft) => {
            const saved = draft.bookings.find((item) => item.id === request.id);
            if (saved) saved.status = 'unknown';
          });
        } catch {
          /* Chunk: If the status write fails, durable starting intent still prevents replay. */
        }
        throw error;
      }
    });
  refreshCall = (requestID: string): Promise<void> =>
    this.action(async () => {
      if (!this.requiredSnapshot().bookings.some((request) => request.id === requestID && request.isLive))
        throw new Error('Choose an existing live call request to check.');
      const identity = this.identity,
        result = await this.apiFactory(this.state.token).callStatus(requestID);
      this.assertIdentity(identity);
      await this.edit((draft) => {
        this.assertIdentity(identity);
        const request = draft.bookings.find((item) => item.id === requestID);
        if (request) {
          request.providerConversationID = result.conversationID;
          request.status = result.status;
          request.providerTranscript = result.transcript;
        }
      });
      this.notify('Call status updated. Review the outcome; no appointment has been confirmed.');
    });

  // MARK: - Discovery cannot silently advance a revision that has already become stale.
  checkServer = (): Promise<void> =>
    this.action(async () => {
      const identity = this.identity,
        api = this.apiFactory(this.state.token);
      const health = await api.health(),
        providers = await api.providers();
      let remoteRevision: number;
      try {
        remoteRevision = (await api.pull()).revision;
      } catch (error) {
        if (!(error instanceof APIError) || error.status !== 404 || error.revision === null) throw error;
        remoteRevision = error.revision;
      }
      this.assertIdentity(identity);
      const known = this.state.serverRevision;
      this.publish({ providers, connectedAI: this.state.connectedAI && providers.gemini.configured });
      if (this.mustPull || (known !== null && known !== remoteRevision)) {
        this.mustPull = true;
        this.notify(`${health}. The server has a different revision; pull and review it before pushing.`);
      } else {
        this.publish({ serverRevision: remoteRevision });
        this.notify(`${health}. Provider availability checked.`);
      }
    });
  pushToServer = (): Promise<void> =>
    this.action(async () => {
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
        this.assertIdentity(identity);
        await api.uploadAttachment(filename, type ? blob.slice(0, blob.size, type) : blob);
      }
      this.assertIdentity(identity);
      try {
        const next = await api.push(snapshot, revision);
        this.assertIdentity(identity);
        this.publish({ serverRevision: next });
        this.notify(
          localRevision === this.localRevision
            ? 'Browser snapshot and originals sent to the server.'
            : 'Captured snapshot sent. Newer browser edits remain local; push again to send them.',
        );
      } catch (error) {
        if (error instanceof APIError && error.status === 409 && identity === this.identity)
          this.mustPull = true;
        throw error;
      }
    });
  pullFromServer = (): Promise<void> =>
    this.action(async () => {
      await this.writes;
      const identity = this.identity,
        localRevision = this.localRevision,
        api = this.apiFactory(this.state.token),
        remote = await api.pull(),
        attachments = new Map<string, Blob>();
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
      });
      this.notify('Server snapshot and all originals saved in this browser.');
    });
}
