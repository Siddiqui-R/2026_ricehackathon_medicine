// Purpose: Refresh medical history automatically when account reports change.
// Inputs: Observable workspace state, a durable mutation boundary and an injectable profile provider.
// Outputs: Debounced, source-checked profile updates and a quiet status for the profile page.
// Side effects: Authenticated AI requests, retry timers and profile commits that use ordinary account sync.
import { RevaAPI, APIError } from './api';
import { nowISO, sha256 } from './domain';
import {
  applyMedicalProfile,
  emptyProfileFacts,
  profileSourceKey,
  profileSources,
  validateProfileResult,
  validateProfileSources,
  type ProfileSource,
} from './medicalProfileAI';
import type { AIProfileResult, AppSnapshot } from './models';
import type { RevaState } from './store';

// MARK: - An injectable boundary keeps background behavior independently testable.
export interface ProfileHost {
  getState(): RevaState;
  subscribe(listener: () => void): () => void;
  mutate(change: (draft: AppSnapshot) => void): Promise<void>;
  reportError(error: unknown): void;
}
export interface ProfileUpdateState {
  status: 'waiting' | 'updating' | 'current' | 'unavailable' | 'error';
  message: string;
}
type Extract = (token: string, records: ProfileSource[], signal: AbortSignal) => Promise<AIProfileResult>;
export class MedicalProfileAutomation {
  private state: ProfileUpdateState = {
    status: 'waiting',
    message: 'Medical details update automatically from your reports.',
  };
  private listeners = new Set<() => void>();
  private unsubscribe?: () => void;
  private timer?: ReturnType<typeof setTimeout>;
  private request?: AbortController;
  private observed = '';
  private active = false;
  private failures = 0;
  private retryAt = 0;
  private transientFailure = false;
  constructor(
    private host: ProfileHost,
    private extract: Extract = (token, records, signal) => new RevaAPI(token).medicalProfile(records, signal),
    private delay = 1800,
  ) {}
  getState = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private publish(status: ProfileUpdateState['status'], message: string) {
    this.state = { status, message };
    this.listeners.forEach((listener) => listener());
  }
  start = () => {
    this.active = true;
    this.unsubscribe?.();
    this.unsubscribe = this.host.subscribe(this.consider);
    this.observed = '';
    this.consider();
  };
  stop = () => {
    this.active = false;
    this.unsubscribe?.();
    clearTimeout(this.timer);
    this.request?.abort();
  };
  retry = () => {
    if (
      !this.active ||
      this.request ||
      this.state.status !== 'error' ||
      !this.transientFailure ||
      this.failures >= 3 ||
      Date.now() < this.retryAt
    )
      return;
    clearTimeout(this.timer);
    void this.run(this.observed);
  };
  retryManually = () => {
    if (!this.active || this.request) return;
    this.failures = 0;
    this.observed = '';
    this.consider();
  };
  private eligible(state: RevaState) {
    return (
      !state.loading &&
      !!state.snapshot &&
      !!state.providers?.gemini.configured &&
      (state.mode === 'account' || state.connectedAI)
    );
  }

  // MARK: - Report edits cancel stale requests; notices and unrelated edits never retrigger AI.
  private consider = () => {
    if (!this.active) return;
    const state = this.host.getState();
    const eligible = this.eligible(state);
    const observed = JSON.stringify([
      state.token,
      state.account?.user.id,
      eligible,
      state.providers?.gemini.model,
      state.snapshot?.profile.id,
      state.snapshot?.profile.aiMedicalHistory?.sourceSignature,
      state.snapshot ? profileSourceKey(state.snapshot) : '',
    ]);
    if (observed === this.observed) return;
    this.observed = observed;
    this.request?.abort();
    clearTimeout(this.timer);
    this.failures = 0;
    this.retryAt = 0;
    this.transientFailure = false;
    if (!eligible) {
      this.publish(
        'unavailable',
        state.mode === 'demo'
          ? 'Demo profile. Connect and enable AI to update it from reports.'
          : 'Automatic profile updates will resume when the AI service is available.',
      );
      return;
    }
    this.publish('waiting', 'Report changes saved. Updating your medical profile shortly…');
    this.timer = setTimeout(() => void this.run(observed), this.delay);
  };
  private async run(observed: string) {
    if (!this.active || observed !== this.observed) return;
    const state = this.host.getState(),
      snapshot = state.snapshot!;
    const records = profileSources(snapshot),
      sourceKey = profileSourceKey(snapshot);
    const controller = new AbortController();
    this.request = controller;
    const stillCurrent = () => this.active && !controller.signal.aborted && observed === this.observed;
    try {
      validateProfileSources(records);
      const signature = await sha256(sourceKey);
      if (!stillCurrent()) return;
      if (
        snapshot.profile.aiMedicalHistory?.sourceSignature === signature ||
        (!records.length && !snapshot.profile.aiMedicalHistory)
      ) {
        this.publish(
          'current',
          records.length
            ? 'Medical profile is up to date with your reports.'
            : 'Add a report to build your medical profile automatically.',
        );
        return;
      }
      this.publish('updating', 'Updating your medical profile from your reports…');
      const result = records.length
        ? validateProfileResult(await this.extract(state.token, records, controller.signal), records)
        : { ...emptyProfileFacts(), model: 'No source reports' };
      if (!stillCurrent()) return;
      await this.host.mutate((draft) => {
        if (
          !stillCurrent() ||
          draft.profile.id !== snapshot.profile.id ||
          profileSourceKey(draft) !== sourceKey
        )
          throw new Error('Reports changed during the profile update. A fresh update will follow.');
        // Read the latest profile here so a manual edit made during the request survives.
        draft.profile = applyMedicalProfile(draft.profile, result, signature, nowISO());
      });
      if (stillCurrent()) this.publish('current', 'Medical profile is up to date with your reports.');
      this.failures = 0;
    } catch (error) {
      if (!stillCurrent()) return;
      if (error instanceof APIError && error.status === 401) {
        this.host.reportError(error);
        return;
      }
      this.publish(
        'error',
        error instanceof Error
          ? error.message
          : 'The profile update could not finish. Your saved details are unchanged.',
      );
      // Invalid input/output waits for a source change; transient service failures retry with backoff.
      this.transientFailure =
        error instanceof TypeError ||
        (error instanceof APIError && [408, 429, 500, 502, 503, 504].includes(error.status)) ||
        (error instanceof Error && /timed out/.test(error.message));
      if (this.failures < 3 && this.transientFailure) {
        this.failures += 1;
        const retry = Math.max(
          Math.min(300_000, 15_000 * 2 ** Math.min(this.failures - 1, 5)),
          error instanceof APIError ? (error.retryAfter ?? 0) * 1000 : 0,
        );
        this.retryAt = Date.now() + retry;
        this.timer = setTimeout(() => void this.run(observed), retry);
      }
    } finally {
      if (this.request === controller) this.request = undefined;
    }
  }
}
