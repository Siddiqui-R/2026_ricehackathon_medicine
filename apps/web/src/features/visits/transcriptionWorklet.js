// Purpose: Copy consented microphone audio to small PCM16 frames without playing it back.
// Runs off the UI thread. The MediaRecorder still owns and saves the original audio.
class RevaTranscriptionPCM extends AudioWorkletProcessor {
  constructor() {
    super();
    this.frameBytes = Math.round(sampleRate / 10) * 2;
    this.samples = new ArrayBuffer(this.frameBytes); // 100 ms at the AudioContext's actual rate.
    this.view = new DataView(this.samples);
    this.offset = 0;
    this.finished = false;
    this.port.onmessage = (event) => {
      if (event.data?.type !== 'flush' || this.finished) return;
      this.finished = true;
      if (this.offset) {
        const tail = this.samples.slice(0, this.offset);
        this.port.postMessage(tail, [tail]);
        this.offset = 0;
      }
      this.port.postMessage({ type: 'flushed' });
    };
  }
  process(inputs) {
    if (this.finished) return false;
    const channels = inputs[0];
    if (!channels?.length) return true;
    for (let i = 0; i < channels[0].length; i++) {
      let sample = 0;
      for (const channel of channels) sample += channel[i] || 0;
      sample = Math.max(-1, Math.min(1, sample / channels.length));
      this.view.setInt16(this.offset, Math.round(sample * (sample < 0 ? 32768 : 32767)), true);
      this.offset += 2;
      if (this.offset === this.samples.byteLength) {
        this.port.postMessage(this.samples, [this.samples]);
        this.samples = new ArrayBuffer(this.frameBytes);
        this.view = new DataView(this.samples);
        this.offset = 0;
      }
    }
    // The output stays silent. Never connect microphone samples to the speakers.
    return true;
  }
}
registerProcessor('reva-transcription-pcm', RevaTranscriptionPCM);
