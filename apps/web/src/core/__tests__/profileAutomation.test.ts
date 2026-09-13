// Purpose: Verify automatic medical history follows report edits safely and without repeat requests.
// Inputs: Synthetic observable workspaces and deferred provider responses.
// Outputs: Regression assertions for startup, changes, cancellation, retries and manual edit preservation.
// Side effects: Fake timers and in-memory mutations only; no real provider requests.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MedicalProfileAutomation, type ProfileHost } from '../profileAutomation';
import { RevaStore } from '../store';
import { APIError } from '../api';
import type { AIProfileResult, AppSnapshot } from '../models';
import { emptyProfileFacts, profileSources, type ProfileSource } from '../medicalProfileAI';
import { capabilities, deferred, seed, testUser } from './fixtures';

// MARK: - The host publishes durable edits in the same order as the real workspace store.
class Host implements ProfileHost {
  state = {
    ...new RevaStore().getState(),
    snapshot: seed(),
    loading: false,
    mode: 'account' as const,
    account: { user: testUser, expiresAt: null },
    providers: capabilities,
  };
  listeners = new Set<() => void>();
  commits = 0;
  getState = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  reportError = vi.fn();
  mutate = async (change: (draft: AppSnapshot) => void) => {
    const draft = structuredClone(this.state.snapshot);
    change(draft);
    this.state = { ...this.state, snapshot: draft };
    this.commits += 1;
    this.emit();
  };
  emit = () => this.listeners.forEach((listener) => listener());
}
const response = (host: Host): AIProfileResult => ({
  ...emptyProfileFacts(),
  model: 'mock-gemini',
  allergies: [{ text: 'Allergy from report', recordIDs: [host.state.snapshot.records[0].id] }],
});
const controllers: MedicalProfileAutomation[] = [];
const setup = (extract: ConstructorParameters<typeof MedicalProfileAutomation>[1], host = new Host()) => {
  vi.useFakeTimers();
  const controller = new MedicalProfileAutomation(host, extract, 10);
  controllers.push(controller);
  controller.start();
  return { controller, host };
};
const tick = () => vi.advanceTimersByTimeAsync(15);
afterEach(() => {
  controllers.splice(0).forEach((controller) => controller.stop());
  vi.useRealTimers();
});

// MARK: - Source fingerprints prevent stale application and unneeded provider work.
describe('automatic medical profile', () => {
  it('builds from existing reports, then reruns for additions and edits but not notices', async () => {
    const host = new Host();
    const extract = vi.fn(async (_token: string, _records: ProfileSource[]) => response(host));
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(extract).toHaveBeenCalledTimes(1);
    expect(extract.mock.calls[0]?.[1]).toEqual(profileSources(host.state.snapshot));
    expect(host.state.snapshot.profile.allergies).toContain('Allergy from report');
    host.emit();
    await tick();
    expect(extract).toHaveBeenCalledTimes(1);
    await host.mutate((draft) => {
      draft.records.push({ ...draft.records[0], id: 'added-report' });
    });
    await tick();
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(2));
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    await host.mutate((draft) => {
      draft.records[0].text += ' Updated report text';
    });
    await tick();
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(3));
  });
  it('discards stale results and preserves manual edits while a new update is pending', async () => {
    const host = new Host(),
      first = deferred<AIProfileResult>(),
      second = deferred<AIProfileResult>();
    const extract = vi.fn().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(1));
    await host.mutate((draft) => {
      draft.records[0].text += ' Changed';
    });
    await tick();
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(2));
    await host.mutate((draft) => {
      draft.profile.medications.push('Manual medication');
    });
    first.resolve({
      ...response(host),
      allergies: [{ text: 'Stale allergy', recordIDs: [host.state.snapshot.records[0].id] }],
    });
    second.resolve(response(host));
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(host.state.snapshot.profile.allergies).not.toContain('Stale allergy');
    expect(host.state.snapshot.profile.medications).toContain('Manual medication');
  });
  it('clears generated details when all reports are deleted without another AI request', async () => {
    const host = new Host(),
      extract = vi.fn(async () => response(host));
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    const manual = seed().profile.allergies;
    await host.mutate((draft) => {
      draft.records = [];
    });
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(host.state.snapshot.profile.allergies).toEqual(manual);
    expect(extract).toHaveBeenCalledTimes(1);
  });
  it('cancels on unmount and never applies the returning result', async () => {
    const host = new Host(),
      pending = deferred<AIProfileResult>(),
      extract = vi.fn(() => pending.promise);
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(1));
    controller.stop();
    pending.resolve(response(host));
    await tick();
    expect(host.commits).toBe(0);
  });
  it('refreshes stale profile metadata from another device even when reports did not change', async () => {
    const host = new Host(),
      extract = vi.fn(async () => response(host));
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    await host.mutate((draft) => {
      draft.profile.aiMedicalHistory!.sourceSignature = '0'.repeat(64);
    });
    await tick();
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(2));
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(host.state.snapshot.profile.aiMedicalHistory?.sourceSignature).not.toBe('0'.repeat(64));
  });
  it('retries a transient network failure without dropping saved medical details', async () => {
    const host = new Host(),
      extract = vi
        .fn()
        .mockRejectedValueOnce(new TypeError('Offline'))
        .mockImplementation(async () => response(host));
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    expect(host.commits).toBe(0);
    await vi.advanceTimersByTimeAsync(15_000);
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(extract).toHaveBeenCalledTimes(2);
  });
  it.each([422, 424])('does not replay a permanent HTTP %s failure on focus or timers', async (status) => {
    const extract = vi.fn().mockRejectedValue(new APIError(status));
    const { controller, host } = setup(extract);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    for (let wake = 0; wake < 5; wake += 1) {
      controller.retry();
      host.emit();
      await vi.advanceTimersByTimeAsync(60_000);
    }
    expect(extract).toHaveBeenCalledTimes(1);
    expect(host.commits).toBe(0);
  });
  it('honors Retry-After even when the user repeatedly returns to the app', async () => {
    const extract = vi.fn().mockRejectedValue(new APIError(429, null, null, 120));
    const { controller } = setup(extract);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    for (let wake = 0; wake < 3; wake += 1) {
      controller.retry();
      await vi.advanceTimersByTimeAsync(30_000);
    }
    expect(extract).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(30_000);
    await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(2));
  });
  it('caps transient retries without resetting the budget on focus', async () => {
    const extract = vi.fn().mockRejectedValue(new APIError(503));
    const { controller } = setup(extract);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    for (const [index, delay] of [15_000, 30_000, 60_000].entries()) {
      await vi.advanceTimersByTimeAsync(delay);
      await vi.waitFor(() => expect(extract).toHaveBeenCalledTimes(index + 2));
      await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    }
    for (let wake = 0; wake < 3; wake += 1) {
      controller.retry();
      await vi.advanceTimersByTimeAsync(300_000);
    }
    expect(extract).toHaveBeenCalledTimes(4);
  });
  it('allows an explicit retry after the provider configuration is repaired', async () => {
    const host = new Host();
    const extract = vi
      .fn()
      .mockRejectedValueOnce(new APIError(424))
      .mockImplementation(async () => response(host));
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    controller.retryManually();
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(extract).toHaveBeenCalledTimes(2);
  });
  it('reconsiders a failed request when the configured model changes', async () => {
    const host = new Host();
    const extract = vi
      .fn()
      .mockRejectedValueOnce(new APIError(424))
      .mockImplementation(async () => response(host));
    const { controller } = setup(extract, host);
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('error'));
    host.state = {
      ...host.state,
      providers: {
        ...host.state.providers,
        gemini: { ...host.state.providers.gemini, model: 'changed-model' },
      },
    };
    host.emit();
    await tick();
    await vi.waitFor(() => expect(controller.getState().status).toBe('current'));
    expect(extract).toHaveBeenCalledTimes(2);
  });
});
