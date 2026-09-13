// Purpose: Review saved audio and timestamped transcripts, then turn reviewed content into visit memory.
// Inputs: A persisted recording, original attachment storage, and configured transcription capability.
// Outputs: Audio playback, faithful segment corrections, separate notes, and links to saved memory records.
// Side effects: Loads original audio; saves corrections/notes and delegates optional reprocessing to the background queue.

import { recordingDateLabel } from '../../core/recordingDates';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { FileText, Pencil, RotateCcw } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { useRecordingProcessing } from '../../core/RecordingProcessingUpdates';
import { demoDescription, demoLabel, demoSourceText } from '../../core/presentation';
import type { VisitRecording } from '../../core/models';
import { durationLabel, formatDate } from '../../core/domain';
import { hasRecordingSummary } from '../../core/mutations';
import { Badge, Button, Field, Modal } from '../../components/ui';
import { SourceLink } from '../../components/SourceLink';

// MARK: - Original playback and automatic processing progress
export function RecordingDetail({
  recording,
  onClose,
  embedded = false,
}: {
  recording: VisitRecording;
  onClose: () => void;
  embedded?: boolean;
}) {
  const { snapshot, getAttachment, busy } = useReva();
  const processing = useRecordingProcessing();
  const job = processing.jobs.find((item) => item.id === recording.id);
  const processingStage =
    job?.stage ??
    (recording.status === 'processing-queued'
      ? 'queued'
      : ['processing-transcribing', 'processing-retranscribing'].includes(recording.status)
        ? 'transcribing'
        : recording.status === 'processing-analyzing'
          ? 'analyzing'
          : ['processing-failed', 'processing-reprocess-failed'].includes(recording.status)
            ? 'failed'
            : recording.status === 'processing-complete'
              ? 'complete'
              : null);
  const automaticWork = ['queued', 'transcribing', 'analyzing', 'waiting'].includes(processingStage ?? '');
  const transcript = useRef<HTMLElement>(null);
  const audioPlayer = useRef<HTMLAudioElement>(null);
  const [audio, setAudio] = useState('');
  const [audioError, setAudioError] = useState('');
  const [editor, setEditor] = useState<'transcript' | 'notes' | null>(null);
  const hasSummary = hasRecordingSummary(recording);
  const memory = snapshot?.records.find(
    (item) => item.sourceRecordingID === recording.id || item.id === `memory-${recording.id}`,
  );
  function close() {
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
  if (editor === 'transcript' && !automaticWork)
    return <TranscriptEditor recording={recording} onClose={() => setEditor(null)} />;
  if (editor === 'notes' && !automaticWork)
    return <RecordingNotesEditor recording={recording} onClose={() => setEditor(null)} />;
  const content = (
    <div className="stack">
      <div className="row">
        <Badge tone={recording.isSample ? 'review' : 'accent'}>
          {recording.isSample ? 'Transcript only · no audio' : 'Saved visit audio'}
        </Badge>
        <span className="muted small">
          {recordingDateLabel(recording, true)} · {durationLabel(recording.duration)}
        </span>
      </div>
      {processingStage && (
        <div className="recording-page-notice stack" role={processingStage === 'failed' ? 'alert' : 'status'}>
          <strong>
            {processingStage === 'queued'
              ? 'Recording queued'
              : processingStage === 'transcribing'
                ? 'Transcribing your recording'
                : processingStage === 'analyzing'
                  ? 'Analyzing your conversation'
                  : processingStage === 'waiting'
                    ? 'Recording saved · waiting to continue'
                    : processingStage === 'failed'
                      ? 'Recording saved · processing needs attention'
                      : 'Transcript and analysis ready'}
          </strong>
          <p>
            {job?.message ??
              (processingStage === 'complete'
                ? 'Review the transcript and summary below against your original audio.'
                : processingStage === 'failed'
                  ? 'Your original audio is safe. Retry transcription and analysis when you’re ready.'
                  : 'You can keep browsing your workspace. This will continue in the background.')}
          </p>
          {(processingStage === 'failed' || job?.canRetry) && (
            <Button variant="secondary" disabled={busy} onClick={() => processing.retry(recording.id)}>
              Retry processing
            </Button>
          )}
          {processingStage === 'waiting' && !job?.retryAt && !job?.canRetry && (
            <a className="text-link" href="#/settings" onClick={close}>
              View connection settings
            </a>
          )}
        </div>
      )}
      {recording.isSample ? (
        <p className="small">No audio is attached to this transcript.</p>
      ) : audio ? (
        <audio ref={audioPlayer} controls preload="metadata" src={audio}>
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
      <section className="stack">
        <h3>Appointment summary</h3>
        {hasSummary ? (
          <>
            {recording.aiSummary
              ?.split(/\r?\n+/)
              .filter(Boolean)
              .map((line, index) => (
                <p className="prose" key={index}>
                  {line}
                  {recording.segments.length > 0 && (
                    <SourceLink
                      label="View source: saved transcript"
                      onOpen={() => {
                        transcript.current?.scrollIntoView({ block: 'start' });
                        transcript.current?.focus({ preventScroll: true });
                      }}
                    />
                  )}
                </p>
              ))}
            <p className="muted small">
              AI summary{recording.aiSummaryModel ? ` · ${recording.aiSummaryModel}` : ''}
              {recording.aiSummaryGeneratedAt ? ` · ${formatDate(recording.aiSummaryGeneratedAt, true)}` : ''}
              . Review it against the transcript and original audio. It may contain mistakes.
            </p>
          </>
        ) : (
          <p className="muted small">
            {recording.isSample
              ? 'This transcript has no generated appointment summary.'
              : processingStage === 'failed'
                ? 'Your saved audio and completed steps are kept while processing needs attention.'
                : 'Your appointment summary is prepared automatically from the saved audio and will appear here when ready.'}
          </p>
        )}
      </section>
      <section className="stack" ref={transcript} tabIndex={-1} aria-label="Saved transcript">
        <div className="section-heading">
          <h3>Transcript</h3>
          {recording.segments.length > 0 && (
            <Button variant="ghost" onClick={() => setEditor('transcript')} disabled={busy || automaticWork}>
              <Pencil size={15} /> Correct words
            </Button>
          )}
        </div>
        {recording.transcriptionModel && (
          <p className="muted small">
            Generated by {recording.transcriptionModel}. Review the words and speaker labels before using the
            transcript.
          </p>
        )}
        {recording.segments.length ? (
          <div className="transcript-segments stack">
            {recording.segments
              .filter((segment) => demoSourceText(segment.text, recording.isSample))
              .map((segment) => (
                <div key={segment.id} className="transcript-segment">
                  <p className="small muted">
                    {durationLabel(segment.start)}–{durationLabel(segment.end)} ·{' '}
                    {demoLabel(segment.speaker, recording.isSample)}
                  </p>
                  <p className="prose">
                    {demoSourceText(segment.text, recording.isSample)}
                    {audio && (
                      <SourceLink
                        label={`Listen to original audio at ${durationLabel(segment.start)}`}
                        onOpen={() => {
                          if (audioPlayer.current) {
                            audioPlayer.current.currentTime = segment.start;
                            audioPlayer.current.scrollIntoView({ block: 'center' });
                            audioPlayer.current.focus({ preventScroll: true });
                            void audioPlayer.current.play().catch(() => {
                              setAudioError(
                                'Use the audio player to play this part of the original recording.',
                              );
                            });
                          }
                        }}
                      />
                    )}
                  </p>
                </div>
              ))}
          </div>
        ) : (
          <p className="muted">
            {automaticWork
              ? 'Your transcript will appear here when it is ready.'
              : 'The transcript from your saved audio will appear here when processing finishes.'}
          </p>
        )}
      </section>
      <section>
        <div className="section-heading">
          <h3>My visit notes</h3>
          <Button variant="ghost" onClick={() => setEditor('notes')} disabled={busy || automaticWork}>
            <Pencil size={15} /> Edit notes
          </Button>
        </div>
        <p className="prose">
          {demoDescription(recording.summary, recording.isSample) ||
            'Add what you want to remember from this visit.'}
        </p>
        <p className="muted small">Your notes are kept separately from transcript corrections.</p>
      </section>
      <div className="form-actions">
        {memory && (
          <a className="text-link" href={`#/records/${encodeURIComponent(memory.id)}`} onClick={onClose}>
            <FileText size={16} /> Open saved memory
          </a>
        )}
      </div>
      {!recording.isSample && recording.audioFilename && !automaticWork && processingStage !== 'failed' && (
        <details className="source-disclosure">
          <summary>Processing options</summary>
          <p className="muted small">Rebuild the transcript and summary from the original audio.</p>
          <Button variant="secondary" disabled={busy} onClick={() => processing.reprocess(recording.id)}>
            <RotateCcw size={16} /> Reprocess recording
          </Button>
        </details>
      )}
    </div>
  );
  return embedded ? (
    content
  ) : (
    <Modal title={demoLabel(recording.title, recording.isSample)} onClose={close} wide>
      {content}
    </Modal>
  );
}

// MARK: - Correct words while retaining segment identity, speaker, and original timing
function TranscriptEditor({ recording, onClose }: { recording: VisitRecording; onClose: () => void }) {
  const { snapshot, saveMemory } = useReva();
  const processing = useRecordingProcessing();
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
      if (!recording.isSample && recording.audioFilename) processing.retry(recording.id);
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
        {recording.segments
          .filter((segment) => demoSourceText(segment.text, recording.isSample))
          .map((segment) => (
            <Field
              key={segment.id}
              label={`${durationLabel(segment.start)}–${durationLabel(segment.end)} · ${demoLabel(segment.speaker, recording.isSample)}`}
            >
              <textarea
                rows={3}
                required
                maxLength={20000}
                value={demoSourceText(texts[segment.id] ?? '', recording.isSample)}
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
          hint="These notes stay with this recording, separate from the transcript and its generated summary."
        >
          <textarea
            rows={8}
            maxLength={20000}
            value={demoDescription(notes, recording.isSample)}
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
