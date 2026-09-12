// Purpose: Make a self-reported symptom observation quick to create and straightforward to revise.
// Inputs: Optional existing structured entry, user wording, occurrence time, and optional context.
// Outputs: A validated MedicalRecord that participates in search and preparation as an original source.
// Side effects: Persists through Reva context and optionally summarizes after local saving.

import { useState, type FormEvent } from 'react';
import { Check, Clock, NotebookPen } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { makeSymptomRecord, nowISO } from '../../core/domain';
import { dateFieldValue, defaultTimeZone, displayTimeZone } from '../../core/dates';
import { editedSymptomOccurrence } from '../../core/symptoms';
import type { MedicalRecord, SymptomEntry } from '../../core/models';
import { Button, Field, Modal } from '../../components/ui';

// MARK: - Zoned occurrence display keeps the original instant unless the user edits it
export function SymptomDialog({ record, onClose }: { record?: MedicalRecord; onClose: () => void }) {
  const { saveRecord, summarizeRecord, connectedAI, notify, reportError } = useReva();
  const [original] = useState(() => (record?.symptomEntry ? structuredClone(record) : undefined));
  const [initial] = useState<SymptomEntry>(
    () =>
      original?.symptomEntry ?? {
        observedAt: nowISO(),
        timeZone: defaultTimeZone,
        symptom: '',
        severity: null,
        duration: '',
        details: '',
        triggers: '',
        whatHelped: '',
      },
  );
  const [entry, setEntry] = useState<SymptomEntry>(initial);
  const occurrenceZone = displayTimeZone(initial.timeZone);
  const initialWhen = dateFieldValue(initial.observedAt, occurrenceZone);
  const [when, setWhen] = useState(initialWhen);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [discard, setDiscard] = useState(false);
  const dirty = JSON.stringify(entry) !== JSON.stringify(initial) || when !== initialWhen;
  const close = () => {
    if (!saving) {
      if (dirty) setDiscard(true);
      else onClose();
    }
  };
  const update = <K extends keyof SymptomEntry>(key: K, value: SymptomEntry[K]) =>
    setEntry((current) => ({ ...current, [key]: value }));

  // MARK: - Preserve source identity and reject concurrent changes through expectedVersion
  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError('');
    try {
      const revised = {
        ...entry,
        ...editedSymptomOccurrence(initial, when),
      };
      const saved = makeSymptomRecord(revised, original);
      await saveRecord(saved, original?.version);
      notify(
        original
          ? 'Symptom entry updated. Previous visit briefs may need refreshing.'
          : 'Symptom entry saved to Records.',
      );
      if (connectedAI) void summarizeRecord(saved.id).catch(reportError);
      onClose();
      location.hash = `/records/${encodeURIComponent(saved.id)}`;
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'The symptom entry could not be saved.');
    } finally {
      setSaving(false);
    }
  };
  return (
    <Modal title={original ? 'Edit symptom entry' : 'Log symptoms'} onClose={close}>
      {discard ? (
        <div className="stack">
          <p>Discard your unsaved changes to this symptom entry?</p>
          <div className="form-actions">
            <Button variant="secondary" onClick={() => setDiscard(false)}>
              Keep editing
            </Button>
            <Button variant="danger" onClick={onClose}>
              Discard changes
            </Button>
          </div>
        </div>
      ) : (
        <form className="stack" onSubmit={(event) => void save(event)}>
          <div className="row">
            <span className="record-icon">
              <NotebookPen size={23} />
            </span>
            <p className="muted">
              A quick observation in your own words. Only the symptom and time are required.
            </p>
          </div>
          <Field label="What did you notice?">
            <input
              autoFocus
              required
              value={entry.symptom}
              onChange={(event) => update('symptom', event.target.value)}
              maxLength={120}
              placeholder="For example, nausea or a headache"
            />
          </Field>
          <Field
            label="When did it happen?"
            hint={`Shown in ${occurrenceZone}. Existing occurrence time is kept unless you change this field.`}
          >
            <input
              type="datetime-local"
              required
              value={when}
              max={dateFieldValue(nowISO(), occurrenceZone)}
              onChange={(event) => setWhen(event.target.value)}
            />
          </Field>
          <div className="form-grid">
            <Field label="Severity · optional">
              <select
                value={entry.severity ?? ''}
                onChange={(event) => update('severity', event.target.value || null)}
              >
                <option value="">Not specified</option>
                <option value="mild">Mild</option>
                <option value="moderate">Moderate</option>
                <option value="severe">Severe</option>
              </select>
            </Field>
            <Field label="Duration · optional">
              <input
                value={entry.duration}
                onChange={(event) => update('duration', event.target.value)}
                maxLength={2000}
                placeholder="20 minutes, or still happening"
              />
            </Field>
          </div>
          <Field label="Details · optional">
            <textarea
              rows={4}
              value={entry.details}
              onChange={(event) => update('details', event.target.value)}
              maxLength={12000}
              placeholder="Where you felt it, what happened, or anything you want to remember"
            />
          </Field>
          <details open={Boolean(initial.triggers || initial.whatHelped)}>
            <summary>A little more detail</summary>
            <div className="stack detail-fields">
              <Field label="Possible triggers · optional">
                <textarea
                  rows={2}
                  value={entry.triggers}
                  onChange={(event) => update('triggers', event.target.value)}
                  maxLength={2000}
                  placeholder="Anything you noticed before it started"
                />
              </Field>
              <Field label="What helped? · optional">
                <textarea
                  rows={2}
                  value={entry.whatHelped}
                  onChange={(event) => update('whatHelped', event.target.value)}
                  maxLength={2000}
                  placeholder="What you tried and how it felt"
                />
              </Field>
            </div>
          </details>
          <p className="small muted">
            <Clock size={15} /> Saved as a User symptom entry in Records. Relevant observations can be
            included in visit preparation.
          </p>
          {error && (
            <p className="inline-error" role="alert">
              {error}
            </p>
          )}
          <div className="form-actions">
            <Button variant="secondary" onClick={close} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !entry.symptom.trim()}>
              <Check size={18} />
              {saving ? 'Saving…' : 'Save entry'}
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
