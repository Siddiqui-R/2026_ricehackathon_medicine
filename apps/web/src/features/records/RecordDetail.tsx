// Purpose: Make a source readable, editable, and traceable to its original document or visit transcript.
// Inputs: A record ID, optional hash evidence page, and local/provider state from Reva context.
// Outputs: Structured source details, review status, and explicit edit/delete/summarize actions.
// Side effects: Opens local originals and delegates confirmed mutations or provider calls to context.

import { useEffect, useState } from 'react';
import { ArrowLeft, CalendarDays, FileText, Pencil, Sparkles, Trash2 } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { demoDescription, demoLabel } from '../../core/presentation';
import {
  formatDate,
  currentSummary,
  localExcerptDetails,
  excerptOmissionNotice,
  hasAuthoredDemoSummary,
} from '../../core/domain';
import type { SymptomEntry } from '../../core/models';
import { Badge, Button, Card, EmptyState, Modal, PageHeading } from '../../components/ui';
import { RecordEditor } from './RecordEditor';
import { SymptomDialog } from './SymptomDialog';
import { SourcePreview } from './SourcePreview';
import { queryParameter, RecordSymbol } from './recordPresentation';

// MARK: - Exact self-reported fields remain distinct from optional AI interpretation
function SymptomDetails({ entry }: { entry: SymptomEntry }) {
  const fields = [
    ['Severity', entry.severity ? entry.severity[0].toUpperCase() + entry.severity.slice(1) : ''],
    ['Duration', entry.duration],
    ['Details', entry.details],
    ['Possible triggers', entry.triggers],
    ['What helped', entry.whatHelped],
  ];
  return (
    <Card className="stack">
      <div className="section-heading">
        <h2>Your observation</h2>
        <Badge tone="accent">Self-reported</Badge>
      </div>
      <div>
        <h3>When it happened</h3>
        <p>{formatDate(entry.observedAt, true, entry.timeZone)}</p>
        <p className="muted small">{entry.timeZone}</p>
      </div>
      {fields
        .filter(([, value]) => value)
        .map(([label, value]) => (
          <div key={label}>
            <h3>{label}</h3>
            <p className="prose">{value}</p>
          </div>
        ))}
    </Card>
  );
}

// MARK: - Detail navigation and explicit side-effect boundaries
export function RecordDetail({ id }: { id: string }) {
  const { snapshot, deleteRecord, summarizeRecord, connectedAI, busy, notify } = useReva();
  const record = snapshot?.records.find((item) => item.id === id);
  const [editing, setEditing] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [preview, setPreview] = useState(() => queryParameter('page') !== null);
  const [page, setPage] = useState(() => Math.max(1, Number(queryParameter('page')) || 1));
  const [error, setError] = useState('');
  useEffect(() => {
    setEditing(false);
    setDeleting(false);
    setError('');
    setPage(Math.max(1, Number(queryParameter('page')) || 1));
    setPreview(queryParameter('page') !== null);
  }, [id]);
  useEffect(() => {
    const update = () => {
      const requested = queryParameter('page');
      if (requested !== null) {
        setPage(Math.max(1, Number(requested) || 1));
        setPreview(true);
      }
    };
    window.addEventListener('hashchange', update);
    return () => window.removeEventListener('hashchange', update);
  }, []);
  if (!record)
    return (
      <Card>
        <EmptyState title="This record is no longer available">
          <p>It may have been deleted. Refresh an older visit brief to update its sources.</p>
          <a className="text-link" href="#/records">
            Back to Records
          </a>
        </EmptyState>
      </Card>
    );
  const authoredDemo = hasAuthoredDemoSummary(record);
  const linkedRecording = record.sourceRecordingID
    ? snapshot?.recordings.find((item) => item.id === record.sourceRecordingID)
    : undefined;
  const remove = async () => {
    setRemoving(true);
    setError('');
    try {
      await deleteRecord(id);
      notify('Record removed from your active history.');
      location.hash = '/records';
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'The record could not be deleted.');
    } finally {
      setRemoving(false);
    }
  };
  return (
    <div className="stack">
      <a className="text-link breadcrumb" href="#/records">
        <ArrowLeft size={17} /> All records
      </a>
      <PageHeading
        eyebrow={record.kind}
        title={demoLabel(record.title, record.isDemo)}
        description={`${demoLabel(record.provider, record.isDemo)} · ${formatDate(record.date)}`}
        actions={
          <Button variant="secondary" onClick={() => setEditing(true)}>
            <Pencil size={18} />
            {record.symptomEntry ? 'Edit entry' : 'Edit record'}
          </Button>
        }
      />
      <div className="row chip-list">
        <span className="record-icon">
          <RecordSymbol record={record} />
        </span>
        <Badge tone={record.status === 'needsReview' ? 'review' : 'accent'}>
          {record.status === 'needsReview' ? 'Needs review' : 'Saved record'}
        </Badge>
        <span className="small muted">Source version {record.version}</span>
      </div>
      {record.status === 'needsReview' && (
        <div className="extraction-notices">
          <strong>Check the original before using these details</strong>
          <p>
            Some text or dates need confirmation. You can correct the wording and mark it reviewed in Edit
            record.
          </p>
        </div>
      )}
      <div className="detail-grid">
        <div className="stack">
          {record.symptomEntry ? (
            <SymptomDetails entry={record.symptomEntry} />
          ) : (
            <Card className="stack">
              <h2>{record.summaryModel ? 'AI summary' : authoredDemo ? 'Demo summary' : 'Local excerpt'}</h2>
              <p className="prose">
                {(authoredDemo ? demoDescription(currentSummary(record), true) : currentSummary(record)) ||
                  'No complete source line fits in this excerpt. Open the source to review its text.'}
              </p>
              {!record.summaryModel &&
                !authoredDemo &&
                localExcerptDetails(record.text, record.isDemo).omitted && (
                  <p className="small muted">{excerptOmissionNotice}</p>
                )}
              <p className="small muted">
                {record.summaryModel
                  ? `Generated by ${record.summaryModel}. Review it against the original source.`
                  : authoredDemo
                    ? 'Authored from source material for this demonstration.'
                    : 'An excerpt of source wording prepared on this device.'}
              </p>
            </Card>
          )}
          {record.symptomEntry && record.summaryModel && (
            <Card>
              <h2>AI summary · review</h2>
              <p className="prose">{record.summary}</p>
              <p className="small muted">{record.summaryModel}</p>
            </Card>
          )}
          <Card>
            <details>
              <summary>
                {record.symptomEntry ? 'Entry text used in visit preparation' : 'Full source text'}
              </summary>
              <p className="prose source-text">{record.text || 'No readable text is saved yet.'}</p>
            </details>
          </Card>
          {record.notes && (
            <Card>
              <h2>Notes and extraction details</h2>
              <p className="prose">{demoDescription(record.notes, record.isDemo)}</p>
            </Card>
          )}
        </div>
        <aside className="stack">
          <Card className="stack">
            <h2>Source details</h2>
            <div className="row">
              <CalendarDays size={18} />
              <span>{formatDate(record.date)}</span>
            </div>
            <dl className="source-metadata">
              <dt>Added</dt>
              <dd>{formatDate(record.uploadedAt, true)}</dd>
              <dt>Type</dt>
              <dd>{record.kind}</dd>
              {record.sourceFilename && (
                <>
                  <dt>Original</dt>
                  <dd>
                    {record.pageCount} {record.pageCount === 1 ? 'page' : 'pages'}
                  </dd>
                </>
              )}
            </dl>
            {record.sourceFilename && (
              <Button
                onClick={() => {
                  setPage(1);
                  setPreview(true);
                }}
              >
                <FileText size={18} /> Open original
              </Button>
            )}
            {linkedRecording ? (
              <a className="text-link" href={`#/visits/${encodeURIComponent(linkedRecording.visitID)}`}>
                Open the source visit transcript
              </a>
            ) : (
              record.sourceRecordingID && (
                <p className="small muted">
                  The originating transcript is no longer available. This memory retains its saved wording.
                </p>
              )
            )}
            {record.tags.length > 0 && (
              <div className="chip-list">
                {record.tags.map((tag) => (
                  <Badge key={tag}>{tag}</Badge>
                ))}
              </div>
            )}
          </Card>
          {connectedAI && (
            <Card className="stack">
              <h2>Connected summary</h2>
              <p className="small muted">
                Send this record's source text to your configured Gemini service for a reviewable summary.
              </p>
              <Button
                variant="secondary"
                disabled={busy || !record.text.trim()}
                onClick={() => {
                  setError('');
                  void summarizeRecord(id).catch((reason) =>
                    setError(
                      reason instanceof Error ? reason.message : 'The summary could not be generated.',
                    ),
                  );
                }}
              >
                <Sparkles size={18} />
                {busy ? 'Working…' : 'Summarize with Gemini'}
              </Button>
            </Card>
          )}
          <Button variant="danger" onClick={() => setDeleting(true)}>
            <Trash2 size={17} />
            {record.symptomEntry ? 'Delete entry' : 'Delete record'}
          </Button>
        </aside>
      </div>
      {error && !deleting && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
      {editing &&
        (record.symptomEntry ? (
          <SymptomDialog record={record} onClose={() => setEditing(false)} />
        ) : (
          <RecordEditor record={record} onClose={() => setEditing(false)} />
        ))}
      {preview && record.sourceFilename && (
        <SourcePreview record={record} page={page} onClose={() => setPreview(false)} />
      )}
      {deleting && (
        <Modal
          title={record.symptomEntry ? 'Delete this symptom entry?' : 'Delete this record?'}
          onClose={() => {
            if (!removing) setDeleting(false);
          }}
        >
          <div className="stack">
            <p>
              <strong>{record.title}</strong> will leave your active history. Existing visit briefs will need
              refreshing. Original files and a previous-state backup may remain in browser storage for
              recovery.
            </p>
            {error && (
              <p className="inline-error" role="alert">
                {error}
              </p>
            )}
            <div className="form-actions">
              <Button variant="secondary" disabled={removing} onClick={() => setDeleting(false)}>
                Keep record
              </Button>
              <Button variant="danger" disabled={removing} onClick={() => void remove()}>
                {removing ? 'Deleting…' : 'Delete record'}
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
