// Purpose: Keep a single consented recording draft alive across workspace navigation.
// Inputs: Explicit consent, recording controls, title/notes edits and uploaded original audio.
// Outputs: Shared draft state and an atomic audio save queued for background transcription and analysis.
// Side effects: Owns microphone lifecycle; guards unsaved browser exits and saves originals through Reva.

import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { useReva } from '../../core/RevaContext';
import { nowISO, uid } from '../../core/domain';
import type { Visit, VisitRecording } from '../../core/models';
import { recordingDateTitle } from '../../core/recordingDates';
import { audioExtension, MAX_AUDIO_BYTES, useVisitRecorder } from './useVisitRecorder';
import { inspectAudio, type UploadedAudio } from './recordingAudio';
import { RevaAPI } from '../../core/api';
import { useLiveTranscription } from './useLiveTranscription';

interface RecordingDraft {
  id: string;
  visit?: Visit;
  returnHash: string;
  title: string;
  notes: string;
  mode: 'microphone' | 'upload';
  consented: true;
}
interface PendingSession {
  visit?: Visit;
  returnHash: string;
}

// MARK: - The provider is mounted outside the route switch, so screens never own the microphone
export function useRecordingSessionDraft() {
  const { snapshot, saveRecording, notify, token, providers } = useReva();
  const live = useLiveTranscription(async (signal) => {
    if (!providers?.realtimeTranscription?.configured) throw new Error('Live transcription is unavailable.');
    return new RevaAPI(token).realtimeTranscriptionToken(signal);
  });
  const capture = useVisitRecorder(live);
  const [draft, setDraft] = useState<RecordingDraft | null>(null);
  const [pending, setPending] = useState<PendingSession | null>(null);
  const [upload, setUpload] = useState<UploadedAudio | null>(null);
  const [reading, setReading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const lock = useRef(false);
  const starting = useRef(false);
  const version = useRef(0);
  const alive = useRef(true);
  const original = upload?.blob ?? capture.blob;
  const duration = upload?.duration ?? capture.seconds;
  const active = ['requesting', 'recording', 'paused'].includes(capture.state);
  const detachedVisit = Boolean(
    draft?.visit && !snapshot?.visits.some((visit) => visit.id === draft.visit?.id),
  );
  const hasUnsaved = Boolean(
    draft && (active || original || reading || saving || draft.title.trim() || draft.notes.trim()),
  );
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      version.current += 1;
    };
  }, []);
  useEffect(() => {
    if (!hasUnsaved) return;
    const beforeLeave = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', beforeLeave);
    return () => window.removeEventListener('beforeunload', beforeLeave);
  }, [hasUnsaved]);

  function openPage() {
    window.location.hash = '#/recording';
  }
  function requestSession(visit?: Visit) {
    if (draft) {
      openPage();
      return;
    }
    if (pending) return;
    const current = window.location.hash;
    setPending({
      visit,
      returnHash: current.split('?')[0] === '#/recording' ? '#/summary' : current || '#/summary',
    });
  }
  function cancelConsent() {
    if (window.location.hash.split('?')[0] === '#/recording')
      window.location.hash = pending?.returnHash ?? '#/summary';
    setPending(null);
  }
  function confirmConsent(agreed: boolean) {
    if (!agreed || !pending || draft) return;
    setDraft({
      ...pending,
      id: uid(),
      title: '',
      notes: '',
      mode: 'microphone',
      consented: true,
    });
    setPending(null);
    setError('');
    openPage();
  }
  function updateDraft(update: Partial<Pick<RecordingDraft, 'title' | 'notes'>>) {
    if (lock.current) return;
    setDraft((value) => value && { ...value, ...update });
  }
  function setMode(mode: RecordingDraft['mode']) {
    if (active || original || lock.current) return;
    setError('');
    setDraft((value) => value && { ...value, mode });
  }
  async function start() {
    if (!draft?.consented || original || lock.current || starting.current || active) return;
    starting.current = true;
    setError('');
    try {
      await capture.start();
    } finally {
      starting.current = false;
    }
  }
  async function chooseAudio(file: File) {
    if (!draft?.consented || active || original || lock.current || starting.current) return;
    const attempt = version.current;
    lock.current = true;
    setReading(true);
    setError('');
    try {
      const selected = await inspectAudio(file);
      if (!alive.current || attempt !== version.current) return;
      setUpload(selected);
    } catch (failure) {
      if (alive.current && attempt === version.current)
        setError(failure instanceof Error ? failure.message : 'This audio could not be opened.');
    } finally {
      if (alive.current && attempt === version.current) {
        lock.current = false;
        setReading(false);
      }
    }
  }
  function clearDraft() {
    version.current += 1;
    capture.reset();
    setDraft(null);
    setUpload(null);
    setError('');
  }
  function discard() {
    if (lock.current) return;
    if (hasUnsaved && !window.confirm('Discard this unsaved recording and its notes?')) return;
    const returnHash = draft?.returnHash ?? '#/summary';
    clearDraft();
    if (window.location.hash.split('?')[0] === '#/recording') window.location.hash = returnHash;
  }
  // Sign-out must be blocked before account credentials are revoked, rather than at the final navigation.
  function allowWorkspaceExit() {
    if (lock.current) {
      openPage();
      return false;
    }
    if (hasUnsaved && !window.confirm('Leave this workspace and discard your unsaved recording?'))
      return false;
    clearDraft();
    return true;
  }
  async function save() {
    if (!draft?.consented || !original || active || lock.current) return;
    lock.current = true;
    setSaving(true);
    setError('');
    try {
      if (!Number.isFinite(duration) || duration <= 0)
        throw new Error('This recording has no captured audio duration.');
      if (!original.size || original.size > MAX_AUDIO_BYTES)
        throw new Error('Audio must be nonempty and no larger than 16 MiB.');
      const savedAt = nowISO();
      const capturedAt = upload ? undefined : (capture.startedAt ?? undefined);
      const recording: VisitRecording = {
        id: draft.id,
        visitID: detachedVisit ? '' : (draft.visit?.id ?? ''),
        title: draft.title.trim() || recordingDateTitle(capturedAt ?? savedAt),
        titleSource: draft.title.trim() ? 'user' : 'date',
        createdAt: capturedAt ?? savedAt,
        capturedAt,
        savedAt,
        duration,
        audioFilename: `reva-audio-${draft.id}.${upload?.extension ?? audioExtension(original.type)}`,
        // The live preview is provisional and may omit short/final speech. Always process the
        // saved original automatically, even when preview text looks complete.
        segments: [],
        summary: draft.notes.trim(),
        isSample: false,
        status: 'processing-queued',
      };
      await saveRecording(recording, original);
      if (!alive.current) return;
      clearDraft();
      notify(
        detachedVisit
          ? 'Recording saved as a standalone session because the linked visit was removed. Transcription and analysis are queued.'
          : 'Recording saved. Transcription and analysis will continue in the background.',
      );
      window.location.hash = detachedVisit ? '#/summary' : draft.returnHash;
    } catch (failure) {
      if (alive.current)
        setError(
          failure instanceof Error
            ? failure.message
            : 'Your audio could not be saved. Your draft is still here; try again.',
        );
    } finally {
      lock.current = false;
      if (alive.current) setSaving(false);
    }
  }
  return {
    draft,
    pending,
    capture,
    liveTranscript: live.transcript,
    upload,
    original,
    duration,
    active,
    hasUnsaved,
    detachedVisit,
    reading,
    saving,
    error,
    requestSession,
    cancelConsent,
    confirmConsent,
    updateDraft,
    setMode,
    start,
    chooseAudio,
    save,
    discard,
    allowWorkspaceExit,
  };
}

const RecordingSessionContext = createContext<ReturnType<typeof useRecordingSessionDraft> | null>(null);
export function RecordingSessionProvider({ children }: { children: ReactNode }) {
  const session = useRecordingSessionDraft();
  return <RecordingSessionContext.Provider value={session}>{children}</RecordingSessionContext.Provider>;
}
export function useRecordingSession() {
  const session = useContext(RecordingSessionContext);
  if (!session) throw new Error('Recording controls must be inside the workspace recording provider.');
  return session;
}
