// Purpose: Verify recorder resource ownership with an isolated hook driver and mocked browser APIs.
// Inputs: Deferred microphone promises, fake media events, visibility changes, and explicit cleanup.
// Outputs: Vitest assertions for cancellation, pause/resume, original bytes, and released tracks/timers.
// Side effects: Temporarily mocks React hooks and browser globals; no DOM renderer or microphone is opened.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// MARK: - Minimal hook driver preserves state and refs while exposing effect cleanup
// This tests browser resource lifecycle only; full React/DOM integration belongs to browser QA.
const driver = vi.hoisted(() => ({
  states: [] as unknown[],
  refs: [] as { current: unknown }[],
  effects: [] as (() => void)[],
  stateIndex: 0,
  refIndex: 0,
  mounted: false,
}));
vi.mock('react', () => ({
  useState<T>(initial: T | (() => T)) {
    const index = driver.stateIndex++;
    if (!(index in driver.states))
      driver.states[index] = typeof initial === 'function' ? (initial as () => T)() : initial;
    return [
      driver.states[index],
      (next: T | ((previous: T) => T)) => {
        driver.states[index] =
          typeof next === 'function' ? (next as (previous: T) => T)(driver.states[index] as T) : next;
      },
    ];
  },
  useRef<T>(initial: T) {
    const index = driver.refIndex++;
    if (!driver.refs[index]) driver.refs[index] = { current: initial };
    return driver.refs[index];
  },
  useEffect(effect: () => (() => void) | void) {
    if (!driver.mounted) {
      const cleanup = effect();
      if (cleanup) driver.effects.push(cleanup);
    }
  },
}));
import { useVisitRecorder, type CaptureObserver } from './useVisitRecorder';

function render(observer?: CaptureObserver) {
  driver.stateIndex = 0;
  driver.refIndex = 0;
  const result = useVisitRecorder(observer);
  driver.mounted = true;
  return result;
}
function unmount() {
  driver.effects.splice(0).forEach((cleanup) => cleanup());
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((accept, fail) => {
    resolve = accept;
    reject = fail;
  });
  return { promise, resolve, reject };
}

// MARK: - Controllable browser resources without audio hardware
class FakeDocument extends EventTarget {
  hidden = false;
}
class FakeRecorder {
  static instances: FakeRecorder[] = [];
  static isTypeSupported = (type: string) => type === 'audio/mp4';
  state: RecordingState = 'inactive';
  mimeType: string;
  ondataavailable: ((event: { data: Blob }) => void) | null = null;
  onstop: (() => void) | null = null;
  onerror: (() => void) | null = null;
  constructor(_source: MediaStream, options: MediaRecorderOptions) {
    this.mimeType = options.mimeType!;
    FakeRecorder.instances.push(this);
  }
  start = vi.fn(() => {
    this.state = 'recording';
  });
  pause = vi.fn(() => {
    this.state = 'paused';
  });
  resume = vi.fn(() => {
    this.state = 'recording';
  });
  stop = vi.fn(() => {
    this.state = 'inactive';
    this.onstop?.();
  });
  emit(bytes: number[]) {
    this.ondataavailable?.({ data: new Blob([new Uint8Array(bytes)], { type: this.mimeType }) });
  }
}
function microphone() {
  const track = { stop: vi.fn(), onended: null as (() => void) | null };
  const stream = { getTracks: () => [track], getAudioTracks: () => [track] } as unknown as MediaStream;
  return { stream, track };
}
let documentMock: FakeDocument;
let requestMicrophone: ReturnType<typeof vi.fn>;
let elapsed: number;
beforeEach(() => {
  driver.states = [];
  driver.refs = [];
  driver.effects = [];
  driver.stateIndex = 0;
  driver.refIndex = 0;
  driver.mounted = false;
  FakeRecorder.instances = [];
  documentMock = new FakeDocument();
  requestMicrophone = vi.fn();
  elapsed = 0;
  vi.useFakeTimers();
  vi.spyOn(performance, 'now').mockImplementation(() => elapsed);
  vi.stubGlobal('MediaRecorder', FakeRecorder);
  vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: requestMicrophone } });
  vi.stubGlobal('document', documentMock);
  vi.stubGlobal('window', { isSecureContext: true, setInterval, clearInterval });
});
afterEach(() => {
  unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

// MARK: - Cancellation and cleanup always release microphone ownership
describe('visit recorder lifecycle', () => {
  it('shares only consented active audio with live captions and pauses captions when hidden', async () => {
    const source = microphone();
    requestMicrophone.mockResolvedValue(source.stream);
    const observer = {
      start: vi.fn(),
      pause: vi.fn(),
      resume: vi.fn(),
      stop: vi.fn(),
      reset: vi.fn(),
      dispose: vi.fn(),
    };
    const capture = render(observer);
    expect(observer.start).not.toHaveBeenCalled();
    await capture.start();
    expect(observer.start).toHaveBeenCalledExactlyOnceWith(source.stream);
    documentMock.hidden = true;
    documentMock.dispatchEvent(new Event('visibilitychange'));
    expect(observer.pause).toHaveBeenCalledOnce();
    capture.resume();
    expect(observer.resume).not.toHaveBeenCalled();
    documentMock.hidden = false;
    capture.resume();
    expect(observer.resume).toHaveBeenCalledExactlyOnceWith(source.stream);
    FakeRecorder.instances[0].emit([1, 2, 3]);
    capture.stop();
    expect(observer.stop).toHaveBeenCalled();
    capture.reset();
    expect(observer.reset).toHaveBeenCalledOnce();
    unmount();
    expect(observer.dispose).toHaveBeenCalledOnce();
    expect(requestMicrophone).toHaveBeenCalledOnce();
  });
  it('does not request microphone access merely by mounting', () => {
    const capture = render();
    expect(capture.supported).toBe(true);
    expect(capture.state).toBe('idle');
    expect(requestMicrophone).not.toHaveBeenCalled();
  });

  it('stops a stream returned after the dialog was closed while permission was pending', async () => {
    const request = deferred<MediaStream>();
    requestMicrophone.mockReturnValue(request.promise);
    const pending = render().start();
    expect(render().state).toBe('requesting');
    unmount();
    const source = microphone();
    request.resolve(source.stream);
    await pending;
    expect(source.track.stop).toHaveBeenCalledOnce();
    expect(FakeRecorder.instances).toHaveLength(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('ignores an older permission rejection after a newer request has started recording', async () => {
    const older = deferred<MediaStream>(),
      newer = deferred<MediaStream>();
    requestMicrophone.mockReturnValueOnce(older.promise).mockReturnValueOnce(newer.promise);
    const first = render().start();
    const second = render().start();
    const source = microphone();
    newer.resolve(source.stream);
    await second;
    expect(render().state).toBe('recording');
    older.reject(new DOMException('Old request denied', 'NotAllowedError'));
    await first;
    expect(source.track.stop).not.toHaveBeenCalled();
    expect(FakeRecorder.instances[0].state).toBe('recording');
    expect(render().state).toBe('recording');
    expect(render().error).toBe('');
  });

  it('releases active tracks and removes timers/listeners on unmount', async () => {
    const source = microphone();
    requestMicrophone.mockResolvedValue(source.stream);
    await render().start();
    const media = FakeRecorder.instances[0];
    expect(media.state).toBe('recording');
    unmount();
    expect(media.stop).toHaveBeenCalledOnce();
    expect(source.track.stop).toHaveBeenCalledOnce();
    expect(media.ondataavailable).toBeNull();
    expect(media.onstop).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
    documentMock.hidden = true;
    documentMock.dispatchEvent(new Event('visibilitychange'));
    expect(media.pause).not.toHaveBeenCalled();
  });

  // MARK: - Hidden-page pause excludes paused time and requires explicit visible resume
  it('pauses on hide, refuses hidden resume, and preserves only active elapsed time', async () => {
    const source = microphone();
    requestMicrophone.mockResolvedValue(source.stream);
    await render().start();
    const media = FakeRecorder.instances[0];
    elapsed = 1250;
    documentMock.hidden = true;
    documentMock.dispatchEvent(new Event('visibilitychange'));
    expect(media.pause).toHaveBeenCalledOnce();
    expect(render().state).toBe('paused');
    expect(render().seconds).toBe(1.25);
    expect(render().notice).toContain('page was hidden');
    elapsed = 11250;
    render().resume();
    expect(media.resume).not.toHaveBeenCalled();
    documentMock.hidden = false;
    documentMock.dispatchEvent(new Event('visibilitychange'));
    expect(media.resume).not.toHaveBeenCalled();
    render().resume();
    expect(media.resume).toHaveBeenCalledOnce();
    elapsed = 13750;
    media.emit([1, 2, 3]);
    render().stop();
    expect(render().seconds).toBe(3.75);
    expect(render().state).toBe('stopped');
    expect(source.track.stop).toHaveBeenCalledOnce();
  });

  it('keeps original captured bytes without creating transcript data', async () => {
    const source = microphone();
    requestMicrophone.mockResolvedValue(source.stream);
    await render().start();
    const media = FakeRecorder.instances[0];
    media.emit([0, 255, 128]);
    media.emit([13, 10, 42]);
    elapsed = 2000;
    render().stop();
    const result = render();
    expect(result.blob?.type).toBe('audio/mp4');
    expect([...new Uint8Array(await result.blob!.arrayBuffer())]).toEqual([0, 255, 128, 13, 10, 42]);
    expect(result).not.toHaveProperty('segments');
    expect(result).not.toHaveProperty('transcript');
  });

  it('surfaces denied permission and does not create a recorder', async () => {
    requestMicrophone.mockRejectedValue(new DOMException('Denied in test', 'NotAllowedError'));
    await render().start();
    expect(render().state).toBe('idle');
    expect(render().error).toContain('Microphone access was not allowed');
    expect(FakeRecorder.instances).toHaveLength(0);
  });

  it('keeps recording when a different workspace hash is opened', async () => {
    const source = microphone();
    requestMicrophone.mockResolvedValue(source.stream);
    await render().start();
    vi.stubGlobal('location', { hash: '#/records/synthetic-report' });
    const result = render();
    expect(result.state).toBe('recording');
    expect(FakeRecorder.instances).toHaveLength(1);
    expect(source.track.stop).not.toHaveBeenCalled();
    expect(FakeRecorder.instances[0].pause).not.toHaveBeenCalled();
  });

  it('releases the microphone and original bytes when a draft is discarded', async () => {
    vi.setSystemTime(new Date('2026-09-13T04:58:00Z'));
    const source = microphone();
    requestMicrophone.mockResolvedValue(source.stream);
    await render().start();
    expect(render().startedAt).toBe('2026-09-13T04:58:00.000Z');
    const media = FakeRecorder.instances[0];
    media.emit([1, 2, 3]);
    elapsed = 2500;
    render().stop();
    expect(render().blob?.size).toBe(3);
    render().reset();
    expect(render().state).toBe('idle');
    expect(render().seconds).toBe(0);
    expect(render().blob).toBeNull();
    expect(render().startedAt).toBeNull();
    expect(source.track.stop).toHaveBeenCalledOnce();
  });

  it('cancels a pending permission request when its shared draft is discarded', async () => {
    const request = deferred<MediaStream>();
    requestMicrophone.mockReturnValue(request.promise);
    const pending = render().start();
    render().reset();
    const source = microphone();
    request.resolve(source.stream);
    await pending;
    expect(render().state).toBe('idle');
    expect(source.track.stop).toHaveBeenCalledOnce();
    expect(FakeRecorder.instances).toHaveLength(0);
  });
});
