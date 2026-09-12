// Purpose: Let a user explicitly record or upload original visit audio and save it with notes.
// Inputs: A visit, participant consent, browser microphone support, or a user-selected audio file.
// Outputs: A durable recording with original audio and no invented transcript.
// Side effects: Captures microphone only after consent; saves audio and metadata atomically in the active workspace.

import { useEffect, useState, type ChangeEvent } from 'react';
import { Mic, Pause, Play, Square, Upload } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import type { Visit, VisitRecording } from '../../core/models';
import { durationLabel, nowISO, uid } from '../../core/domain';
import { Button, Field, Modal } from '../../components/ui';
import { audioExtension, MAX_AUDIO_BYTES, useVisitRecorder } from './useVisitRecorder';

// MARK: - Bounded metadata inspection for uploaded originals
async function inspectDuration(blob: Blob): Promise<number> {
  const url = URL.createObjectURL(blob);
  const audio = document.createElement('audio');
  audio.preload = 'metadata';
  try {
    return await new Promise<number>((resolve, reject) => {
      const timeout = window.setTimeout(
        () => reject(new Error('This audio could not be read. Try an MP3, M4A, or WAV file.')),
        10000,
      );
      audio.onloadedmetadata = () => {
        window.clearTimeout(timeout);
        Number.isFinite(audio.duration) && audio.duration > 0 && audio.duration <= 24 * 3600
          ? resolve(audio.duration)
          : reject(
              new Error('This file has no usable duration. Export it as MP3, M4A, or WAV and try again.'),
            );
      };
      audio.onerror = () => {
        window.clearTimeout(timeout);
        reject(new Error('The browser cannot read this audio file. Try MP3, M4A, or WAV.'));
      };
      audio.src = url;
    });
  } finally {
    audio.removeAttribute('src');
    audio.load();
    URL.revokeObjectURL(url);
  }
}

// MARK: - Consent, capture preview, and explicit durable save
export function RecordingCapture({ visit, onClose }: { visit: Visit; onClose: () => void }) {
  const { saveRecording, notify } = useReva();
  const capture = useVisitRecorder();
  const [id] = useState(uid);
  const [consent, setConsent] = useState(false);
  const [title, setTitle] = useState(`${visit.title} · recording`);
  const [notes, setNotes] = useState('');
  const [upload, setUpload] = useState<{ blob: Blob; duration: number; extension: string } | null>(null);
  const [reading, setReading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [preview, setPreview] = useState('');
  const original = upload?.blob ?? capture.blob;
  const active =
    capture.state === 'recording' || capture.state === 'paused' || capture.state === 'requesting';
  const duration = upload?.duration ?? capture.seconds;
  useEffect(() => {
    if (!original) {
      setPreview('');
      return;
    }
    const url = URL.createObjectURL(original);
    setPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [original]);
  function close() {
    if (saving || reading) return;
    if (
      (active || original) &&
      !window.confirm('Discard this unsaved recording? Saved visits and audio will stay available.')
    )
      return;
    onClose();
  }
  async function chooseAudio(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setError('');
    setReading(true);
    try {
      if (!consent)
        throw new Error('Confirm your doctor and everyone present agreed before uploading audio.');
      const extension = file.name.split('.').pop()?.toLowerCase() ?? '';
      if (!['m4a', 'mp4', 'mp3', 'wav', 'webm', 'ogg'].includes(extension))
        throw new Error('Choose an M4A, MP3, WAV, WebM, or Ogg audio file.');
      if (!file.size || file.size > MAX_AUDIO_BYTES)
        throw new Error('Audio must be nonempty and no larger than 16 MiB.');
      const measured = await inspectDuration(file);
      setUpload({ blob: file, duration: measured, extension });
      if (!title.trim() || title === `${visit.title} · recording`)
        setTitle(file.name.replace(/\.[^.]+$/, ''));
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'This audio could not be opened.');
    } finally {
      setReading(false);
    }
  }
  async function save() {
    if (!original || active || saving) return;
    setError('');
    setSaving(true);
    try {
      if (!consent) throw new Error('Confirm your doctor and everyone present agreed before saving audio.');
      if (!title.trim()) throw new Error('Add a title for this recording.');
      if (!Number.isFinite(duration) || duration <= 0)
        throw new Error('This recording has no captured audio duration.');
      if (original.size > MAX_AUDIO_BYTES) throw new Error('Audio exceeds the 16 MiB limit.');
      const filename = `reva-audio-${id}.${upload?.extension ?? audioExtension(original.type)}`;
      const recording: VisitRecording = {
        id,
        visitID: visit.id,
        title: title.trim(),
        createdAt: nowISO(),
        duration,
        audioFilename: filename,
        segments: [],
        summary: notes.trim(),
        isSample: false,
        status: 'saved',
      };
      await saveRecording(recording, original);
      notify('Original audio saved. Add a transcript when your transcription service is configured.');
      onClose();
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : 'Your audio could not be saved. Keep this dialog open and try again.',
      );
    } finally {
      setSaving(false);
    }
  }
  return (
    <Modal title="Record appointment" onClose={close}>
      <div className="stack">
        <p className="muted">
          Get your doctor’s consent and permission from everyone present before recording.
        </p>
        <label className="row">
          <input
            type="checkbox"
            checked={consent}
            disabled={active || saving}
            onChange={(event) => setConsent(event.target.checked)}
          />
          <span>My doctor and everyone present agreed to recording.</span>
        </label>
        <Field label="Recording title">
          <input value={title} maxLength={180} onChange={(event) => setTitle(event.target.value)} />
        </Field>
        {!upload && (
          <>
            {!capture.supported && (
              <p className="inline-error">
                Microphone recording is unavailable in this browser or connection. You can upload existing
                audio below.
              </p>
            )}
            <div className="recording-controls">
              <p className="recording-timer" role="timer" aria-label="Recorded duration">
                {durationLabel(capture.seconds)}
              </p>
              <p className="muted small">
                {capture.state === 'requesting'
                  ? 'Waiting for microphone permission…'
                  : capture.state === 'recording'
                    ? 'Recording'
                    : capture.state === 'paused'
                      ? 'Paused'
                      : capture.blob
                        ? 'Ready to save'
                        : 'Ready when you are'}
              </p>
              <div className="row">
                {(capture.state === 'idle' || capture.state === 'stopped') && !capture.blob && (
                  <Button
                    disabled={!consent || !capture.supported || reading}
                    onClick={() => {
                      void capture.start();
                    }}
                  >
                    <Mic size={18} /> Start recording
                  </Button>
                )}
                {capture.state === 'recording' && (
                  <Button variant="secondary" onClick={capture.pause}>
                    <Pause size={17} /> Pause
                  </Button>
                )}
                {capture.state === 'paused' && (
                  <Button variant="secondary" onClick={capture.resume}>
                    <Play size={17} /> Resume
                  </Button>
                )}
                {(capture.state === 'recording' || capture.state === 'paused') && (
                  <Button onClick={capture.stop}>
                    <Square size={16} /> Stop recording
                  </Button>
                )}
              </div>
            </div>
            <p className="muted small">
              Recording pauses when you leave this page. Maximum 30 minutes or 16 MiB per recording.
            </p>
          </>
        )}
        {capture.notice && (
          <p className="small" role="status">
            {capture.notice}
          </p>
        )}
        {capture.error && (
          <p className="inline-error" role="alert">
            {capture.error}
          </p>
        )}
        {!active && !original && (
          <Field label="Or upload existing audio" hint="M4A, MP3, WAV, WebM, or Ogg · up to 16 MiB">
            <span className="row">
              <Upload size={17} />
              <input
                type="file"
                accept="audio/*,.m4a,.mp3,.wav,.webm,.ogg"
                disabled={reading || !consent}
                onChange={(event) => {
                  void chooseAudio(event);
                }}
              />
            </span>
          </Field>
        )}
        {reading && <p role="status">Reading audio…</p>}
        {preview && (
          <div className="stack">
            <strong>Review original audio · {durationLabel(duration)}</strong>
            <audio controls preload="metadata" src={preview}>
              Audio playback is unavailable.
            </audio>
            <p className="muted small">No transcript has been created for this audio.</p>
          </div>
        )}
        <Field label="Your visit notes (optional)" hint="These stay separate from any transcript.">
          <textarea
            rows={3}
            maxLength={20000}
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
          />
        </Field>
        {error && (
          <p className="inline-error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <Button variant="secondary" onClick={close} disabled={saving || reading}>
            Cancel
          </Button>
          <Button
            onClick={() => {
              void save();
            }}
            disabled={!consent || !original || active || saving || reading}
          >
            {saving ? 'Saving…' : 'Save recording'}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
