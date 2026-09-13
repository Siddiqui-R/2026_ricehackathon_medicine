import { demoDescription, demoLabel } from '../../core/presentation';
// Purpose: Generate and preview a concise pre-visit brief with an explicit PDF download.
// Inputs: Optional visit details, current workspace context, and patient-entered concerns/questions.
// Outputs: A bounded brief preview, downloadable PDF, and actionable generation errors.
// Side effects: Calls the authenticated provider on submission, generates a PDF, and manages its object URL.

// MARK: - Transient form, generation lifecycle, and source-aware preview
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Download, Sparkles } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { briefContextSignature, type ClinicalBrief, type VisitBriefInput } from '../../core/visitBrief';
import { formatDate } from '../../core/dates';
import { demoBriefDefaults } from '../../core/demoVisitBrief';
import { Button, Field } from '../../components/ui';
import { SourceLink, type SourceTarget } from '../../components/SourceLink';
import './visitPreparation.css';

export function VisitPreparation({ initial }: { initial?: VisitBriefInput }) {
  const { generateVisitBrief, snapshot, token, mode } = useReva();
  const demo = mode === 'demo' && snapshot?.profile.isDemo === true;
  const defaults = initial ?? (demo && snapshot ? demoBriefDefaults(snapshot) : undefined);
  const [type, setType] = useState(defaults?.type ?? '');
  const [concern, setConcern] = useState(defaults?.concern ?? '');
  const [questions, setQuestions] = useState(defaults?.questions.join('\n') ?? '');
  const [working, setWorking] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<{ brief: ClinicalBrief; url: string } | null>(null);
  const visitDetails = useRef<HTMLFormElement>(null);
  const mounted = useRef(true),
    request = useRef(0);
  const activeRequest = useRef<AbortController | null>(null);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      request.current++;
      activeRequest.current?.abort();
    };
  }, []);
  useEffect(
    () => () => {
      if (result) URL.revokeObjectURL(result.url);
    },
    [result],
  );
  useEffect(() => {
    activeRequest.current?.abort();
    activeRequest.current = null;
    setResult(null);
    setWorking(false);
    setError('');
    request.current++;
  }, [token]);
  const stale = result && snapshot && result.brief.sourceSignature !== briefContextSignature(snapshot);
  const sourceTarget = (source: ClinicalBrief['sources'][number]): SourceTarget[] => {
    const record = snapshot?.records.find((item) => item.id === source.id);
    if (record) return [{ label: source.title, href: `#/records/${encodeURIComponent(record.id)}` }];
    // The preparation service supplies this separate context record for the current profile.
    return ['Medical profile', 'Patient-provided medical profile'].includes(source.title)
      ? [{ label: 'Medical profile', href: '#/profile' }]
      : [];
  };
  const sourceTargets = result?.brief.sources.flatMap(sourceTarget) ?? [];
  const inputIcon = (
    <SourceLink
      label="View source: details entered for this visit"
      onOpen={() => {
        visitDetails.current?.scrollIntoView({ block: 'start' });
        visitDetails.current?.focus({ preventScroll: true });
      }}
    />
  );
  const sourceIcon = sourceTargets.length ? (
    <SourceLink sources={sourceTargets} label="View sources used for this brief" />
  ) : (
    inputIcon
  );
  async function generate(event: FormEvent) {
    event.preventDefault();
    if (working || activeRequest.current) return;
    const generation = ++request.current;
    const controller = new AbortController();
    activeRequest.current = controller;
    const current = () => mounted.current && generation === request.current && !controller.signal.aborted;
    setWorking(true);
    setError('');
    setResult(null);
    try {
      const brief = await generateVisitBrief(
        {
          type,
          concern,
          questions: questions
            .split('\n')
            .map((q) => q.trim())
            .filter(Boolean),
        },
        controller.signal,
      );
      if (!current()) return;
      const { createBriefPDF } = await import('./briefPDF');
      if (!current()) return;
      const sourceURLs = Object.fromEntries(
        brief.sources.flatMap((source) =>
          sourceTarget(source).map((target) => [source.id, new URL(target.href, window.location.href).href]),
        ),
      );
      const bytes = await createBriefPDF(brief, undefined, sourceURLs);
      if (!current()) return;
      const url = URL.createObjectURL(new Blob([new Uint8Array(bytes)], { type: 'application/pdf' }));
      setResult({ brief, url });
    } catch (failure) {
      if (current())
        setError(failure instanceof Error ? failure.message : 'The brief could not be generated. Try again.');
    } finally {
      if (activeRequest.current === controller) activeRequest.current = null;
      if (mounted.current && generation === request.current) setWorking(false);
    }
  }
  function stop() {
    request.current++;
    activeRequest.current?.abort();
    activeRequest.current = null;
    setWorking(false);
    setError('');
  }
  return (
    <div className="visit-preparation stack">
      <form
        ref={visitDetails}
        tabIndex={-1}
        aria-label="Details entered for this visit"
        className="stack"
        onSubmit={(event) => {
          void generate(event);
        }}
      >
        <fieldset className="brief-fields" disabled={working}>
          <Field label="Visit type">
            <input
              required
              maxLength={80}
              placeholder="e.g. Cardiology follow-up"
              value={type}
              onChange={(event) => {
                setType(event.target.value);
                setResult(null);
              }}
            />
          </Field>
          <Field label="Main concern (optional)">
            <textarea
              rows={2}
              maxLength={2000}
              value={concern}
              onChange={(event) => {
                setConcern(event.target.value);
                setResult(null);
              }}
            />
          </Field>
          <Field label="Questions (optional)" hint="Up to three. One per line.">
            <textarea
              rows={3}
              maxLength={902}
              value={questions}
              onChange={(event) => {
                setQuestions(event.target.value);
                setResult(null);
              }}
            />
          </Field>
        </fieldset>
        <p className="muted small">
          {demo
            ? 'Prepare a brief using the records in this workspace.'
            : 'Prepare for your upcoming appointment. Gemini uses your current records and medical profile when you run this brief.'}
        </p>
        <div className="form-actions">
          <Button type="submit" disabled={working}>
            <Sparkles size={16} />
            {working ? 'Preparing your visit…' : 'Run pre-visit brief'}
          </Button>
          {working && (
            <Button type="button" variant="secondary" onClick={stop}>
              Stop preparation
            </Button>
          )}
        </div>
      </form>
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
      {stale && <p role="status">Your records changed. Generate a new brief.</p>}
      {result && !stale && (
        <>
          <a className="button button-primary" href={result.url} download="pre-visit-brief.pdf">
            <Download size={16} /> Download PDF
          </a>
          <article className="clinical-brief" aria-label="Pre-visit brief preview">
            <header>
              <h2>Pre-visit brief</h2>
              <strong>{demoLabel(result.brief.patient.name, result.brief.patient.isDemo)}</strong>
              {result.brief.patient.dateOfBirth && (
                <div>DOB: {formatDate(result.brief.patient.dateOfBirth)}</div>
              )}
              <p>
                {result.brief.visitType} · Prepared {formatDate(result.brief.createdAt)}
              </p>
            </header>
            {result.brief.overview
              .split(/\r?\n+/)
              .filter(Boolean)
              .map((line, index) => (
                <p className="clinical-overview" key={index}>
                  {line}
                  {result.brief.overviewSourceIDs?.[index] ? (
                    <SourceLink
                      sources={result.brief.sources
                        .filter((source) => source.id === result.brief.overviewSourceIDs?.[index])
                        .flatMap(sourceTarget)}
                    />
                  ) : (
                    sourceIcon
                  )}
                </p>
              ))}
            {!!result.brief.questions.length && (
              <section>
                <h3>Questions to ask</h3>
                <ol>
                  {result.brief.questions.map((q, i) => (
                    <li key={i}>
                      {q}
                      {result.brief.example ? inputIcon : sourceIcon}
                    </li>
                  ))}
                </ol>
              </section>
            )}
            {!!result.brief.sources.length && (
              <section className="clinical-sources">
                <h3>Sources</h3>
                <ol>
                  {result.brief.sources.map((source) => (
                    <li key={source.id}>
                      {demoLabel(source.title, result.brief.patient.isDemo)}
                      {source.date && ` · ${formatDate(source.date)}`}
                      <SourceLink sources={sourceTarget(source)} />
                    </li>
                  ))}
                </ol>
              </section>
            )}
            <footer>
              {result.brief.example
                ? 'Prepared from saved records · Review for accuracy'
                : 'Patient-prepared · AI-assisted · Review for accuracy'}
            </footer>
          </article>
        </>
      )}
    </div>
  );
}
