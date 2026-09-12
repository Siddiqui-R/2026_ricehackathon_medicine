// Purpose: Review saved audio and timestamped transcripts, then turn reviewed content into visit memory.
// Inputs: A persisted recording, original attachment storage, and configured transcription capability.
// Outputs: Audio playback, faithful segment corrections, separate notes, and links to saved memory records.
// Side effects: Loads original audio; explicit actions transcribe or persist corrections/notes through context.

import { useEffect, useRef, useState, type FormEvent } from 'react';
import { FileText, Pencil, Sparkles } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { demoLabel } from '../../core/presentation';
import type { VisitRecording } from '../../core/models';
import { durationLabel, formatDate } from '../../core/domain';
import { hasRecordingSummary } from '../../core/mutations';
import { Badge, Button, Field, Modal } from '../../components/ui';

// MARK: - Original playback and explicit connected transcription
export function RecordingDetail({ recording, onClose }: { recording: VisitRecording; onClose: () => void }) {
  const { snapshot, providers, transcribeRecording, summarizeRecording, saveMemory, getAttachment, busy } =
    useReva();
  const summaryRequest = useRef<AbortController | null>(null);
  useEffect(() => () => summaryRequest.current?.abort(), []);
  const [audio, setAudio] = useState('');
  const [audioError, setAudioError] = useState('');
  const [editor, setEditor] = useState<'transcript' | 'notes' | null>(null);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState('');
  const hasSummary = hasRecordingSummary(recording);
  const memory = snapshot?.records.find(
    (item) => item.sourceRecordingID === recording.id || item.id === `memory-${recording.id}`,
  );
  function close() {
    summaryRequest.current?.abort();
    onClose();
  }
  useEffect(() => {
    let cancelled = false;
    let objectURL = '';
    setAudio('');
    setAudioError('');
    if (recording.audioFilename && !recording.isSample) {
      void getAttachment(recording.audioFilename)
        .then((blob) => {
          if (cancelled) return;
          objectURL = URL.createObjectURL(blob);
          setAudio(objectURL);
        })
        .catch((failure) => {
          if (!cancelled)
            setAudioError(failure instanceof Error ? failure.message : 'The original audio is unavailable.');
        });
    }
    return () => {
      cancelled = true;
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [getAttachment, recording.audioFilename, recording.isSample]);
  async function act(operation: () => Promise<void>) {
    setError('');
    setWorking(true);
    try {
      await operation();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'This action could not be completed.');
    } finally {
      setWorking(false);
    }
  }
  if (editor === 'transcript')
    return <TranscriptEditor recording={recording} onClose={() => setEditor(null)} />;
  if (editor === 'notes')
    return <RecordingNotesEditor recording={recording} onClose={() => setEditor(null)} />;
  return (
    <Modal title={demoLabel(recording.title, recording.isSample)} onClose={close} wide>
      <div className="stack">
        <div className="row">
          <Badge tone={recording.isSample ? 'review' : 'accent'}>
            {recording.isSample ? 'Sample · no audio' : 'Saved visit audio'}
          </Badge>
          <span className="muted small">
            {formatDate(recording.createdAt, true)} · {durationLabel(recording.duration)}
          </span>
        </div>
        {recording.isSample ? (
          <p className="small">This is a sample conversation, separate from any microphone recording.</p>
        ) : audio ? (
          <audio controls preload="metadata" src={audio}>
            Audio playback is unavailable.
          </audio>
        ) : (
          <p className={audioError ? 'inline-error' : 'muted'}>
            {audioError ||
              (recording.audioFilename
                ? 'Loading original audio…'
                : 'No original audio is attached to this visit memory.')}
          </p>
        )}
        {!recording.isSample && recording.audioFilename && (
          <div className="stack">
            <Button
              variant="secondary"
              disabled={!providers?.transcription.configured || busy || working}
              onClick={() => {
                void act(() => transcribeRecording(recording.id));
              }}
            >
              <Sparkles size={16} />
              {working ? 'Working…' : recording.segments.length ? 'Transcribe again' : 'Transcribe'}
            </Button>
            {!providers?.transcription.configured && (
              <p className="muted small">
                Configure and check your transcription service in{' '}
                <a className="text-link" href="#/settings" onClick={onClose}>
                  Settings
                </a>
                . Your original audio is already saved.
              </p>
            )}
          </div>
        )}
        <section className="stack">
          <div className="section-heading">
            <h3>Appointment summary</h3>
            <Button
              disabled={!recording.segments.length || !providers?.gemini.configured || busy || working}
              onClick={() => {
                const controller = new AbortController();
                summaryRequest.current = controller;
                void act(async () => {
                  try {
                    await summarizeRecording(recording.id, controller.signal);
                  } finally {
                    if (summaryRequest.current === controller) summaryRequest.current = null;
                  }
                });
              }}
            >
              <Sparkles size={16} /> Summarize appointment
            </Button>
          </div>
          {working && summaryRequest.current && (
            <Button variant="secondary" onClick={() => summaryRequest.current?.abort()}>
              Cancel summarization
            </Button>
          )}
          {hasSummary ? (
            <>
              <p className="prose">{recording.aiSummary}</p>
              <p className="muted small">
                AI summary{recording.aiSummaryModel ? ` · ${recording.aiSummaryModel}` : ''}
                {recording.aiSummaryGeneratedAt
                  ? ` · ${formatDate(recording.aiSummaryGeneratedAt, true)}`
                  : ''}
                . Review it against the transcript and original audio. It may contain mistakes.
              </p>
            </>
          ) : (
            <p className="muted small">
              {recording.segments.length
                ? 'Summarize the saved transcript to review what was discussed. Your personal notes stay separate.'
                : 'Transcribe the appointment first. The summary is generated only from the saved transcript.'}
            </p>
          )}
          {!providers?.gemini.configured && (
            <p className="muted small">
              Check your AI service in{' '}
              <a className="text-link" href="#/settings" onClick={close}>
                Settings
              </a>{' '}
              to enable summaries.
            </p>
          )}
        </section>
        <section className="stack">
          <div className="section-heading">
            <h3>Transcript</h3>
            {recording.segments.length > 0 && (
              <Button variant="ghost" onClick={() => setEditor('transcript')} disabled={working || busy}>
                <Pencil size={15} /> Correct words
              </Button>
            )}
          </div>
          {recording.transcriptionModel && (
            <p className="muted small">
              Generated by {recording.transcriptionModel}. Review the words and speaker labels before using
              the transcript.
            </p>
          )}
          {recording.segments.length ? (
            <div className="transcript-segments stack">
              {recording.segments.map((segment) => (
                <div key={segment.id} className="transcript-segment">
                  <p className="small muted">
                    {durationLabel(segment.start)}–{durationLabel(segment.end)} ·{' '}
                    {demoLabel(segment.speaker, recording.isSample)}
                  </p>
                  <p className="prose">{segment.text}</p>
                </div>
              ))}
            </div>
          ) : (
            <p className="muted">No transcript has been generated for this audio.</p>
          )}
        </section>
        <section>
          <div className="section-heading">
            <h3>My visit notes</h3>
            <Button variant="ghost" onClick={() => setEditor('notes')} disabled={working || busy}>
              <Pencil size={15} /> Edit notes
            </Button>
          </div>
          <p className="prose">{recording.summary || 'Add what you want to remember from this visit.'}</p>
          <p className="muted small">Your notes are kept separately from transcript corrections.</p>
        </section>
        {error && (
          <p className="inline-error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          {memory && (
            <a className="text-link" href={`#/records/${encodeURIComponent(memory.id)}`} onClick={onClose}>
              <FileText size={16} /> Open saved memory
            </a>
          )}
          <Button
            disabled={working || busy || (!recording.segments.length && !recording.summary.trim())}
            onClick={() => {
              void act(() => saveMemory(recording.id));
            }}
          >
            {memory ? 'Update saved memory' : 'Save memory to Records'}
          </Button>
        </div>
      </div>
    </Modal>
  );
}

// MARK: - Correct words while retaining segment identity, speaker, and original timing
function TranscriptEditor({ recording, onClose }: { recording: VisitRecording; onClose: () => void }) {
  const { snapshot, saveMemory } = useReva();
  const [original] = useState(() => JSON.stringify(recording.segments));
  const [texts, setTexts] = useState(() =>
    Object.fromEntries(recording.segments.map((segment) => [segment.id, segment.text])),
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  async function save(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError('');
    try {
      const latest = snapshot?.recordings.find((item) => item.id === recording.id);
      if (!latest || JSON.stringify(latest.segments) !== original)
        throw new Error(
          'The transcript changed while this editor was open. Reopen it before correcting the words.',
        );
      if (
        Object.values(texts).some((value) => !value.trim() || value.length > 20000) ||
        Object.values(texts).join('').length > 200000
      )
        throw new Error(
          'Keep every segment nonempty and under 20,000 characters, with at most 200,000 characters overall.',
        );
      await saveMemory(recording.id, texts, original);
      onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Corrections could not be saved.');
    } finally {
      setSaving(false);
    }
  }
  return (
    <Modal title="Correct transcript words" onClose={onClose} wide>
      <form className="stack" onSubmit={save}>
        <p className="muted small">
          Correct the words you hear. Segment times, speakers, original audio, and your separate notes stay
          unchanged. Any existing saved memory is updated.
        </p>
        {recording.segments.map((segment) => (
          <Field
            key={segment.id}
            label={`${durationLabel(segment.start)}–${durationLabel(segment.end)} · ${demoLabel(segment.speaker, recording.isSample)}`}
          >
            <textarea
              rows={3}
              required
              maxLength={20000}
              value={texts[segment.id] ?? ''}
              onChange={(event) =>
                setTexts((previous) => ({ ...previous, [segment.id]: event.target.value }))
              }
            />
          </Field>
        ))}
        {error && (
          <p className="inline-error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <Button type="button" variant="secondary" disabled={saving} onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={saving}>
            {saving ? 'Saving…' : 'Save corrections'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

// MARK: - User notes are saved independently of provider transcripts
function RecordingNotesEditor({ recording, onClose }: { recording: VisitRecording; onClose: () => void }) {
  const { mutate } = useReva();
  const [notes, setNotes] = useState(recording.summary);
  const [original] = useState(recording.summary);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  async function save(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError('');
    try {
      await mutate((draft) => {
        const latest = draft.recordings.find((item) => item.id === recording.id);
        if (!latest) throw new Error('This recording is no longer available.');
        if (latest.summary !== original)
          throw new Error(
            'These notes changed while the editor was open. Reopen it to review the latest version.',
          );
        latest.summary = notes;
      });
      onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Notes could not be saved.');
    } finally {
      setSaving(false);
    }
  }
  return (
    <Modal title="My visit notes" onClose={onClose}>
      <form className="stack" onSubmit={save}>
        <Field
          label="What would you like to remember?"
          hint="These notes remain separate from the transcript. Use Update saved memory when you want to copy them to Records."
        >
          <textarea
            rows={8}
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
          <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button type="submit" disabled={saving}>
            {saving ? 'Saving…' : 'Save notes'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
