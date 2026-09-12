// Purpose: Merge appointment-editor fields against the latest serialized snapshot draft.
// Inputs: The initial visit baseline, submitted editor fields, and the current snapshot.
// Outputs: A saved appointment that preserves newer reports, notes, status, and untouched fields.
// Side effects: Mutates only the supplied draft after checking concurrent edits; no persistence or HTTP.

import type { AppSnapshot, Visit } from '../../core/models';

export type VisitEditorValues = Pick<
  Visit,
  | 'title'
  | 'type'
  | 'provider'
  | 'clinic'
  | 'date'
  | 'timeZone'
  | 'concern'
  | 'goal'
  | 'questions'
  | 'pinnedRecordIDs'
>;
const fields = [
  'title',
  'type',
  'provider',
  'clinic',
  'date',
  'timeZone',
  'concern',
  'goal',
  'questions',
  'pinnedRecordIDs',
] as const;
function same(field: keyof VisitEditorValues, left: Visit, right: VisitEditorValues): boolean {
  return field === 'date'
    ? Date.parse(left.date) === Date.parse(right.date)
    : JSON.stringify(left[field]) === JSON.stringify(right[field]);
}

// MARK: - Detect competing edits before applying any change to the current draft
export function applyVisitEditorValues(
  snapshot: AppSnapshot,
  id: string,
  values: VisitEditorValues,
  baseline?: Visit,
): void {
  if (
    !values.title.trim() ||
    !values.provider.trim() ||
    !values.concern.trim() ||
    !Number.isFinite(Date.parse(values.date))
  )
    throw new Error('Add a visit title, clinician, valid date, and the concern you want to discuss.');
  const index = snapshot.visits.findIndex((visit) => visit.id === id);
  const latest = snapshot.visits[index];
  if (baseline && !latest)
    throw new Error('This visit is no longer available. Your editor has not recreated it.');
  if (!baseline && latest) throw new Error('This visit was already saved. Close the editor to review it.');
  const edited = {
    ...values,
    pinnedRecordIDs: values.pinnedRecordIDs.filter((recordID) =>
      snapshot.records.some((record) => record.id === recordID),
    ),
  };
  const changed = baseline ? fields.filter((field) => !same(field, baseline, edited)) : [...fields];
  // Date and zone form one appointment time; do not merge a new instant with a concurrently changed zone.
  if (changed.includes('date') || changed.includes('timeZone')) {
    if (!changed.includes('date')) changed.push('date');
    if (!changed.includes('timeZone')) changed.push('timeZone');
  }
  if (baseline && latest) {
    for (const field of changed) {
      if (!same(field, latest, baseline) && !same(field, latest, edited))
        throw new Error(
          'This appointment changed while you were editing. Reopen the editor to review the latest details before saving.',
        );
    }
  }

  // MARK: - Preserve current generated evidence and user-owned notes; mirror authoritative questions
  const saved: Visit = latest
    ? structuredClone(latest)
    : { id, ...structuredClone(edited), notes: '', status: 'upcoming' };
  for (const field of changed) Object.assign(saved, { [field]: structuredClone(edited[field]) });
  if (saved.report) {
    saved.report.questions = [...saved.questions];
    saved.report.notes = saved.notes;
  }
  if (index < 0) snapshot.visits.push(saved);
  else snapshot.visits[index] = saved;
}
