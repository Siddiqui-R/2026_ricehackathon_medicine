// Purpose: Present source-linked preparation and preserve user-owned questions and notes.
// Inputs: One visit, its saved report, current source records, and provider capabilities.
// Outputs: Reviewable brief content, source navigation, and a guarded browser print document.
// Side effects: Explicitly generates reports, saves edits through context, and opens browser printing.

import { useEffect, useRef, useState, type FormEvent } from 'react';
import { FileText, Pencil, Printer, RefreshCw, Sparkles } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import type { ReportSection, Visit } from '../../core/models';
import { formatDate, reportIsStale } from '../../core/domain';
import { Badge, Button, Card, EmptyState, Field, Modal } from '../../components/ui';

// MARK: - Suppress only a body already displayed verbatim by its source quotations
function sectionBodyRepeatsSourceQuotes(section: ReportSection): boolean {
  const normalized = (text: string) => text.trim().replace(/\s+/gu, ' ');
  const body = normalized(section.body);
  if (!body || !section.sources.length) return false;
  return (
    section.sources.some((source) => normalized(source.excerpt) === body) ||
    normalized(section.sources.map((source) => source.excerpt).join('\n\n')) === body
  );
}

// MARK: - Source freshness and explicit generation
export function VisitBrief({ visit }: { visit: Visit }) {
  const { snapshot, prepareVisit, connectedAI, providers, busy, reportError } = useReva();
  const [stale, setStale] = useState(true);
  const [checking, setChecking] = useState(true);
  const [editing, setEditing] = useState(false);
  const [working, setWorking] = useState(false);
  const current = useRef({ visit, records: snapshot?.records ?? [] });
  current.current = { visit, records: snapshot?.records ?? [] };
  useEffect(() => {
    let cancelled = false;
    setChecking(true);
    setStale(true);
    void reportIsStale(visit, snapshot?.records ?? [])
      .then((value) => {
        if (!cancelled) {
          setStale(value);
          setChecking(false);
        }
      })
      .catch((failure) => {
        if (!cancelled) {
          setChecking(false);
          reportError(failure);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [visit, snapshot?.records, reportError]);
  async function generate() {
    setWorking(true);
    try {
      await prepareVisit(visit.id);
    } catch {
      /* Context displays the failure; existing brief remains. */
    } finally {
      setWorking(false);
    }
  }
  async function print() {
    setWorking(true);
    try {
      const original = current.current;
      const fingerprint = JSON.stringify(original);
      if (!original.visit.report || (await reportIsStale(original.visit, original.records)))
        throw new Error(
          'Update your visit brief before printing so its sources reflect your latest records.',
        );
      if (fingerprint !== JSON.stringify(current.current))
        throw new Error('Your visit or records changed. Review the updated brief before printing.');
      window.print();
    } catch (failure) {
      reportError(failure);
    } finally {
      setWorking(false);
    }
  }
  const aiEnabled = connectedAI && providers?.gemini.configured;
  const report = visit.report;

  // MARK: - Brief-only print surface and exact original quotations
  return (
    <Card className="brief-card">
      <div className="section-heading no-print">
        <div>
          <p className="eyebrow">Before your appointment</p>
          <h2>Visit brief</h2>
        </div>
        <div className="row">
          {report && (
            <Button variant="secondary" onClick={print} disabled={busy || working || checking || stale}>
              <Printer size={16} /> Print / save PDF
            </Button>
          )}
          <Button onClick={generate} disabled={busy || working}>
            {report ? <RefreshCw size={16} /> : <Sparkles size={16} />}
            {working ? 'Working…' : report ? 'Update brief' : 'Prepare my visit'}
          </Button>
        </div>
      </div>
      <p className="muted small no-print">
        {aiEnabled
          ? 'Connected AI selects relevant records; citations retain the original source words.'
          : 'Prepared locally from your records. Enable connected AI in Settings when your service is configured.'}
      </p>
      {report && stale && !checking && (
        <p className="inline-error no-print" role="status">
          Your visit or source records have changed. Update the brief before using or printing it.
        </p>
      )}
      {!report ? (
        <EmptyState title="Make every appointment count">
          <p>
            Reva brings together relevant history, original source references, and the questions you want
            answered.
          </p>
        </EmptyState>
      ) : (
        <article
          className="visit-report stack"
          data-print-ready={!stale && !checking}
          aria-label="Pre-visit report"
        >
          <header className="report-print-heading">
            <p>REVA · PRE-VISIT BRIEF</p>
            <h2>{visit.title}</h2>
            <p>
              {formatDate(visit.date, true, visit.timeZone)} · {visit.provider}
            </p>
            <p>Concern: {visit.concern}</p>
            {visit.goal && <p>Visit goal: {visit.goal}</p>}
          </header>
          <div className="row report-meta">
            <Badge tone="accent">{report.generationModel ? 'AI-assisted brief' : 'Local preparation'}</Badge>
            <span className="muted small">
              Prepared {formatDate(report.createdAt, true)} · {report.selectedRecordIDs.length} source
              {report.selectedRecordIDs.length === 1 ? '' : 's'}
            </span>
          </div>
          {report.sections.map((section) => (
            <section className="report-section stack" key={section.id}>
              <h3>{section.title}</h3>
              {!sectionBodyRepeatsSourceQuotes(section) && <p className="prose">{section.body}</p>}
              {section.sources.map((source, index) => {
                const record = snapshot?.records.find((item) => item.id === source.recordID);
                return (
                  <blockquote className="source-quote" key={`${source.recordID}-${source.page}-${index}`}>
                    <p className="prose">{source.excerpt}</p>
                    <footer>
                      <a
                        className="text-link"
                        href={`#/records/${encodeURIComponent(source.recordID)}${source.page > 0 ? `?page=${source.page}` : ''}`}
                      >
                        <FileText size={14} />
                        {record?.title ?? 'Source no longer available'} ·{' '}
                        {source.page > 0 ? `page ${source.page}` : 'record text'}
                        {source.sourceVersion ? ` · version ${source.sourceVersion}` : ''}
                      </a>
                    </footer>
                  </blockquote>
                );
              })}
            </section>
          ))}
          <section className="report-section">
            <div className="section-heading">
              <h3>Questions to ask</h3>
              <Button className="no-print" variant="ghost" onClick={() => setEditing(true)}>
                <Pencil size={15} /> Edit
              </Button>
            </div>
            {visit.questions.length ? (
              <ol className="question-list">
                {visit.questions.map((question, index) => (
                  <li key={`${index}-${question}`}>{question}</li>
                ))}
              </ol>
            ) : (
              <p className="muted">Add the questions you want to take into your appointment.</p>
            )}
          </section>
          <section className="report-section">
            <h3>My notes</h3>
            <p className="prose">{visit.notes || 'No personal notes added.'}</p>
          </section>
          <p className="muted small report-footer">
            Prepared to help you discuss your history with your clinician. Review the original sources and any
            items marked “Needs review.”
          </p>
        </article>
      )}
      {!report && (
        <Button variant="secondary" onClick={() => setEditing(true)}>
          <Pencil size={16} /> Add questions & notes
        </Button>
      )}
      {editing && <BriefNotesEditor visit={visit} onClose={() => setEditing(false)} />}
    </Card>
  );
}

// MARK: - User questions and notes remain authoritative across regeneration
function BriefNotesEditor({ visit, onClose }: { visit: Visit; onClose: () => void }) {
  const { mutate } = useReva();
  const [questions, setQuestions] = useState(visit.questions.join('\n'));
  const [notes, setNotes] = useState(visit.notes);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  async function save(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError('');
    try {
      await mutate((draft) => {
        const latest = draft.visits.find((item) => item.id === visit.id);
        if (!latest) throw new Error('This visit is no longer available.');
        if (
          latest.notes !== visit.notes ||
          JSON.stringify(latest.questions) !== JSON.stringify(visit.questions)
        )
          throw new Error(
            'Your questions or notes changed while this editor was open. Reopen it to review the latest version.',
          );
        latest.questions = questions
          .split('\n')
          .map((line) => line.trim())
          .filter(Boolean);
        latest.notes = notes;
        if (latest.report) {
          latest.report.questions = latest.questions;
          latest.report.notes = notes;
        }
      });
      onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Your notes could not be saved.');
    } finally {
      setSaving(false);
    }
  }
  return (
    <Modal title="Questions & personal notes" onClose={onClose}>
      <form className="stack" onSubmit={save}>
        <Field
          label="Questions to ask"
          hint="One question per line. These are kept when you update your brief."
        >
          <textarea
            rows={6}
            maxLength={20000}
            value={questions}
            onChange={(event) => setQuestions(event.target.value)}
          />
        </Field>
        <Field label="My notes">
          <textarea
            rows={5}
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
            {saving ? 'Saving…' : 'Save questions & notes'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
