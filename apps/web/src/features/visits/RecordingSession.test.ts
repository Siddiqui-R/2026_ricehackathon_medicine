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
  live: { status: 'idle', committed: '', partial: '' },
  capture: {
    state: 'idle',
    seconds: 0,
    startedAt: null as string | null,
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
vi.mock('./useLiveTranscription', () => ({ useLiveTranscription: () => ({ transcript: mocks.live }) }));
import { useRecordingSessionDraft } from './RecordingSession';
import type { Visit } from '../../core/models';
import { RevaStore } from '../../core/store';
import { RecordingProcessingAutomation } from '../../core/recordingProcessing';
import { MemoryRepository, transport } from '../../core/__tests__/fixtures';

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
  mocks.live = { status: 'idle', committed: '', partial: '' };
  host.states = [];
  host.refs = [];
  host.effects = [];
  mocks.capture.state = 'idle';
  mocks.capture.seconds = 0;
  mocks.capture.startedAt = null;
  mocks.capture.blob = null;
  mocks.capture.start.mockImplementation(async () => {
    mocks.capture.state = 'recording';
    mocks.capture.startedAt = new Date().toISOString();
  });
  mocks.capture.reset.mockImplementation(() => {
    mocks.capture.state = 'idle';
    mocks.capture.seconds = 0;
    mocks.capture.startedAt = null;
    mocks.capture.blob = null;
  });
  mocks.save.mockResolvedValue(undefined);
  browser = Object.assign(new EventTarget(), { location: { hash: '#/summary' }, confirm: vi.fn(() => true) });
  vi.stubGlobal('window', browser);
});
afterEach(() => {
  host.effects.forEach((effect) => effect.cleanup?.());
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

// MARK: - Page entry requires consent; capture still requires an explicit start action
describe('shared recording session', () => {
  it.each(['short', 'no final live words', 'partial live words', 'unavailable', 'uploaded'])(
    'automatically processes the saved original after %s without asking for transcription or AI permission',
    async (scenario) => {
      const repository = new MemoryRepository();
      const transcribe = vi.fn(async () => ({
        text: 'Complete words recovered from the saved audio.',
        model: 'mock-standard-transcription',
        segments: [
          {
            id: 'complete',
            start: 0,
            end: 0.4,
            speaker: 'Speaker',
            text: 'Complete words recovered from the saved audio.',
          },
        ],
      }));
      const summarize = vi.fn(async () => ({
        summary: 'Summary of the complete saved conversation.',
        model: 'mock-summary',
      }));
      const store = new RevaStore(repository, () => transport({ transcribe, summarize }));
      await store.initialize();
      await store.checkServer();
      expect(store.getState().connectedAI).toBe(false);
      mocks.save.mockImplementation(store.saveRecording);
      const processor = new RecordingProcessingAutomation(store);
      processor.start();
      try {
        consent();
        render().updateDraft({ title: 'Synthetic saved conversation' });
        if (scenario === 'uploaded') {
          render().setMode('upload');
          const file = new File(['original imported audio'], 'sample.wav', { type: 'audio/wav' });
          mocks.inspect.mockResolvedValue({ blob: file, duration: 1, extension: 'wav' });
          await render().chooseAudio(file);
        } else {
          finishedAudio();
          mocks.capture.seconds = scenario === 'short' ? 0.4 : 12;
          mocks.live = {
            status: scenario === 'unavailable' ? 'unavailable' : 'stopped',
            committed: scenario === 'partial live words' ? 'Incomplete opening words.' : '',
            partial: scenario === 'no final live words' ? 'Unfinalized words' : '',
          };
        }
        const id = render().draft!.id;
        const original = render().original!;
        await render().save();
        expect(mocks.save).toHaveBeenCalledWith(
          expect.objectContaining({ id, status: 'processing-queued', segments: [] }),
          original,
        );
        expect(render().draft).toBeNull();
        expect(browser.location.hash).toBe('#/summary');
        expect(browser.confirm).not.toHaveBeenCalled();
        await vi.waitFor(() =>
          expect(processor.getState().find((job) => job.id === id)?.stage).toBe('complete'),
        );
        expect(transcribe).toHaveBeenCalledOnce();
        expect(summarize).toHaveBeenCalledOnce();
        const result = store.getState().snapshot!.recordings.find((item) => item.id === id)!;
        expect(result.segments[0].text).toBe('Complete words recovered from the saved audio.');
        expect(result.aiSummary).toBe('Summary of the complete saved conversation.');
        expect(await (await store.getAttachment(result.audioFilename!)).text()).toBe(await original.text());
        expect(
          store.getState().snapshot!.records.find((item) => item.sourceRecordingID === id)?.text,
        ).toContain('Complete words recovered');
      } finally {
        processor.stop();
      }
    },
  );
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
    expect(render().draft?.title).toBe('');
    expect(render().hasUnsaved).toBe(false);
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
    render().updateDraft({ title: 'Synthetic recording' });
    await render().start();
    mocks.capture.blob = new Blob(['partial']);
    await render().save();
    mocks.capture.state = 'paused';
    await render().save();
    expect(mocks.save).not.toHaveBeenCalled();
  });

  it('retains failed-save audio, serializes retries and clears only after durable success', async () => {
    browser.location.hash = '#/records?query=synthetic';
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
    expect(browser.location.hash).toBe('#/recording');
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
        status: 'processing-queued',
      }),
      original,
    );
    expect(render().draft).toBeNull();
    expect(mocks.capture.reset).toHaveBeenCalledOnce();
    expect(browser.location.hash).toBe('#/records?query=synthetic');
    expect(mocks.notify).toHaveBeenCalledWith(expect.stringContaining('background'));
  });

  it('saves a blank title with its Central recording day and retains the actual capture time', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-13T05:10:00Z'));
    consent();
    finishedAudio();
    mocks.capture.startedAt = '2026-09-13T04:58:00.000Z';
    render().updateDraft({ title: ' ' });
    await render().save();
    expect(mocks.save).toHaveBeenCalledWith(
      expect.objectContaining({
        title: 'Sep 12, 2026',
        titleSource: 'date',
        capturedAt: '2026-09-13T04:58:00.000Z',
        createdAt: '2026-09-13T04:58:00.000Z',
        savedAt: '2026-09-13T05:10:00Z',
      }),
      expect.any(Blob),
    );
    expect(render().draft).toBeNull();
  });
  it('preserves audio as a standalone session if its linked visit is removed during navigation', async () => {
    const visit = { id: 'removed-visit', title: 'Synthetic visit' } as Visit;
    browser.location.hash = '#/visits/removed-visit';
    mocks.snapshot.visits = [visit];
    render().requestSession(visit);
    render().confirmConsent(true);
    expect(render().draft?.title).toBe('');
    render().updateDraft({ title: 'My appointment audio' });
    finishedAudio();
    expect(render().detachedVisit).toBe(false);
    mocks.snapshot.visits = [];
    expect(render().detachedVisit).toBe(true);
    const original = render().original;
    await render().save();
    expect(mocks.save).toHaveBeenCalledWith(
      expect.objectContaining({ visitID: '', title: 'My appointment audio' }),
      original,
    );
    expect(mocks.notify).toHaveBeenCalledWith(expect.stringContaining('standalone session'));
    expect(browser.location.hash).toBe('#/summary');
  });

  it('uses the same consented save flow for uploaded originals', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-13T02:30:00Z'));
    consent();
    render().setMode('upload');
    const file = new File(['synthetic original'], 'synthetic-visit.mp3', {
      type: 'audio/mpeg',
      lastModified: Date.parse('2020-01-01T00:00:00Z'),
    });
    mocks.inspect.mockResolvedValue({ blob: file, duration: 64, extension: 'mp3' });
    await render().chooseAudio(file);
    expect(render().draft?.title).toBe('');
    expect(render().original).toBe(file);
    await render().save();
    expect(mocks.save).toHaveBeenCalledWith(
      expect.objectContaining({
        title: 'Sep 12, 2026',
        titleSource: 'date',
        capturedAt: undefined,
        savedAt: '2026-09-13T02:30:00Z',
        createdAt: '2026-09-13T02:30:00Z',
        duration: 64,
        audioFilename: expect.stringMatching(/\.mp3$/),
      }),
      file,
    );
    expect(mocks.capture.start).not.toHaveBeenCalled();
  });

  it('protects typed titles and unsaved audio from reload and sign-out before credentials are revoked', async () => {
    consent();
    render().updateDraft({ title: 'A title worth keeping' });
    expect(render().hasUnsaved).toBe(true);
    const titleOnlyLeave = new Event('beforeunload', { cancelable: true });
    browser.dispatchEvent(titleOnlyLeave);
    expect(titleOnlyLeave.defaultPrevented).toBe(true);
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
