// Purpose: Save questions and notes without overwriting changes made while their editor was open.
// Inputs: An immutable opening baseline, submitted fields and the latest serialized snapshot draft.
// Outputs: User-edited fields merged with current generated questions, or a competing-edit error.
// Side effects: Changes the supplied draft only after every edited field passes its conflict check.

import type { AppSnapshot, Visit } from '../../core/models';

export type BriefNotesValues = Pick<Visit, 'questions' | 'notes'>;
export type BriefNotesBaseline = BriefNotesValues & Pick<Visit, 'id'>;
const fields = ['questions', 'notes'] as const;

// MARK: - Parse edited question lines while preserving untouched source question wording
export function briefNotesValues(
  baseline: BriefNotesBaseline,
  questionText: string,
  notes: string,
): BriefNotesValues {
  return {
    questions:
      questionText === baseline.questions.join('\n')
        ? [...baseline.questions]
        : questionText
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean),
    notes,
  };
}

// MARK: - Check all edited fields against the opening version before changing either field
export function applyBriefNotes(
  snapshot: AppSnapshot,
  baseline: BriefNotesBaseline,
  values: BriefNotesValues,
): void {
  const latest = snapshot.visits.find((visit) => visit.id === baseline.id);
  if (!latest) throw new Error('This visit is no longer available.');
  const changed = fields.filter((field) => JSON.stringify(values[field]) !== JSON.stringify(baseline[field]));
  for (const field of changed) {
    if (
      JSON.stringify(latest[field]) !== JSON.stringify(baseline[field]) &&
      JSON.stringify(latest[field]) !== JSON.stringify(values[field])
    )
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
