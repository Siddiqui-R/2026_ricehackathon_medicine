// Purpose: Verify shared draft ownership and consent/save safety independently of a browser microphone.
// Inputs: A hook driver, fake recorder, deferred storage promises and synthetic browser event target.
// Outputs: Assertions for route persistence, explicit consent, retained failures and protected exits.
// Side effects: Mocks React state and browser APIs; no recording, patient data or external services.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// MARK: - The hook host stays mounted while routed consumers come and go
const host = vi.hoisted(() => ({
  states: [] as unknown[],
  refs: [] as { current: unknown }[],
  effects: [] as { deps?: unknown[]; cleanup?: () => void }[],
  stateIndex: 0,
  refIndex: 0,
  effectIndex: 0,
}));
const mocks = vi.hoisted(() => ({
  snapshot: { visits: [] as { id: string }[] },
  save: vi.fn(),
  notify: vi.fn(),
  inspect: vi.fn(),
  capture: {
    state: 'idle',
    seconds: 0,
    blob: null as Blob | null,
    error: '',
    notice: '',
    supported: true,
    start: vi.fn(),
    pause: vi.fn(),
    resume: vi.fn(),
    stop: vi.fn(),
    reset: vi.fn(),
  },
}));
vi.mock('react', async (original) => ({
  ...(await original<typeof import('react')>()),
  useState<T>(initial: T | (() => T)) {
    const index = host.stateIndex++;
    if (!(index in host.states))
      host.states[index] = typeof initial === 'function' ? (initial as () => T)() : initial;
    return [
      host.states[index],
      (value: T | ((previous: T) => T)) => {
        host.states[index] =
          typeof value === 'function' ? (value as (previous: T) => T)(host.states[index] as T) : value;
      },
    ];
  },
  useRef<T>(initial: T) {
    const index = host.refIndex++;
    if (!host.refs[index]) host.refs[index] = { current: initial };
    return host.refs[index];
  },
  useEffect(effect: () => (() => void) | void, deps?: unknown[]) {
    const index = host.effectIndex++;
    const previous = host.effects[index];
    if (
      previous &&
      deps &&
      previous.deps?.length === deps.length &&
      deps.every((value, i) => Object.is(previous.deps![i], value))
    )
      return;
    previous?.cleanup?.();
    host.effects[index] = { deps, cleanup: effect() || undefined };
  },
}));
vi.mock('../../core/RevaContext', () => ({
  useReva: () => ({ snapshot: mocks.snapshot, saveRecording: mocks.save, notify: mocks.notify }),
}));
vi.mock('./useVisitRecorder', () => ({
  useVisitRecorder: () => mocks.capture,
  audioExtension: () => 'webm',
  MAX_AUDIO_BYTES: 16 * 1024 * 1024,
}));
vi.mock('./recordingAudio', () => ({ inspectAudio: mocks.inspect }));
import { useRecordingSessionDraft } from './RecordingSession';
import type { Visit } from '../../core/models';

function render() {
  host.stateIndex = 0;
  host.refIndex = 0;
  host.effectIndex = 0;
  return useRecordingSessionDraft();
}
function consent() {
  render().requestSession();
  render().confirmConsent(true);
  return render();
}
function finishedAudio() {
  mocks.capture.state = 'stopped';
  mocks.capture.seconds = 12;
  mocks.capture.blob = new Blob(['synthetic original audio'], { type: 'audio/webm' });
}
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (failure: Error) => void;
  const promise = new Promise<T>((accept, fail) => {
    resolve = accept;
    reject = fail;
  });
  return { promise, resolve, reject };
}
let browser: EventTarget & { location: { hash: string }; confirm: ReturnType<typeof vi.fn> };
beforeEach(() => {
  vi.clearAllMocks();
  mocks.snapshot.visits = [];
  host.states = [];
  host.refs = [];
  host.effects = [];
  mocks.capture.state = 'idle';
  mocks.capture.seconds = 0;
  mocks.capture.blob = null;
  mocks.capture.start.mockImplementation(async () => {
    mocks.capture.state = 'recording';
  });
  mocks.capture.reset.mockImplementation(() => {
    mocks.capture.state = 'idle';
    mocks.capture.seconds = 0;
    mocks.capture.blob = null;
  });
  mocks.save.mockResolvedValue(undefined);
  browser = Object.assign(new EventTarget(), { location: { hash: '#/summary' }, confirm: vi.fn(() => true) });
  vi.stubGlobal('window', browser);
});
afterEach(() => {
  host.effects.forEach((effect) => effect.cleanup?.());
  vi.unstubAllGlobals();
});

// MARK: - Page entry requires consent; capture still requires an explicit start action
describe('shared recording session', () => {
  it('blocks capture, upload and save before consent and does not start on consent alone', async () => {
    await render().start();
    await render().chooseAudio(new File(['audio'], 'visit.mp3'));
    await render().save();
    expect(mocks.capture.start).not.toHaveBeenCalled();
    expect(mocks.inspect).not.toHaveBeenCalled();
    expect(mocks.save).not.toHaveBeenCalled();
    render().requestSession();
    render().confirmConsent(false);
    expect(render().draft).toBeNull();
    expect(browser.location.hash).toBe('#/summary');
    render().confirmConsent(true);
    expect(render().draft?.consented).toBe(true);
    expect(browser.location.hash).toBe('#/recording');
    expect(mocks.capture.start).not.toHaveBeenCalled();
    await render().start();
    expect(mocks.capture.start).toHaveBeenCalledOnce();
  });

  it('preserves the recording and notes while navigating away and returning', async () => {
    const id = consent().draft!.id;
    render().updateDraft({ title: 'Synthetic visit', notes: 'Questions for later' });
    await render().start();
    browser.location.hash = '#/records/synthetic-report';
    expect(render().capture.state).toBe('recording');
    expect(render().draft).toMatchObject({ id, title: 'Synthetic visit', notes: 'Questions for later' });
    render().requestSession();
    expect(browser.location.hash).toBe('#/recording');
    expect(render().draft!.id).toBe(id);
    expect(mocks.capture.start).toHaveBeenCalledOnce();
    expect(mocks.capture.reset).not.toHaveBeenCalled();
    expect(mocks.capture.pause).not.toHaveBeenCalled();
  });

  it('does not save while recording or paused', async () => {
    consent();
    await render().start();
    mocks.capture.blob = new Blob(['partial']);
    await render().save();
    mocks.capture.state = 'paused';
    await render().save();
    expect(mocks.save).not.toHaveBeenCalled();
  });

  it('retains failed-save audio, serializes retries and clears only after durable success', async () => {
    const id = consent().draft!.id;
    render().updateDraft({ title: ' Original session ', notes: ' My notes ' });
    finishedAudio();
    const original = mocks.capture.blob,
      write = deferred<void>();
    mocks.save.mockReturnValueOnce(write.promise);
    const first = render().save();
    await render().save();
    render().discard();
    expect(mocks.save).toHaveBeenCalledOnce();
    expect(render().draft!.id).toBe(id);
    expect(mocks.capture.reset).not.toHaveBeenCalled();
    write.reject(new Error('Storage unavailable'));
    await first;
    expect(render().error).toBe('Storage unavailable');
    expect(render().original).toBe(original);
    await render().save();
    expect(mocks.save).toHaveBeenLastCalledWith(
      expect.objectContaining({
        id,
        title: 'Original session',
        summary: 'My notes',
        segments: [],
        status: 'saved',
      }),
      original,
    );
    expect(render().draft).toBeNull();
    expect(mocks.capture.reset).toHaveBeenCalledOnce();
    expect(browser.location.hash).toBe(`#/recordings/${id}`);
  });

  it('keeps the draft when its title is empty instead of sending invalid metadata', async () => {
    consent();
    finishedAudio();
    render().updateDraft({ title: ' ' });
    await render().save();
    expect(render().error).toBe('Add a title for this recording.');
    expect(render().original).not.toBeNull();
    expect(mocks.save).not.toHaveBeenCalled();
  });
  it('preserves audio as a standalone session if its linked visit is removed during navigation', async () => {
    const visit = { id: 'removed-visit', title: 'Synthetic visit' } as Visit;
    mocks.snapshot.visits = [visit];
    render().requestSession(visit);
    render().confirmConsent(true);
    finishedAudio();
    expect(render().detachedVisit).toBe(false);
    mocks.snapshot.visits = [];
    expect(render().detachedVisit).toBe(true);
    const original = render().original;
    await render().save();
    expect(mocks.save).toHaveBeenCalledWith(
      expect.objectContaining({ visitID: '', title: 'Synthetic visit · recording' }),
      original,
    );
    expect(mocks.notify).toHaveBeenCalledWith(expect.stringContaining('standalone session'));
  });

  it('uses the same consented save flow for uploaded originals', async () => {
    consent();
    render().setMode('upload');
    const file = new File(['synthetic original'], 'synthetic-visit.mp3', { type: 'audio/mpeg' });
    mocks.inspect.mockResolvedValue({ blob: file, duration: 64, extension: 'mp3' });
    await render().chooseAudio(file);
    expect(render().draft?.title).toBe('synthetic-visit');
    expect(render().original).toBe(file);
    await render().save();
    expect(mocks.save).toHaveBeenCalledWith(
      expect.objectContaining({ duration: 64, audioFilename: expect.stringMatching(/\.mp3$/) }),
      file,
    );
    expect(mocks.capture.start).not.toHaveBeenCalled();
  });

  it('protects unsaved audio from reload and sign-out before credentials are revoked', async () => {
    consent();
    await render().start();
    render();
    const leave = new Event('beforeunload', { cancelable: true });
    browser.dispatchEvent(leave);
    expect(leave.defaultPrevented).toBe(true);
    browser.confirm.mockReturnValue(false);
    expect(render().allowWorkspaceExit()).toBe(false);
    expect(render().capture.state).toBe('recording');
    browser.confirm.mockReturnValue(true);
    expect(render().allowWorkspaceExit()).toBe(true);
    expect(mocks.capture.reset).toHaveBeenCalledOnce();
    render();
    const cleanLeave = new Event('beforeunload', { cancelable: true });
    browser.dispatchEvent(cleanLeave);
    expect(cleanLeave.defaultPrevented).toBe(false);
  });
});
