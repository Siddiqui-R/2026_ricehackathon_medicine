// Purpose: Merge personal brief edits without replacing newer generated questions or notes.
// Inputs: An immutable opening baseline, submitted fields, and the latest serialized snapshot draft.
// Outputs: Field-targeted changes mirrored into the current report, or an explicit competing-edit error.
// Side effects: Mutates the supplied draft only after all edited fields pass conflict checks.

import type { AppSnapshot, Visit } from '../../core/models';

export type BriefNotesValues = Pick<Visit, 'questions' | 'notes'>;
const fields = ['questions', 'notes'] as const;
const same = (left: unknown, right: unknown) => JSON.stringify(left) === JSON.stringify(right);

// MARK: - Validate all competing fields before applying the user's changed values
export function applyBriefNotesValues(
  snapshot: AppSnapshot,
  id: string,
  values: BriefNotesValues,
  baseline: BriefNotesValues,
): void {
  const latest = snapshot.visits.find((visit) => visit.id === id);
  if (!latest) throw new Error('This visit is no longer available.');
  const changed = fields.filter((field) => !same(values[field], baseline[field]));
  for (const field of changed) {
    if (!same(latest[field], baseline[field]) && !same(latest[field], values[field]))
      throw new Error(
        'Your questions or notes changed while this editor was open. Reopen it to review the latest version.',
      );
  }
  for (const field of changed) Object.assign(latest, { [field]: structuredClone(values[field]) });
  if (latest.report) {
    latest.report.questions = [...latest.questions];
    latest.report.notes = latest.notes;
  }
}
