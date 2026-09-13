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
  const context = new AudioContext({ sampleRate: 16_000 });
  let source: MediaStreamAudioSourceNode | undefined;
  let node: AudioWorkletNode | undefined;
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    signal.removeEventListener('abort', close);
    source?.disconnect();
    node?.disconnect();
    if (node) {
      node.port.onmessage = null;
      node.onprocessorerror = null;
      node.port.close();
    }
    void context.close().catch(() => {});
  };
  signal.addEventListener('abort', close, { once: true });
  try {
    if (signal.aborted) throw new Error('Capture canceled.');
    if (context.sampleRate !== 16_000 || !context.audioWorklet) throw new Error('Unsupported audio capture.');
    await context.resume();
    if (signal.aborted) throw new Error('Capture canceled.');
    await context.audioWorklet.addModule(
      new URL('./transcriptionWorklet.js?no-inline', import.meta.url).href,
    );
    if (signal.aborted) throw new Error('Capture canceled.');
    source = context.createMediaStreamSource(stream);
    node = new AudioWorkletNode(context, 'reva-transcription-pcm', { outputChannelCount: [1] });
    node.port.onmessage = (event: MessageEvent<ArrayBuffer>) => {
      if (!closed) receive(event.data);
    };
    node.onprocessorerror = failed;
    source.connect(node);
    node.connect(context.destination);
    return { close };
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
  queue: ArrayBuffer[];
  queuedBytes: number;
  timeout?: ReturnType<typeof setTimeout>;
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
    connection.abort.abort();
    connection.audio?.close();
    connection.queue = [];
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
      const credential = await token(connection.abort.signal);
      if (this.connection !== connection) return;
      const query = new URLSearchParams({
        token: credential,
        model_id: 'scribe_v2_realtime',
        audio_format: 'pcm_16000',
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
    if (this.connection !== connection || connection.ending) return;
    if (connection.ready) this.send(connection, pcm);
    else {
      connection.queue.push(pcm);
      connection.queuedBytes += pcm.byteLength;
      if (connection.queuedBytes > 256_000) this.failed(connection);
    }
  }
  private send(connection: Connection, pcm: ArrayBuffer, commit = false) {
    if (connection.socket?.readyState !== 1 || connection.socket.bufferedAmount > 64_000) {
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
          sample_rate: 16_000,
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
        clearTimeout(connection.timeout);
        connection.ready = true;
        this.publish({ status: 'listening' });
        for (const pcm of connection.queue) {
          if (this.connection !== connection) break;
          this.send(connection, pcm);
        }
        connection.queue = [];
        connection.queuedBytes = 0;
      } else if (['partial_transcript', 'committed_transcript'].includes(event.message_type)) {
        if (typeof event.text !== 'string' || event.text.length + this.value.committed.length > 200_000)
          throw new Error();
        if (event.message_type === 'partial_transcript') this.publish({ partial: event.text });
        else {
          this.publish({
            committed: [this.value.committed, event.text.trim()].filter(Boolean).join('\n'),
            partial: '',
          });
          if (connection.ending) this.close(connection);
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
  stop = (status: 'paused' | 'stopped' = 'stopped') => {
    const connection = this.connection;
    if (this.value.status !== 'unavailable') this.publish({ status });
    if (!connection || connection.ending) return;
    connection.ending = true;
    connection.audio?.close();
    clearTimeout(connection.timeout);
    if (!connection.ready) {
      this.close(connection);
      return;
    }
    this.send(connection, new ArrayBuffer(0), true);
    if (this.connection === connection) connection.timeout = setTimeout(() => this.close(connection), 1500);
  };
  reset = () => {
    if (this.connection) this.close(this.connection);
    this.publish({ ...emptyLiveTranscript });
  };
  dispose = () => {
    if (this.connection) this.close(this.connection);
  };
}
