// Purpose: Stream the recorder's existing microphone to Scribe using a one-use session token.
// Outputs: An ephemeral live preview. Saved-audio transcription remains the final source of record.
// Bounds: 15-second connection timeout, eight seconds of queued PCM, 200k preview characters.
// No credential persistence, secondary microphone request, automatic retry, or provider error logging.
export interface LiveTranscript {
  status: 'idle' | 'connecting' | 'listening' | 'paused' | 'stopped' | 'unavailable';
  committed: string;
  partial: string;
}
export const emptyLiveTranscript: LiveTranscript = { status: 'idle', committed: '', partial: '' };
type TokenLoader = (signal: AbortSignal) => Promise<string>;
interface AudioTap {
  sampleRate?: number;
  finish?(): Promise<void>;
  close(): void;
}
interface LiveDependencies {
  audio(
    stream: MediaStream,
    receive: (pcm: ArrayBuffer) => void,
    failed: () => void,
    signal: AbortSignal,
  ): Promise<AudioTap>;
  socket(url: string): WebSocket;
}

// AudioWorklet keeps sample conversion off the main thread and reuses the recorder's consented stream.
async function openAudioTap(
  stream: MediaStream,
  receive: (pcm: ArrayBuffer) => void,
  failed: () => void,
  signal: AbortSignal,
): Promise<AudioTap> {
  let context: AudioContext;
  try {
    context = new AudioContext({ sampleRate: 16_000 });
  } catch {
    // Some browsers accept only the device's native sample rate, which Scribe also supports.
    context = new AudioContext();
  }
  let source: MediaStreamAudioSourceNode | undefined;
  let node: AudioWorkletNode | undefined;
  let closed = false;
  let finishing: Promise<void> | undefined;
  let finishResolve: (() => void) | undefined;
  let flushTimeout: ReturnType<typeof setTimeout> | undefined;
  const close = () => {
    if (closed) return;
    closed = true;
    clearTimeout(flushTimeout);
    signal.removeEventListener('abort', close);
    source?.disconnect();
    node?.disconnect();
    if (node) {
      node.port.onmessage = null;
      node.onprocessorerror = null;
      node.port.close();
    }
    void context.close().catch(() => {});
    finishResolve?.();
  };
  signal.addEventListener('abort', close, { once: true });
  try {
    if (signal.aborted) throw new Error('Capture canceled.');
    if (![8000, 16000, 22050, 24000, 44100, 48000].includes(context.sampleRate) || !context.audioWorklet)
      throw new Error('Unsupported audio capture.');
    await context.resume();
    if (signal.aborted) throw new Error('Capture canceled.');
    await context.audioWorklet.addModule(
      new URL('./transcriptionWorklet.js?no-inline', import.meta.url).href,
    );
    if (signal.aborted) throw new Error('Capture canceled.');
    source = context.createMediaStreamSource(stream);
    node = new AudioWorkletNode(context, 'reva-transcription-pcm', { outputChannelCount: [1] });
    node.port.onmessage = (event: MessageEvent<ArrayBuffer | { type: 'flushed' }>) => {
      if (closed) return;
      if (event.data instanceof ArrayBuffer) receive(event.data);
      else if (event.data?.type === 'flushed') close();
    };
    node.onprocessorerror = failed;
    source.connect(node);
    node.connect(context.destination);
    return {
      sampleRate: context.sampleRate,
      close,
      finish: () => {
        if (closed) return Promise.resolve();
        if (finishing) return finishing;
        finishing = new Promise<void>((resolve) => {
          finishResolve = resolve;
          source?.disconnect();
          // Flush the final fraction of a 100 ms frame before disconnecting its message port.
          flushTimeout = setTimeout(close, 250);
          node?.port.postMessage({ type: 'flush' });
        });
        return finishing;
      },
    };
  } catch (error) {
    close();
    throw error;
  }
}

interface Connection {
  abort: AbortController;
  socket?: WebSocket;
  audio?: AudioTap;
  ready: boolean;
  ending: boolean;
  flushing: boolean;
  commitSent: boolean;
  sampleRate: number;
  queue: ArrayBuffer[];
  queuedBytes: number;
  timeout?: ReturnType<typeof setTimeout>;
  pumpTimeout?: ReturnType<typeof setTimeout>;
}
export class LiveTranscription {
  private value: LiveTranscript = { ...emptyLiveTranscript };
  private connection?: Connection;
  constructor(
    private changed: (value: LiveTranscript) => void,
    private dependencies: LiveDependencies = { audio: openAudioTap, socket: (url) => new WebSocket(url) },
  ) {}
  private publish(patch: Partial<LiveTranscript>) {
    this.value = { ...this.value, ...patch };
    this.changed(this.value);
  }
  private close(connection: Connection) {
    clearTimeout(connection.timeout);
    clearTimeout(connection.pumpTimeout);
    connection.abort.abort();
    connection.audio?.close();
    connection.queue = [];
    connection.queuedBytes = 0;
    if (connection.socket) {
      connection.socket.onopen = connection.socket.onmessage = null;
      connection.socket.onclose = connection.socket.onerror = null;
      connection.socket.close();
    }
    if (this.connection === connection) this.connection = undefined;
  }
  private failed(connection: Connection) {
    if (this.connection !== connection) return;
    this.close(connection);
    this.publish({ status: 'unavailable' });
  }
  start = async (stream: MediaStream, token: TokenLoader) => {
    if (this.connection) this.close(this.connection);
    // Keep the preceding preview across pause/resume; it is never used as the saved final transcript.
    const committed = [this.value.committed, this.value.partial].filter(Boolean).join('\n');
    this.publish({ status: 'connecting', committed, partial: '' });
    const connection: Connection = {
      abort: new AbortController(),
      ready: false,
      ending: false,
      flushing: false,
      commitSent: false,
      sampleRate: 16_000,
      queue: [],
      queuedBytes: 0,
    };
    this.connection = connection;
    connection.timeout = setTimeout(() => this.failed(connection), 15_000);
    try {
      const audio = await this.dependencies.audio(
        stream,
        (pcm) => this.audio(connection, pcm),
        () => this.failed(connection),
        connection.abort.signal,
      );
      if (this.connection !== connection) {
        audio.close();
        return;
      }
      connection.audio = audio;
      connection.sampleRate = audio.sampleRate ?? 16_000;
      if (connection.ending) this.finishAudio(connection);
      const credential = await token(connection.abort.signal);
      if (this.connection !== connection) return;
      const query = new URLSearchParams({
        token: credential,
        model_id: 'scribe_v2_realtime',
        audio_format: `pcm_${connection.sampleRate}`,
        commit_strategy: 'vad',
      });
      const socket = this.dependencies.socket(`wss://api.elevenlabs.io/v1/speech-to-text/realtime?${query}`);
      connection.socket = socket;
      socket.onmessage = (event: MessageEvent) => this.message(connection, event.data);
      socket.onerror = () => this.failed(connection);
      socket.onclose = () => {
        if (connection.ending) this.close(connection);
        else this.failed(connection);
      };
    } catch {
      this.failed(connection);
    }
  };
  private audio(connection: Connection, pcm: ArrayBuffer) {
    if (this.connection !== connection || (connection.ending && !connection.flushing)) return;
    connection.queue.push(pcm);
    connection.queuedBytes += pcm.byteLength;
    if (connection.queuedBytes > connection.sampleRate * 2 * 8) this.failed(connection);
    else this.pump(connection);
  }
  private pump(connection: Connection) {
    if (this.connection !== connection || !connection.ready || connection.pumpTimeout) return;
    if (connection.socket?.readyState !== 1) {
      this.failed(connection);
      return;
    }
    while (connection.queue.length && connection.socket.bufferedAmount <= 64_000) {
      const pcm = connection.queue.shift()!;
      connection.queuedBytes -= pcm.byteLength;
      this.send(connection, pcm);
      if (this.connection !== connection) return;
    }
    if (connection.queue.length || connection.socket.bufferedAmount > 64_000) {
      // Startup audio can exceed one socket buffer without being an audio/provider failure.
      connection.pumpTimeout = setTimeout(() => {
        connection.pumpTimeout = undefined;
        this.pump(connection);
      }, 50);
    } else if (connection.ending && !connection.flushing && !connection.commitSent) {
      connection.commitSent = true;
      this.send(connection, new ArrayBuffer(0), true);
      if (this.connection === connection) {
        clearTimeout(connection.timeout);
        // VAD can return multiple final segments, so retain them for this bounded grace period.
        connection.timeout = setTimeout(() => this.close(connection), 3000);
      }
    }
  }
  private send(connection: Connection, pcm: ArrayBuffer, commit = false) {
    if (connection.socket?.readyState !== 1) {
      this.failed(connection);
      return;
    }
    try {
      const bytes = new Uint8Array(pcm);
      let binary = '';
      for (const byte of bytes) binary += String.fromCharCode(byte);
      connection.socket.send(
        JSON.stringify({
          message_type: 'input_audio_chunk',
          audio_base_64: btoa(binary),
          sample_rate: connection.sampleRate,
          commit,
        }),
      );
    } catch {
      this.failed(connection);
    }
  }
  private message(connection: Connection, data: unknown) {
    if (this.connection !== connection) return;
    try {
      if (typeof data !== 'string' || data.length > 250_000) throw new Error();
      const event = JSON.parse(data);
      if (event.message_type === 'session_started' && !connection.ready) {
        connection.ready = true;
        if (!connection.ending) {
          clearTimeout(connection.timeout);
          this.publish({ status: 'listening' });
        }
        this.pump(connection);
      } else if (['partial_transcript', 'committed_transcript'].includes(event.message_type)) {
        if (typeof event.text !== 'string' || event.text.length + this.value.committed.length > 200_000)
          throw new Error();
        if (event.message_type === 'partial_transcript') this.publish({ partial: event.text });
        else {
          this.publish({
            committed: [this.value.committed, event.text.trim()].filter(Boolean).join('\n'),
            partial: '',
          });
        }
      } else if (
        event.error ||
        /error|exceeded|rate_limited|timeout|unaccepted|insufficient/.test(event.message_type ?? '')
      ) {
        this.failed(connection);
      }
    } catch {
      this.failed(connection);
    }
  }
  private finishAudio(connection: Connection) {
    if (!connection.audio || connection.flushing) return;
    if (connection.audio.finish) {
      connection.flushing = true;
      void connection.audio.finish().then(
        () => {
          if (this.connection !== connection) return;
          connection.flushing = false;
          this.pump(connection);
        },
        () => this.failed(connection),
      );
    } else {
      connection.audio.close();
      this.pump(connection);
    }
  }
  stop = (status: 'paused' | 'stopped' = 'stopped') => {
    const connection = this.connection;
    if (this.value.status !== 'unavailable') this.publish({ status });
    if (!connection || connection.ending) return;
    connection.ending = true;
    // Let an in-flight handshake finish so short recordings can still send their captured preview.
    clearTimeout(connection.timeout);
    connection.timeout = setTimeout(() => this.close(connection), 15_000);
    this.finishAudio(connection);
  };
  reset = () => {
    if (this.connection) this.close(this.connection);
    this.publish({ ...emptyLiveTranscript });
  };
  dispose = () => {
    if (this.connection) this.close(this.connection);
  };
}
