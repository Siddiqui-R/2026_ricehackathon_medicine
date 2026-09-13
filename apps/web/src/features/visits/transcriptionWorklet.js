// Purpose: Copy consented microphone audio to small PCM16 frames without playing it back.
// Runs off the UI thread. The MediaRecorder still owns and saves the original audio.
class RevaTranscriptionPCM extends AudioWorkletProcessor {
  constructor() {
    super();
    this.samples = new ArrayBuffer(3200); // 100 ms at 16 kHz, signed little-endian PCM.
    this.view = new DataView(this.samples);
    this.offset = 0;
  }
  process(inputs) {
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
        this.samples = new ArrayBuffer(3200);
        this.view = new DataView(this.samples);
        this.offset = 0;
      }
    }
    // The output stays silent. Never connect microphone samples to the speakers.
    return true;
  }
}
registerProcessor('reva-transcription-pcm', RevaTranscriptionPCM);
