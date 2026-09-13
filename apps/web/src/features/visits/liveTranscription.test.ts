// Synthetic streams and sockets verify live preview lifetime without a microphone or paid requests.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { emptyLiveTranscript, LiveTranscription, type LiveTranscript } from './liveTranscription';

class Socket {
  readyState = 1;
  bufferedAmount = 0;
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  send = vi.fn();
  close = vi.fn(() => {
    this.readyState = 3;
  });
  emit(value: unknown) {
    this.onmessage?.({ data: JSON.stringify(value) });
  }
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((accept) => {
    resolve = accept;
  });
  return { promise, resolve };
}
function fixture(sampleRate = 16000) {
  const sockets: Socket[] = [];
  const frames: ((pcm: ArrayBuffer) => void)[] = [];
  const releases: ReturnType<typeof vi.fn>[] = [];
  let value: LiveTranscript = { ...emptyLiveTranscript };
  const openSocket = vi.fn((_url: string) => {
    const socket = new Socket();
    sockets.push(socket);
    return socket as unknown as WebSocket;
  });
  const audio = vi.fn(async (_stream: MediaStream, receive: (pcm: ArrayBuffer) => void) => {
    frames.push(receive);
    const close = vi.fn();
    releases.push(close);
    return { close, sampleRate };
  });
  const client = new LiveTranscription(
    (next) => {
      value = next;
    },
    { audio, socket: openSocket },
  );
  const track = { stop: vi.fn() };
  const stream = { getTracks: () => [track] } as unknown as MediaStream;
  const token = vi.fn(async (_signal: AbortSignal) => 'synthetic-single-use-token');
  return { client, stream, token, sockets, frames, releases, openSocket, audio, track, state: () => value };
}
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('live transcription session', () => {
  it('opens only on start, buffers until the provider is ready and replaces interim text', async () => {
    const f = fixture();
    expect(f.token).not.toHaveBeenCalled();
    await f.client.start(f.stream, f.token);
    expect(f.audio.mock.calls[0][0]).toBe(f.stream);
    const url = new URL(f.openSocket.mock.calls[0][0]);
    expect(url.origin).toBe('wss://api.elevenlabs.io');
    expect(url.searchParams.get('token')).toBe('synthetic-single-use-token');
    expect(url.searchParams.get('audio_format')).toBe('pcm_16000');
    expect(url.searchParams.get('model_id')).toBe('scribe_v2_realtime');
    expect(url.searchParams.get('commit_strategy')).toBe('vad');
    const socket = f.sockets[0];
    f.frames[0](new Uint8Array([0, 128, 255, 127]).buffer);
    expect(socket.send).not.toHaveBeenCalled();
    socket.emit({ message_type: 'session_started' });
    expect(JSON.parse(socket.send.mock.calls[0][0])).toEqual({
      message_type: 'input_audio_chunk',
      audio_base_64: 'AID/fw==',
      sample_rate: 16000,
      commit: false,
    });
    socket.emit({ message_type: 'partial_transcript', text: 'A fict' });
    socket.emit({ message_type: 'partial_transcript', text: 'A fictional visit.' });
    expect(f.state().partial).toBe('A fictional visit.');
    expect(f.state().committed).toBe('');
    socket.emit({ message_type: 'committed_transcript', text: 'A fictional visit.' });
    expect(f.state()).toEqual({ status: 'listening', committed: 'A fictional visit.', partial: '' });
    // Delayed timestamp events must not duplicate the already committed preview.
    socket.emit({
      message_type: 'committed_transcript_with_timestamps',
      text: 'A fictional visit.',
      words: [],
    });
    expect(f.state().committed).toBe('A fictional visit.');
    f.client.dispose();
    expect(f.track.stop).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('stops sending immediately on pause, receives the final phrase, and uses a fresh token on resume', async () => {
    const f = fixture();
    await f.client.start(f.stream, f.token);
    const first = f.sockets[0];
    first.emit({ message_type: 'session_started' });
    f.client.stop('paused');
    expect(f.state().status).toBe('paused');
    expect(JSON.parse(first.send.mock.calls.at(-1)![0]).commit).toBe(true);
    const calls = first.send.mock.calls.length;
    f.frames[0](new ArrayBuffer(3200));
    expect(first.send).toHaveBeenCalledTimes(calls);
    first.emit({ message_type: 'committed_transcript', text: 'Before the pause.' });
    expect(first.close).not.toHaveBeenCalled();
    first.emit({ message_type: 'committed_transcript', text: 'The final phrase.' });
    await vi.advanceTimersByTimeAsync(60_000);
    expect(first.close).toHaveBeenCalledOnce();
    expect(f.token).toHaveBeenCalledOnce();
    await f.client.start(f.stream, f.token);
    expect(f.token).toHaveBeenCalledTimes(2);
    expect(f.state().committed).toBe('Before the pause.\nThe final phrase.');
    f.sockets[1].emit({ message_type: 'session_started' });
    f.client.stop();
    await vi.advanceTimersByTimeAsync(3000);
    expect(f.sockets[1].close).toHaveBeenCalledOnce();
    expect(f.state().status).toBe('stopped');
    expect(f.track.stop).not.toHaveBeenCalled();
  });

  it('cancels pending credentials on discard and ignores responses from an older session', async () => {
    const f = fixture();
    const pending = deferred<string>();
    const load = vi.fn((_signal: AbortSignal) => pending.promise);
    const starting = f.client.start(f.stream, load);
    await Promise.resolve();
    f.client.reset();
    expect(load.mock.calls[0][0].aborted).toBe(true);
    pending.resolve('late-token');
    await starting;
    expect(f.openSocket).not.toHaveBeenCalled();
    expect(f.state()).toEqual(emptyLiveTranscript);
    await f.client.start(f.stream, f.token);
    const stale = f.sockets[0].onmessage!;
    f.client.reset();
    stale({ data: JSON.stringify({ message_type: 'partial_transcript', text: 'Discarded.' }) });
    expect(f.state()).toEqual(emptyLiveTranscript);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('closes late audio setup after unmount without requesting a token', async () => {
    const pending = deferred<{ close(): void }>();
    const close = vi.fn();
    const token = vi.fn();
    const changed = vi.fn();
    const client = new LiveTranscription(changed, { audio: () => pending.promise, socket: vi.fn() });
    const starting = client.start({} as MediaStream, token);
    client.dispose();
    pending.resolve({ close });
    await starting;
    expect(close).toHaveBeenCalledOnce();
    expect(token).not.toHaveBeenCalled();
    expect(changed).toHaveBeenCalledOnce();
  });

  it('keeps provider failures separate from audio recording and never exposes provider details or retries', async () => {
    const f = fixture();
    await f.client.start(f.stream, f.token);
    f.sockets[0].emit({ message_type: 'quota_exceeded', error: 'secret provider details' });
    expect(f.state()).toEqual({ ...emptyLiveTranscript, status: 'unavailable' });
    expect(f.track.stop).not.toHaveBeenCalled();
    expect(f.releases[0]).toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(f.token).toHaveBeenCalledOnce();
  });

  it('bounds startup buffering, connection time and websocket backpressure', async () => {
    const f = fixture();
    await f.client.start(f.stream, f.token);
    f.frames[0](new ArrayBuffer(256_002));
    expect(f.state().status).toBe('unavailable');
    await f.client.start(f.stream, f.token);
    await vi.advanceTimersByTimeAsync(15_000);
    expect(f.sockets[1].close).toHaveBeenCalledOnce();
    await f.client.start(f.stream, f.token);
    f.sockets[2].emit({ message_type: 'session_started' });
    f.sockets[2].bufferedAmount = 100_000;
    f.frames[2](new ArrayBuffer(3200));
    expect(f.state().status).toBe('listening');
    f.frames[2](new ArrayBuffer(256_000));
    expect(f.state().status).toBe('unavailable');
    expect(f.sockets[2].close).toHaveBeenCalledOnce();
  });

  it('uses supported native device rates and keeps the PCM format and payload rate consistent', async () => {
    for (const sampleRate of [44100, 48000]) {
      const f = fixture(sampleRate);
      await f.client.start(f.stream, f.token);
      expect(new URL(f.openSocket.mock.calls[0][0]).searchParams.get('audio_format')).toBe(
        `pcm_${sampleRate}`,
      );
      f.sockets[0].emit({ message_type: 'session_started' });
      f.frames[0](new ArrayBuffer(sampleRate / 5));
      expect(JSON.parse(f.sockets[0].send.mock.calls[0][0]).sample_rate).toBe(sampleRate);
      f.client.dispose();
    }
  });

  it('drains startup audio under socket backpressure without losing frames or failing the preview', async () => {
    const f = fixture();
    await f.client.start(f.stream, f.token);
    const socket = f.sockets[0];
    socket.send.mockImplementation((message: string) => {
      socket.bufferedAmount += message.length;
    });
    for (let i = 0; i < 40; i++) f.frames[0](new Uint8Array(3200).fill(i).buffer);
    socket.emit({ message_type: 'session_started' });
    expect(socket.send.mock.calls.length).toBeLessThan(40);
    expect(f.state().status).toBe('listening');
    for (let i = 0; i < 4; i++) {
      socket.bufferedAmount = 0;
      await vi.advanceTimersByTimeAsync(50);
    }
    expect(socket.send).toHaveBeenCalledTimes(40);
    expect(
      socket.send.mock.calls.map(([message]) => atob(JSON.parse(message).audio_base_64).charCodeAt(0)),
    ).toEqual(Array.from({ length: 40 }, (_, i) => i));
    f.client.dispose();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('keeps short-recording audio through a late handshake and commits after the queued audio', async () => {
    const f = fixture();
    await f.client.start(f.stream, f.token);
    const socket = f.sockets[0];
    f.frames[0](new Uint8Array([1, 0, 2, 0]).buffer);
    f.client.stop();
    expect(socket.close).not.toHaveBeenCalled();
    socket.emit({ message_type: 'session_started' });
    expect(f.state().status).toBe('stopped');
    expect(socket.send.mock.calls.map(([message]) => JSON.parse(message).commit)).toEqual([false, true]);
    expect(JSON.parse(socket.send.mock.calls[0][0]).audio_base_64).toBe('AQACAA==');
    socket.emit({ message_type: 'committed_transcript', text: 'Short synthetic phrase.' });
    await vi.advanceTimersByTimeAsync(3000);
    expect(f.state().committed).toBe('Short synthetic phrase.');
    expect(socket.close).toHaveBeenCalledOnce();
    expect(f.track.stop).not.toHaveBeenCalled();
  });

  it('flushes the worklet tail before committing and ignores later audio after the flush', async () => {
    const f = fixture();
    const finished = deferred<void>();
    const finish = vi.fn(() => finished.promise);
    f.audio.mockImplementationOnce(async (_stream, receive) => {
      f.frames.push(receive);
      return { close: vi.fn(), sampleRate: 16000, finish };
    });
    await f.client.start(f.stream, f.token);
    const socket = f.sockets[0];
    socket.emit({ message_type: 'session_started' });
    f.client.stop();
    expect(finish).toHaveBeenCalledOnce();
    expect(socket.send).not.toHaveBeenCalled();
    f.frames[0](new Uint8Array([3, 0]).buffer);
    finished.resolve();
    await Promise.resolve();
    expect(socket.send.mock.calls.map(([message]) => JSON.parse(message).commit)).toEqual([false, true]);
    f.frames[0](new ArrayBuffer(100));
    expect(socket.send).toHaveBeenCalledTimes(2);
    f.client.dispose();
  });

  it('bounds a stopped session when the handshake or socket never drains', async () => {
    const f = fixture();
    await f.client.start(f.stream, f.token);
    f.client.stop();
    f.sockets[0].bufferedAmount = 100_000;
    f.sockets[0].emit({ message_type: 'session_started' });
    await vi.advanceTimersByTimeAsync(15_000);
    expect(f.sockets[0].close).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });
});

it('the worklet emits little-endian mono PCM while leaving speaker output silent', () => {
  let Processor: any;
  const emitted: ArrayBuffer[] = [];
  const context = vm.createContext({
    sampleRate: 16000,
    AudioWorkletProcessor: class {
      port = { postMessage: (pcm: ArrayBuffer) => emitted.push(pcm) };
    },
    registerProcessor: (_name: string, ctor: unknown) => {
      Processor = ctor;
    },
  });
  vm.runInContext(readFileSync(new URL('./transcriptionWorklet.js', import.meta.url), 'utf8'), context);
  const processor = new Processor();
  const samples = new Float32Array(1600);
  samples.set([-2, 2, 0, 0.5, -0.5]);
  const output = new Float32Array(1600);
  processor.process([[samples]], [[output]]);
  const view = new DataView(emitted[0]);
  expect([0, 2, 4, 6, 8].map((offset) => view.getInt16(offset, true))).toEqual([
    -32768, 32767, 0, 16384, -16384,
  ]);
  expect(output.every((sample) => sample === 0)).toBe(true);
  processor.process([[new Float32Array(1600).fill(1), new Float32Array(1600).fill(-1)]]);
  expect(new Uint8Array(emitted[1]).every((sample) => sample === 0)).toBe(true);
});

it('the worklet sizes native-rate frames correctly and flushes partial audio exactly once', () => {
  for (const sampleRate of [16000, 44100, 48000]) {
    let Processor: any;
    const emitted: any[] = [];
    const context = vm.createContext({
      sampleRate,
      AudioWorkletProcessor: class {
        port = { onmessage: null, postMessage: (value: unknown) => emitted.push(value) };
      },
      registerProcessor: (_name: string, ctor: unknown) => {
        Processor = ctor;
      },
    });
    vm.runInContext(readFileSync(new URL('./transcriptionWorklet.js', import.meta.url), 'utf8'), context);
    const processor = new Processor();
    processor.process([[new Float32Array(sampleRate / 10 + 25).fill(0.5)]]);
    expect(emitted[0].byteLength).toBe(sampleRate / 5);
    expect(emitted).toHaveLength(1);
    processor.port.onmessage({ data: { type: 'flush' } });
    expect(emitted[1].byteLength).toBe(50);
    const tail = new DataView(emitted[1]);
    expect(Array.from({ length: 25 }, (_, i) => tail.getInt16(i * 2, true))).toEqual(Array(25).fill(16384));
    expect(emitted[2]).toEqual({ type: 'flushed' });
    processor.port.onmessage({ data: { type: 'flush' } });
    expect(processor.process([[new Float32Array(100).fill(1)]])).toBe(false);
    expect(emitted).toHaveLength(3);
  }
});

it('native AudioContext capture falls back cleanly, flushes before closing, and never stops the recorder tracks', async () => {
  const source = { connect: vi.fn(), disconnect: vi.fn() };
  const audio = {
    sampleRate: 48000,
    audioWorklet: { addModule: vi.fn(async (_url: string) => {}) },
    resume: vi.fn(async () => {}),
    close: vi.fn(async () => {}),
    createMediaStreamSource: vi.fn(() => source),
    destination: {},
  };
  const port: {
    onmessage: ((event: { data: unknown }) => void) | null;
    postMessage: ReturnType<typeof vi.fn>;
    close: ReturnType<typeof vi.fn>;
  } = { onmessage: null, postMessage: vi.fn(), close: vi.fn() };
  const node = { port, connect: vi.fn(), disconnect: vi.fn(), onprocessorerror: null };
  const constructors: (AudioContextOptions | undefined)[] = [];
  vi.stubGlobal(
    'AudioContext',
    class {
      constructor(options?: AudioContextOptions) {
        constructors.push(options);
        if (options) throw new DOMException('Synthetic device requires native rate.', 'NotSupportedError');
        return audio;
      }
    },
  );
  vi.stubGlobal(
    'AudioWorkletNode',
    class {
      constructor() {
        return node;
      }
    },
  );
  const socket = new Socket();
  let socketURL = '';
  vi.stubGlobal(
    'WebSocket',
    class {
      constructor(url: string) {
        socketURL = url;
        return socket;
      }
    },
  );
  const track = { stop: vi.fn() };
  const stream = { getTracks: () => [track] } as unknown as MediaStream;
  const client = new LiveTranscription(vi.fn());
  await client.start(stream, async () => 'synthetic-token');
  expect(constructors).toEqual([{ sampleRate: 16000 }, undefined]);
  expect(audio.createMediaStreamSource).toHaveBeenCalledWith(stream);
  expect(new URL(socketURL).searchParams.get('audio_format')).toBe('pcm_48000');
  socket.emit({ message_type: 'session_started' });
  client.stop();
  expect(source.disconnect).toHaveBeenCalled();
  expect(port.postMessage).toHaveBeenCalledWith({ type: 'flush' });
  expect(audio.close).not.toHaveBeenCalled();
  port.onmessage?.({ data: new Uint8Array([4, 0]).buffer });
  port.onmessage?.({ data: { type: 'flushed' } });
  await Promise.resolve();
  expect(socket.send.mock.calls.map(([message]) => JSON.parse(message).commit)).toEqual([false, true]);
  expect(JSON.parse(socket.send.mock.calls[0][0]).sample_rate).toBe(48000);
  expect(audio.close).toHaveBeenCalledOnce();
  expect(port.close).toHaveBeenCalledOnce();
  expect(track.stop).not.toHaveBeenCalled();
  client.dispose();
  expect(vi.getTimerCount()).toBe(0);
});
