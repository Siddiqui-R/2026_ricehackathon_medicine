// Purpose: Collect appointment details, personal questions, and records that must be included.
// Inputs: An optional existing visit and the current medical records from Reva context.
// Outputs: A validated saved visit and navigation to its detail page.
// Side effects: Persists through context; no report or provider request is started automatically.

import { useRef, useState, type FormEvent } from 'react';
import { useReva } from '../../core/RevaContext';
import type { Visit } from '../../core/models';
import { uid } from '../../core/domain';
import { Button, Field, Modal } from '../../components/ui';
import { dateFieldISO, dateFieldValue, visitTimeZones } from './visitDates';
import { applyVisitEditorValues, type VisitEditorValues } from './visitEdits';

// MARK: - Editor state and save boundary
export function VisitEditor({ visit, onClose }: { visit?: Visit; onClose: () => void }) {
  const { snapshot, mutate } = useReva();
  const [baseline] = useState(() => (visit ? structuredClone(visit) : undefined));
  const [id] = useState(() => visit?.id ?? uid());
  const inFlight = useRef(false);
  const initialZone = baseline?.timeZone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [form, setForm] = useState({
    title: visit?.title ?? '',
    type: visit?.type ?? 'Primary care',
    provider: visit?.provider ?? '',
    clinic: visit?.clinic ?? '',
    date: dateFieldValue(visit?.date ?? new Date(Date.now() + 3 * 86400000).toISOString(), initialZone),
    zone: initialZone,
    concern: visit?.concern ?? '',
    goal: visit?.goal ?? '',
    questions: visit?.questions.join('\n') ?? '',
    pins: visit?.pinnedRecordIDs ?? [],
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const change = (key: keyof typeof form, value: string) =>
    setForm((previous) => ({ ...previous, [key]: value }));
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (inFlight.current) return;
    inFlight.current = true;
    setError('');
    setSaving(true);
    try {
      if (!form.title.trim() || !form.provider.trim() || !form.concern.trim())
        throw new Error('Add a visit title, clinician, and the concern you want to discuss.');
      const dateUnchanged =
        baseline &&
        form.zone === baseline.timeZone &&
        form.date === dateFieldValue(baseline.date, baseline.timeZone);
      const values: VisitEditorValues = {
        title: form.title.trim(),
        type: form.type,
        provider: form.provider.trim(),
        clinic: form.clinic.trim(),
        date: dateUnchanged ? baseline.date : dateFieldISO(form.date, form.zone),
        timeZone: form.zone,
        concern: form.concern.trim(),
        goal: form.goal.trim(),
        questions: form.questions
          .split('\n')
          .map((line) => line.trim())
          .filter(Boolean),
        pinnedRecordIDs: form.pins,
      };
      await mutate((draft) => applyVisitEditorValues(draft, id, values, baseline));
      onClose();
      window.location.hash = `#/visits/${encodeURIComponent(id)}`;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The visit could not be saved.');
    } finally {
      inFlight.current = false;
      setSaving(false);
    }
  }

  // MARK: - Appointment context and optional evidence pins
  return (
    <Modal title={visit ? 'Edit visit' : 'Add a visit'} onClose={onClose} wide>
      <form className="stack" onSubmit={submit}>
        <div className="form-grid">
          <Field label="Visit title">
            <input
              required
              maxLength={180}
              value={form.title}
              onChange={(event) => change('title', event.target.value)}
              placeholder="e.g. Follow-up about nausea"
            />
          </Field>
          <Field label="Visit type">
            <select value={form.type} onChange={(event) => change('type', event.target.value)}>
              {Array.from(new Set(['Primary care', 'Orthopedics', 'Cardiology', 'Other', form.type])).map(
                (type) => (
                  <option key={type}>{type}</option>
                ),
              )}
            </select>
          </Field>
          <Field label="Clinician">
            <input
              required
              maxLength={180}
              value={form.provider}
              onChange={(event) => change('provider', event.target.value)}
              placeholder="Clinician or care team"
            />
          </Field>
          <Field label="Clinic">
            <input
              maxLength={180}
              value={form.clinic}
              onChange={(event) => change('clinic', event.target.value)}
            />
          </Field>
          <Field label="Date and time" hint="The time entered uses the time zone selected here.">
            <input
              required
              type="datetime-local"
              value={form.date}
              onChange={(event) => change('date', event.target.value)}
            />
          </Field>
          <Field label="Time zone">
            <select value={form.zone} onChange={(event) => change('zone', event.target.value)}>
              {Array.from(new Set([...visitTimeZones, initialZone])).map((zone) => (
                <option key={zone}>{zone}</option>
              ))}
            </select>
          </Field>
        </div>
        <Field label="What would you like to discuss?">
          <textarea
            required
            rows={3}
            maxLength={10000}
            value={form.concern}
            onChange={(event) => change('concern', event.target.value)}
            placeholder="Describe your concern or symptoms in your own words."
          />
        </Field>
        <Field label="What would make this visit useful?">
          <textarea
            rows={2}
            maxLength={10000}
            value={form.goal}
            onChange={(event) => change('goal', event.target.value)}
            placeholder="e.g. Understand which results need follow-up."
          />
        </Field>
        <Field
          label="Questions to ask"
          hint="One question per line. These stay editable in your visit brief."
        >
          <textarea
            rows={3}
            maxLength={20000}
            value={form.questions}
            onChange={(event) => change('questions', event.target.value)}
          />
        </Field>
        <details className="evidence-picker">
          <summary>Always include specific records ({form.pins.length})</summary>
          <p className="muted small">
            These records will be included alongside history relevant to your visit.
          </p>
          <div className="stack">
            {snapshot?.records.map((record) => (
              <label className="row" key={record.id}>
                <input
                  type="checkbox"
                  checked={form.pins.includes(record.id)}
                  onChange={(event) =>
                    setForm((previous) => ({
                      ...previous,
                      pins: event.target.checked
                        ? [...previous.pins, record.id]
                        : previous.pins.filter((id) => id !== record.id),
                    }))
                  }
                />
                <span>
                  {record.title}
                  <span className="record-meta">
                    {record.kind} · {record.date}
                  </span>
                </span>
              </label>
            ))}
          </div>
        </details>
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
            {saving ? 'Saving…' : 'Save visit'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
