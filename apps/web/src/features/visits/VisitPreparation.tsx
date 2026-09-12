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
import { Button, Field } from '../../components/ui';
import './visitPreparation.css';

export function VisitPreparation({ initial }: { initial?: VisitBriefInput }) {
  const { generateVisitBrief, snapshot, token } = useReva();
  const [type, setType] = useState(initial?.type ?? '');
  const [concern, setConcern] = useState(initial?.concern ?? '');
  const [questions, setQuestions] = useState(initial?.questions.join('\n') ?? '');
  const [working, setWorking] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<{ brief: ClinicalBrief; url: string } | null>(null);
  const mounted = useRef(true),
    request = useRef(0);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      request.current++;
    };
  }, []);
  useEffect(
    () => () => {
      if (result) URL.revokeObjectURL(result.url);
    },
    [result],
  );
  useEffect(() => {
    setResult(null);
    request.current++;
  }, [token]);
  const stale = result && snapshot && result.brief.sourceSignature !== briefContextSignature(snapshot);
  async function generate(event: FormEvent) {
    event.preventDefault();
    if (working) return;
    const generation = ++request.current;
    setWorking(true);
    setError('');
    setResult(null);
    try {
      const brief = await generateVisitBrief({
        type,
        concern,
        questions: questions
          .split('\n')
          .map((q) => q.trim())
          .filter(Boolean),
      });
      const { createBriefPDF } = await import('./briefPDF');
      const bytes = await createBriefPDF(brief);
      if (!mounted.current || generation !== request.current) return;
      const url = URL.createObjectURL(new Blob([new Uint8Array(bytes)], { type: 'application/pdf' }));
      setResult({ brief, url });
    } catch (failure) {
      if (mounted.current)
        setError(failure instanceof Error ? failure.message : 'The brief could not be generated. Try again.');
    } finally {
      if (mounted.current) setWorking(false);
    }
  }
  return (
    <div className="visit-preparation stack">
      <form
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
          Prepare for your upcoming appointment. Gemini uses your current records and medical profile when you
          run this brief.
        </p>
        <Button type="submit" disabled={working}>
          <Sparkles size={16} />
          {working ? 'Preparing your visit…' : 'Run pre-visit brief'}
        </Button>
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
              <strong>{result.brief.patient.name}</strong>
              {result.brief.patient.dateOfBirth && (
                <div>DOB: {formatDate(result.brief.patient.dateOfBirth)}</div>
              )}
              <p>
                {result.brief.visitType} · Prepared {formatDate(result.brief.createdAt)}
              </p>
            </header>
            <p className="clinical-overview">{result.brief.overview}</p>
            {!!result.brief.questions.length && (
              <section>
                <h3>Questions to ask</h3>
                <ol>
                  {result.brief.questions.map((q, i) => (
                    <li key={i}>{q}</li>
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
                      {source.title}
                      {source.date && ` · ${formatDate(source.date)}`}
                    </li>
                  ))}
                </ol>
              </section>
            )}
            <footer>
              {result.brief.patient.isDemo && 'Fictional demo · '}Patient-prepared · AI-assisted · Review for
              accuracy
            </footer>
          </article>
        </>
      )}
    </div>
  );
}
