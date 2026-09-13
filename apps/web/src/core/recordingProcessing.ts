// Purpose: Process consented, saved recordings without owning a page or blocking workspace editing.
// Inputs: Durable queued recording markers, provider availability and cancellable store actions.
// Outputs: Sequential transcription, analysis and sourced memory, plus resumable progress states.
// Side effects: Provider requests and durable edits; originals survive failures and interrupted sessions.
import { APIError } from './api';
import { createMemoryRecord, hasRecordingSummary } from './mutations';
import type { AppSnapshot, VisitRecording } from './models';
import type { RevaState } from './store';
import type { GeminiRetryState } from './geminiRetry';
import { formatDate } from './dates';

export interface RecordingJob {
  id: string;
  title: string;
  stage: 'queued' | 'transcribing' | 'analyzing' | 'waiting' | 'failed' | 'complete';
  message: string;
  retryAt?: number;
}
export interface RecordingProcessingHost {
  getState(): RevaState;
  isWorkspaceActive(): boolean;
  subscribe(listener: () => void): () => void;
  mutate(change: (draft: AppSnapshot) => void): Promise<void>;
  transcribeRecording(id: string, signal?: AbortSignal, background?: boolean): Promise<void>;
  summarizeRecording(
    id: string,
    signal?: AbortSignal,
    background?: boolean,
    onRetry?: (retry: GeminiRetryState | null) => void,
  ): Promise<void>;
}
const pending = new Set(['processing-queued', 'processing-transcribing', 'processing-analyzing']);
export class RecordingProcessingAutomation {
  private jobs: RecordingJob[] = [];
  private listeners = new Set<() => void>();
  private errors = new Map<string, string>();
  private retryAfter = new Map<string, number>();
  private backoff = new Map<string, GeminiRetryState>();
  private paused = new Set<string>();
  private timer?: ReturnType<typeof setTimeout>;
  private unsubscribe?: () => void;
  private request?: { id: string; controller: AbortController; owner: string };
  private active = false;
  private owner = '';
  constructor(private host: RecordingProcessingHost) {}
  getState = () => this.jobs;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  start = () => {
    this.active = true;
    this.unsubscribe?.();
    this.unsubscribe = this.host.subscribe(this.consider);
    this.consider();
  };
  stop = () => {
    this.active = false;
    this.unsubscribe?.();
    clearTimeout(this.timer);
    this.request?.controller.abort();
  };
  private identity(state: RevaState) {
    return JSON.stringify([state.token, state.account?.user.id, state.snapshot?.profile.id]);
  }
  private waiting(recording: VisitRecording, state: RevaState): string | undefined {
    if (this.paused.has(recording.id))
      return 'Processing stopped. Your audio and completed steps are saved. Try again when ready.';
    if (typeof navigator !== 'undefined' && navigator.onLine === false)
      return 'Waiting for a connection. Your audio is saved.';
    if (!recording.segments.length && !state.providers?.transcription.configured)
      return 'Waiting for transcription service. Your audio is saved.';
    if (recording.segments.length && !hasRecordingSummary(recording) && !state.providers?.gemini.configured)
      return 'Transcript saved. Waiting for analysis service.';
  }
  wake = () => this.consider();
  private consider = () => {
    if (!this.active) return;
    const state = this.host.getState();
    const owner = this.identity(state);
    if (owner !== this.owner) {
      this.request?.controller.abort();
      this.errors.clear();
      this.retryAfter.clear();
      this.backoff.clear();
      this.paused.clear();
      this.owner = owner;
    }
    const recordings =
      state.loading || !this.host.isWorkspaceActive() ? [] : (state.snapshot?.recordings ?? []);
    if (this.request && !recordings.some((item) => item.id === this.request!.id))
      this.request.controller.abort();
    const jobs = recordings
      .filter((item) => !item.isSample && item.audioFilename && item.status.startsWith('processing-'))
      .map((item): RecordingJob => {
        if (item.status === 'processing-complete')
          return {
            id: item.id,
            title: item.title,
            stage: 'complete',
            message: 'Transcript and summary ready.',
          };
        if (item.status === 'processing-failed' || this.errors.has(item.id))
          return {
            id: item.id,
            title: item.title,
            stage: 'failed',
            message:
              this.errors.get(item.id) ??
              'Processing could not finish. Your saved audio and completed steps are kept.',
          };
        const scheduled = this.backoff.get(item.id);
        const waiting = scheduled
          ? `Analysis will retry ${formatDate(new Date(scheduled.retryAt).toISOString(), true)}. Your transcript is saved.`
          : this.waiting(item, state);
        const stage = waiting
          ? 'waiting'
          : this.request?.id === item.id
            ? item.segments.length
              ? 'analyzing'
              : 'transcribing'
            : 'queued';
        return {
          id: item.id,
          title: item.title,
          stage,
          ...(scheduled ? { retryAt: scheduled.retryAt } : {}),
          message:
            waiting ??
            (stage === 'transcribing'
              ? 'Turning the conversation into text.'
              : stage === 'analyzing'
                ? 'Preparing your appointment summary.'
                : 'Saved and queued for processing.'),
        };
      });
    if (JSON.stringify(jobs) !== JSON.stringify(this.jobs)) {
      this.jobs = jobs;
      this.listeners.forEach((listener) => listener());
    }
    if (!this.request) {
      clearTimeout(this.timer);
      const next = recordings.find(
        (item) =>
          !item.isSample &&
          item.audioFilename &&
          pending.has(item.status) &&
          !this.errors.has(item.id) &&
          !this.waiting(item, state),
      );
      if (next && !state.busy) this.timer = setTimeout(() => void this.run(next.id, owner), 0);
    }
  };
  private async mark(id: string, status: string, valid: () => boolean) {
    await this.host.mutate((draft) => {
      if (!valid()) throw new DOMException('Processing interrupted.', 'AbortError');
      const item = draft.recordings.find((recording) => recording.id === id);
      if (!item) throw new Error('This recording is no longer available.');
      item.status = status;
    });
  }
  private async run(id: string, owner: string) {
    if (
      !this.active ||
      !this.host.isWorkspaceActive() ||
      this.host.getState().busy ||
      this.request ||
      owner !== this.owner
    )
      return;
    const controller = new AbortController();
    const request = { id, owner, controller };
    this.request = request;
    const valid = () =>
      this.active &&
      this.host.isWorkspaceActive() &&
      !controller.signal.aborted &&
      owner === this.identity(this.host.getState());
    const current = () => this.host.getState().snapshot?.recordings.find((item) => item.id === id);
    this.consider();
    try {
      let recording = current();
      if (!recording || !pending.has(recording.status) || !valid()) return;
      if (!recording.segments.length) {
        await this.mark(id, 'processing-transcribing', valid);
        await this.host.transcribeRecording(id, controller.signal, true);
      }
      if (!valid()) return;
      recording = current();
      if (!recording) return;
      if (this.waiting(recording, this.host.getState())) {
        await this.mark(id, 'processing-analyzing', valid);
        return;
      }
      await this.mark(id, 'processing-analyzing', valid);
      if (!hasRecordingSummary(recording))
        await this.host.summarizeRecording(id, controller.signal, true, (retry) => {
          if (!valid()) return;
          if (retry) this.backoff.set(id, retry);
          else this.backoff.delete(id);
          this.consider();
        });
      if (!valid()) return;
      await this.host.mutate((draft) => {
        if (!valid()) throw new DOMException('Processing interrupted.', 'AbortError');
        const latest = draft.recordings.find((item) => item.id === id);
        if (!latest || !hasRecordingSummary(latest))
          throw new Error('The transcript changed before analysis finished. Retry with the current source.');
        const memory = createMemoryRecord(latest, draft, true);
        const index = draft.records.findIndex((item) => item.id === memory.id);
        if (index < 0) draft.records.push(memory);
        else draft.records[index] = memory;
        latest.status = 'processing-complete';
      });
    } catch (error) {
      if (!valid() || !current()) return;
      if (error instanceof Error && error.name === 'AbortError') {
        // Store cancellation can precede logout/identity changes; keep the durable marker resumable.
        this.paused.add(id);
        return;
      }
      this.errors.set(
        id,
        error instanceof Error ? error.message : 'Processing could not finish. Your audio is saved.',
      );
      if (error instanceof APIError && error.retryAfter)
        this.retryAfter.set(id, Date.now() + error.retryAfter * 1000);
      try {
        await this.mark(id, 'processing-failed', valid);
      } catch {
        /* A failed local commit keeps the durable queued marker for the next app launch. */
      }
    } finally {
      this.backoff.delete(id);
      if (this.request === request) this.request = undefined;
      this.consider();
    }
  }
  retry = (id: string) => {
    if (!this.active || !this.host.isWorkspaceActive() || this.request?.id === id) return;
    const owner = this.owner;
    if (Date.now() < (this.retryAfter.get(id) ?? 0)) return;
    this.errors.delete(id);
    this.paused.delete(id);
    void this.mark(
      id,
      'processing-queued',
      () => this.active && this.host.isWorkspaceActive() && owner === this.owner,
    ).catch((error) => {
      if (!this.active || owner !== this.owner) return;
      this.errors.set(
        id,
        error instanceof Error ? error.message : 'Processing could not resume. Your audio is saved.',
      );
      this.consider();
    });
  };
  dismiss = (id: string) => {
    if (
      this.host.getState().snapshot?.recordings.find((item) => item.id === id)?.status !==
      'processing-complete'
    )
      return;
    const owner = this.owner;
    void this.mark(
      id,
      'ready',
      () => this.active && this.host.isWorkspaceActive() && owner === this.owner,
    ).catch(() => {});
  };
}
