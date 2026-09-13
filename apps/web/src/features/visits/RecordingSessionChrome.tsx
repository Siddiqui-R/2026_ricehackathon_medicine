// Purpose: Keep consent and recording controls visible outside the currently selected workspace screen.
// Inputs: The app-scoped recording draft, microphone state and explicit user confirmation.
// Outputs: A full-viewport consent dialog and a sticky recording status banner with accessible controls.
// Side effects: Owns consent-dialog focus; delegates navigation and microphone controls to the session.

import { useEffect, useId, useRef, useState } from 'react';
import { ArrowRight, Check, Mic, Pause, Play, ShieldCheck, Square, X } from 'lucide-react';
import { Button } from '../../components/ui';
import { durationLabel } from '../../core/domain';
import { useRecordingSession } from './RecordingSession';
import '../../styles/recording-session.css';

// MARK: - No recorder page or microphone request precedes participant consent
export function RecordingConsent() {
  const session = useRecordingSession();
  return session.pending ? (
    <RecordingConsentDialog onCancel={session.cancelConsent} onContinue={session.confirmConsent} />
  ) : null;
}
export function RecordingConsentDialog({
  onCancel,
  onContinue,
}: {
  onCancel: () => void;
  onContinue: (agreed: boolean) => void;
}) {
  const [agreed, setAgreed] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  const title = useId();
  const description = useId();
  const cancel = useRef(onCancel);
  cancel.current = onCancel;
  useEffect(() => {
    const element = dialog.current;
    const previous = document.activeElement as HTMLElement | null;
    if (element && !element.open) element.showModal();
    const escape = (event: Event) => {
      event.preventDefault();
      cancel.current();
    };
    element?.addEventListener('cancel', escape);
    return () => {
      element?.removeEventListener('cancel', escape);
      element?.close();
      previous?.focus();
    };
  }, []);
  return (
    <dialog ref={dialog} className="recording-consent" aria-labelledby={title} aria-describedby={description}>
      <Button
        variant="ghost"
        className="icon-button consent-close"
        onClick={onCancel}
        aria-label="Cancel recording setup"
      >
        <X size={22} />
      </Button>
      <div className="consent-content">
        <span className="consent-symbol" aria-hidden="true">
          <ShieldCheck size={34} />
        </span>
        <p className="consent-kicker">A moment before you begin</p>
        <h1 id={title}>
          Make sure everyone
          <br />
          is comfortable.
        </h1>
        <p id={description} className="consent-description">
          Get your doctor’s consent and permission from everyone present before recording. This applies to
          audio you upload, too.
        </p>
        <label className={`consent-choice${agreed ? ' is-checked' : ''}`}>
          <input type="checkbox" checked={agreed} onChange={(event) => setAgreed(event.target.checked)} />
          <span>My doctor and everyone present agreed to recording.</span>
          {agreed && <Check size={19} aria-hidden="true" />}
        </label>
        <Button disabled={!agreed} onClick={() => onContinue(agreed)}>
          Continue to recording <ArrowRight size={18} />
        </Button>
        <p className="muted small">
          Your microphone stays off until you choose Start recording. While recording, audio is sent for live
          transcription when available.
        </p>
      </div>
    </dialog>
  );
}

// MARK: - The banner follows the workspace, so navigating never unmounts the live recorder
export function RecordingBanner({ onRecordingPage }: { onRecordingPage: boolean }) {
  const session = useRecordingSession();
  const { draft, capture, active, original, reading, saving } = session;
  if (
    !draft ||
    (onRecordingPage && !active && !saving) ||
    (!active && !original && !reading && !session.error)
  )
    return null;
  const label = saving
    ? 'Saving recording'
    : reading
      ? 'Opening audio'
      : capture.state === 'requesting'
        ? 'Waiting for microphone'
        : capture.state === 'recording'
          ? 'Recording in progress'
          : capture.state === 'paused'
            ? 'Recording paused'
            : 'Recording ready to save';
  return (
    <aside
      className={`recording-banner${capture.state === 'recording' ? ' is-recording' : ''}`}
      aria-label="Recording controls"
    >
      <span className="recording-status-dot" aria-hidden="true" />
      <div className="recording-banner-copy">
        <strong role="status">{label}</strong>
        <span>{draft.title}</span>
      </div>
      <span className="recording-banner-time" aria-label="Recorded duration">
        {durationLabel(session.duration)}
      </span>
      <div className="recording-banner-controls">
        {capture.state === 'recording' && (
          <Button
            variant="ghost"
            className="icon-button"
            onClick={capture.pause}
            aria-label="Pause recording"
          >
            <Pause size={17} />
          </Button>
        )}
        {capture.state === 'paused' && (
          <Button
            variant="ghost"
            className="icon-button"
            onClick={capture.resume}
            aria-label="Resume recording"
          >
            <Play size={17} />
          </Button>
        )}
        {(capture.state === 'recording' || capture.state === 'paused') && (
          <Button variant="ghost" className="icon-button" onClick={capture.stop} aria-label="Stop recording">
            <Square size={16} />
          </Button>
        )}
        {original && !active && !reading && (
          <Button variant="secondary" onClick={() => void session.save()} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </Button>
        )}
        <a href="#/recording" className="recording-banner-link" aria-label="Return to recording page">
          <span>{onRecordingPage ? 'Recording' : 'Open recording'}</span>
          <ArrowRight size={17} />
        </a>
      </div>
      {session.error && !onRecordingPage && (
        <p className="recording-banner-error" role="alert">
          {session.error}
        </p>
      )}
    </aside>
  );
}
