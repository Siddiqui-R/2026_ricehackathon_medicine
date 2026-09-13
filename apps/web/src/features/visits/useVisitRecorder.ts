// Purpose: Own the browser microphone lifecycle and produce bounded original audio for a visit.
// Inputs: Explicit Start/Pause/Resume/Stop actions from a consent-gated UI.
// Outputs: Capture state, elapsed active time, an original Blob, and actionable capture errors.
// Side effects: Requests microphone access; pauses when hidden and stops every track on cleanup.

import { useEffect, useRef, useState } from 'react';

export const MAX_AUDIO_BYTES = 16 * 1024 * 1024;
type CaptureState = 'idle' | 'requesting' | 'recording' | 'paused' | 'stopped';
export interface CaptureObserver {
  start(stream: MediaStream): void;
  resume(stream: MediaStream): void;
  pause(): void;
  stop(): void;
  reset(): void;
  dispose(): void;
}

// MARK: - Capability and container selection
export function audioExtension(type: string): string {
  if (type.includes('mp4')) return 'm4a';
  if (type.includes('ogg')) return 'ogg';
  if (type.includes('mpeg')) return 'mp3';
  if (type.includes('wav')) return 'wav';
  return 'webm';
}
export function useVisitRecorder(observer?: CaptureObserver) {
  const observerRef = useRef(observer);
  observerRef.current = observer;
  const [state, setState] = useState<CaptureState>('idle');
  const [seconds, setSeconds] = useState(0);
  const [startedAt, setStartedAt] = useState<string | null>(null);
  const [blob, setBlob] = useState<Blob | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const recorder = useRef<MediaRecorder | null>(null);
  const stream = useRef<MediaStream | null>(null);
  const alive = useRef(true);
  const generation = useRef(0);
  const chunks = useRef<Blob[]>([]);
  const byteCount = useRef(0);
  const overflow = useRef(false);
  const activeSince = useRef<number | null>(null);
  const elapsed = useRef(0);
  const supported =
    typeof MediaRecorder !== 'undefined' &&
    Boolean(navigator.mediaDevices?.getUserMedia) &&
    window.isSecureContext;
  function settleClock() {
    if (activeSince.current !== null) {
      elapsed.current += (performance.now() - activeSince.current) / 1000;
      activeSince.current = null;
    }
    if (alive.current) setSeconds(elapsed.current);
  }
  function stopTracks() {
    stream.current?.getTracks().forEach((track) => track.stop());
    stream.current = null;
  }
  function stop() {
    settleClock();
    observerRef.current?.stop();
    if (recorder.current && recorder.current.state !== 'inactive') recorder.current.stop();
    stopTracks();
  }
  function reset() {
    // Invalidate pending permission and queued media events before releasing the old draft.
    generation.current += 1;
    observerRef.current?.reset();
    if (recorder.current) {
      recorder.current.ondataavailable = null;
      recorder.current.onstop = null;
      recorder.current.onerror = null;
      if (recorder.current.state !== 'inactive') recorder.current.stop();
      recorder.current = null;
    }
    stopTracks();
    activeSince.current = null;
    elapsed.current = 0;
    chunks.current = [];
    byteCount.current = 0;
    overflow.current = false;
    setState('idle');
    setSeconds(0);
    setStartedAt(null);
    setBlob(null);
    setError('');
    setNotice('');
  }
  function pause() {
    if (recorder.current?.state !== 'recording') return;
    recorder.current.pause();
    observerRef.current?.pause();
    settleClock();
    setState('paused');
  }
  function resume() {
    if (recorder.current?.state !== 'paused' || document.hidden) return;
    recorder.current.resume();
    if (stream.current) observerRef.current?.resume(stream.current);
    activeSince.current = performance.now();
    setState('recording');
    setNotice('');
  }

  // MARK: - Explicit microphone request and original audio capture
  async function start() {
    if (!supported || recorder.current?.state === 'recording' || recorder.current?.state === 'paused') return;
    const attempt = ++generation.current;
    setError('');
    setNotice('');
    setState('requesting');
    setBlob(null);
    setSeconds(0);
    setStartedAt(null);
    elapsed.current = 0;
    try {
      const selected = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/ogg;codecs=opus'].find((type) =>
        MediaRecorder.isTypeSupported(type),
      );
      if (!selected)
        throw new Error(
          'This browser cannot create a supported recording. Upload an existing audio file instead.',
        );
      const source = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (!alive.current || attempt !== generation.current) {
        source.getTracks().forEach((track) => track.stop());
        return;
      }
      stream.current = source;
      if (document.hidden) {
        stopTracks();
        throw new Error('Keep this page visible when starting a recording.');
      }
      const media = new MediaRecorder(source, { mimeType: selected, audioBitsPerSecond: 64000 });
      recorder.current = media;
      chunks.current = [];
      byteCount.current = 0;
      overflow.current = false;
      media.ondataavailable = (event) => {
        if (!event.data.size) return;
        if (byteCount.current + event.data.size > MAX_AUDIO_BYTES) {
          overflow.current = true;
          if (alive.current)
            setError('This browser produced audio beyond the 16 MiB limit. Start a shorter recording.');
          stop();
          return;
        }
        chunks.current.push(event.data);
        byteCount.current += event.data.size;
        if (byteCount.current >= MAX_AUDIO_BYTES - 512 * 1024 && media.state !== 'inactive') {
          if (alive.current)
            setNotice('The recording size limit is near. Review and save this part before recording more.');
          stop();
        }
      };
      media.onerror = () => {
        if (alive.current)
          setError('Recording was interrupted. Any captured audio is available to review and save.');
        stop();
      };
      media.onstop = () => {
        settleClock();
        observerRef.current?.stop();
        stopTracks();
        if (alive.current && attempt === generation.current) {
          const captured = new Blob(chunks.current, { type: media.mimeType });
          if (captured.size && !overflow.current) setBlob(captured);
          else if (!overflow.current)
            setError('No audio was captured. Check microphone access and try again.');
          setState('stopped');
        }
      };
      source.getAudioTracks().forEach((track) => {
        track.onended = () => {
          if (media.state !== 'inactive') {
            if (alive.current) setNotice('The microphone disconnected. Review the captured audio.');
            stop();
          }
        };
      });
      media.start(1000);
      observerRef.current?.start(source);
      setStartedAt(new Date().toISOString());
      activeSince.current = performance.now();
      setState('recording');
    } catch (failure) {
      // A superseded permission attempt cannot touch the current stream or its UI state.
      if (!alive.current || attempt !== generation.current) return;
      stopTracks();
      observerRef.current?.stop();
      if (alive.current) {
        setState('idle');
        setError(
          failure instanceof DOMException && failure.name === 'NotAllowedError'
            ? 'Microphone access was not allowed. You can enable it in browser settings or upload an audio file.'
            : failure instanceof Error
              ? failure.message
              : 'The microphone could not be started.',
        );
      }
    }
  }

  // MARK: - Pause on hiding, bound duration, and release capture on unmount
  useEffect(() => {
    alive.current = true;
    const hidden = () => {
      if (document.hidden && recorder.current?.state === 'recording') {
        pause();
        setNotice('Recording paused when this page was hidden. Resume when everyone is ready.');
      }
    };
    const tick = window.setInterval(() => {
      const duration =
        elapsed.current +
        (activeSince.current === null ? 0 : (performance.now() - activeSince.current) / 1000);
      if (alive.current && activeSince.current !== null) setSeconds(duration);
      if (duration >= 30 * 60 && recorder.current?.state !== 'inactive') {
        setNotice('The 30-minute limit was reached. Save this part before recording more.');
        stop();
      }
    }, 250);
    document.addEventListener('visibilitychange', hidden);
    return () => {
      alive.current = false;
      generation.current += 1;
      observerRef.current?.dispose();
      window.clearInterval(tick);
      document.removeEventListener('visibilitychange', hidden);
      if (recorder.current) {
        recorder.current.ondataavailable = null;
        recorder.current.onstop = null;
        if (recorder.current.state !== 'inactive') recorder.current.stop();
      }
      stopTracks();
    };
  }, []);
  return { state, seconds, startedAt, blob, error, notice, supported, start, pause, resume, stop, reset };
}
