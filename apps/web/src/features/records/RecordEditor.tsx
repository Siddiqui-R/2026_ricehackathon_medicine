// Purpose: Correct document metadata/source text while retaining provenance and source-version authority.
// Inputs: The original record, edited fields, and explicit review confirmation.
// Outputs: A revised record with refreshed excerpt/page mapping only when source wording changed.
// Side effects: Persists through context with expectedVersion; cancelling leaves the record untouched.

import { useState, type FormEvent } from 'react';
import { useReva } from '../../core/RevaContext';
import { localExcerpt } from '../../core/domain';
import type { MedicalRecord } from '../../core/models';
import { Button, Field, Modal } from '../../components/ui';
import { MAX_TEXT_BYTES, textByteCount } from './extractDocument';

// MARK: - Hold an editing baseline rather than adopting later asynchronous summaries
export function RecordEditor({ record, onClose }: { record: MedicalRecord; onClose: () => void }) {
  const { saveRecord, notify } = useReva();
  const [original] = useState(() => structuredClone(record));
  const [draft, setDraft] = useState(() => structuredClone(record));
  const [reviewed, setReviewed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [discard, setDiscard] = useState(false);
  const changed = draft.text !== original.text;
  const dirty = JSON.stringify(draft) !== JSON.stringify(original) || reviewed;
  const close = () => {
    if (!saving) {
      if (dirty) setDiscard(true);
      else onClose();
    }
  };
  const update = (key: 'title' | 'provider' | 'date' | 'text' | 'notes', value: string) => {
    setDraft((current) => ({ ...current, [key]: value }));
    if (key === 'text') setReviewed(false);
  };

  // MARK: - Preserve original bytes; manual full-text corrections no longer claim page segmentation
  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError('');
    try {
      if (!draft.title.trim() || !draft.date) throw new Error('Enter a title and source date.');
      if (changed && textByteCount(draft.text) > MAX_TEXT_BYTES)
        throw new Error('Keep corrected text within 120 KB.');
      const revised = {
        ...draft,
        title: draft.title.trim(),
        provider: draft.provider.trim(),
        isDemo: original.isDemo,
      };
      if (changed) {
        revised.summary = localExcerpt(revised.text, revised.isDemo);
        revised.summaryModel = null;
        revised.pageTexts = null;
        revised.status = reviewed && revised.text.trim() ? 'ready' : 'needsReview';
      } else if (reviewed && revised.text.trim() && original.status === 'needsReview')
        revised.status = 'ready';
      await saveRecord(revised, original.version);
      notify('Record updated. Source changes mark previous visit briefs for refresh.');
      onClose();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'The record could not be updated.');
    } finally {
      setSaving(false);
    }
  };
  return (
    <Modal title="Edit record" onClose={close} wide>
      {discard ? (
        <div className="stack">
          <p>Discard the changes you have not saved?</p>
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
          <div className="form-grid">
            <Field label="Record title">
              <input
                required
                value={draft.title}
                onChange={(event) => update('title', event.target.value)}
                maxLength={240}
              />
            </Field>
            <Field label="Source date">
              <input
                required
                type="date"
                value={draft.date.slice(0, 10)}
                onChange={(event) => update('date', event.target.value)}
              />
            </Field>
            <div className="field-full">
              <Field label="Clinic or provider">
                <input
                  value={draft.provider}
                  onChange={(event) => update('provider', event.target.value)}
                  maxLength={240}
                />
              </Field>
            </div>
          </div>
          <Field
            label="Source text"
            hint="Retain exact wording, values, and units. Text corrections refresh the local excerpt and remove unverified page mapping."
          >
            <textarea rows={13} value={draft.text} onChange={(event) => update('text', event.target.value)} />
          </Field>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={reviewed}
              onChange={(event) => setReviewed(event.target.checked)}
              disabled={!draft.text.trim()}
            />
            <span>I checked this text against the original source</span>
          </label>
          <Field label="Your notes · optional">
            <textarea
              rows={3}
              value={draft.notes}
              onChange={(event) => update('notes', event.target.value)}
              maxLength={20000}
            />
          </Field>
          {error && (
            <p className="inline-error" role="alert">
              {error}
            </p>
          )}
          <div className="form-actions">
            <Button variant="secondary" onClick={close} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !draft.title.trim()}>
              {saving ? 'Saving…' : 'Save changes'}
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
