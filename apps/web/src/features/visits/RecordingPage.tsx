// Purpose: Provide a focused full-page workspace for recording or uploading a consented appointment.
// Inputs: Shared recording draft, browser capture capabilities and original audio preview.
// Outputs: Title/notes editing, recording controls, an integrated upload mode and explicit save/discard.
// Side effects: Revokes preview URLs on navigation; shared recording capture remains alive in the provider.

import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, AudioLines, Check, FileAudio, Mic, Pause, Play, Square, Upload } from 'lucide-react';
import { Button, Field } from '../../components/ui';
import { durationLabel } from '../../core/domain';
import { useRecordingSession } from './RecordingSession';

// MARK: - Dedicated recording route uses shared state, never a route-owned MediaRecorder
export function RecordingPage() {
  const session = useRecordingSession();
  const { draft, capture, original, upload, active, reading, saving } = session;
  const [preview, setPreview] = useState('');
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    // A save/cancel updates the hash before the shell receives hashchange. Do not reopen consent
    // during that final render of a page the user has already left.
    if (!draft && !session.pending && window.location.hash.split('?')[0] === '#/recording')
      session.requestSession();
  }, [draft, session.pending]);
  useEffect(() => {
    if (!original) {
      setPreview('');
      return;
    }
    const url = URL.createObjectURL(original);
    setPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [original]);
  if (!draft)
    return (
      <div className="recording-page">
        <p className="muted">Confirm permission to open your recording workspace.</p>
      </div>
    );
  const microphone = draft.mode === 'microphone';
  const status =
    capture.state === 'requesting'
      ? 'Waiting for microphone permission…'
      : capture.state === 'recording'
        ? 'Recording your conversation'
        : capture.state === 'paused'
          ? 'Paused. Take your time.'
          : original
            ? 'Ready to review and save'
            : 'Ready when you are';
  return (
    <div className="recording-page">
      <a className="text-link back-link" href={draft.returnHash}>
        <ArrowLeft size={16} /> Back to your workspace
      </a>
      <header className="recording-heading">
        <h1 className="recording-title-heading" aria-label={draft.title.trim() || 'Session recording'}>
          <input
            aria-label="Session title"
            title="Edit session title"
            value={draft.title}
            placeholder="Add a session title"
            maxLength={180}
            disabled={saving || reading}
            onChange={(event) => session.updateDraft({ title: event.target.value })}
          />
        </h1>
        <div className="recording-actions" role="group" aria-label="Session actions">
          <Button variant="ghost" onClick={session.discard} disabled={reading || saving}>
            {session.hasUnsaved ? 'Discard draft' : 'Cancel session'}
          </Button>
          <Button
            className="recording-save"
            disabled={!original || active || reading || saving}
            onClick={() => void session.save()}
          >
            {saving ? 'Saving…' : 'Save recording'}
          </Button>
        </div>
      </header>
      <div className="recording-workspace">
        <div className="recording-mode-switch" role="group" aria-label="Audio source">
          <button
            type="button"
            aria-pressed={microphone}
            disabled={active || Boolean(original) || reading || saving}
            onClick={() => session.setMode('microphone')}
          >
            <Mic size={16} /> Record live
          </button>
          <button
            type="button"
            aria-pressed={!microphone}
            disabled={active || Boolean(original) || reading || saving}
            onClick={() => session.setMode('upload')}
          >
            <Upload size={16} /> Upload audio
          </button>
        </div>
        <section className="recording-studio" aria-label="Session audio">
          {microphone ? (
            <div className={`recording-capture-stage${capture.state === 'recording' ? ' is-recording' : ''}`}>
              <div className="recording-audio-symbol" aria-hidden="true">
                <AudioLines size={38} />
              </div>
              <p className="recording-page-timer" role="timer" aria-label="Recorded duration">
                {durationLabel(session.duration)}
              </p>
              <p className="recording-stage-status" role="status">
                {status}
              </p>
              <div className="recording-primary-controls">
                {!active && !original && (
                  <Button
                    disabled={!capture.supported || reading || saving}
                    onClick={() => void session.start()}
                  >
                    <Mic size={18} /> Start recording
                  </Button>
                )}
                {capture.state === 'recording' && (
                  <Button variant="secondary" onClick={capture.pause}>
                    <Pause size={18} /> Pause
                  </Button>
                )}
                {capture.state === 'paused' && (
                  <Button variant="secondary" onClick={capture.resume}>
                    <Play size={18} /> Resume
                  </Button>
                )}
                {(capture.state === 'recording' || capture.state === 'paused') && (
                  <Button onClick={capture.stop}>
                    <Square size={16} /> Stop recording
                  </Button>
                )}
              </div>
              {!capture.supported && (
                <p className="inline-error">
                  Your browser cannot record here. Choose Upload audio to use an existing recording.
                </p>
              )}
            </div>
          ) : (
            <div className="recording-upload-stage">
              <span className="recording-audio-symbol" aria-hidden="true">
                <FileAudio size={36} />
              </span>
              <h2>{upload ? 'Your audio is ready.' : 'Already have a recording?'}</h2>
              <p>{upload ? upload.blob.name : 'Bring the original conversation into your workspace.'}</p>
              {upload ? (
                <span className="recording-upload-meta">
                  {durationLabel(upload.duration)} · {(upload.blob.size / (1024 * 1024)).toFixed(1)} MiB
                </span>
              ) : (
                <>
                  <Button
                    variant="secondary"
                    disabled={reading || saving}
                    onClick={() => input.current?.click()}
                  >
                    <Upload size={17} /> {reading ? 'Opening audio…' : 'Choose audio file'}
                  </Button>
                  <input
                    ref={input}
                    className="sr-only"
                    type="file"
                    tabIndex={-1}
                    aria-label="Upload existing audio"
                    accept="audio/*,.m4a,.mp3,.wav,.webm,.ogg"
                    disabled={reading || saving}
                    onChange={(event) => {
                      const file = event.target.files?.[0];
                      event.target.value = '';
                      if (file) void session.chooseAudio(file);
                    }}
                  />
                  <p className="recording-stage-hint">M4A, MP3, WAV, WebM or Ogg · up to 16 MiB</p>
                </>
              )}
            </div>
          )}
          {preview && (
            <div className="recording-preview">
              <h3>Listen back</h3>
              <audio controls preload="metadata" src={preview}>
                Audio playback is unavailable.
              </audio>
              <p>Your original audio is kept with this session.</p>
            </div>
          )}
        </section>
        <section className="recording-details" aria-label="Session notes">
          <Field label="Your notes">
            <textarea
              rows={7}
              maxLength={20000}
              disabled={saving || reading}
              placeholder="Questions, reminders, anything you want to remember…"
              value={draft.notes}
              onChange={(event) => session.updateDraft({ notes: event.target.value })}
            />
          </Field>
        </section>
        <div className="recording-stage-footer">
          <span>
            <Check size={14} /> Original audio preserved
          </span>
          <span>{microphone ? 'Up to 30 min · 16 MiB' : 'No conversion needed'}</span>
        </div>
      </div>
      {session.detachedVisit && (
        <p className="recording-page-notice" role="status">
          The linked visit was removed. This audio and your notes will be saved as a standalone session.
        </p>
      )}
      {capture.notice && (
        <p className="recording-page-notice" role="status">
          {capture.notice}
        </p>
      )}
      {(capture.error || session.error) && (
        <p className="inline-error" role="alert">
          {session.error || capture.error}
        </p>
      )}
    </div>
  );
}
