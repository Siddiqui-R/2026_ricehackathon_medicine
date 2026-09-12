// Purpose: Adapt an existing appointment to the on-demand pre-visit preparation flow.
// Inputs: A saved visit's type, concern, and patient questions.
// Outputs: A preparation form initialized from the visit without overwriting its saved report.
// Side effects: Delegates explicit generation to VisitPreparation; mounting does not persist changes.

// MARK: - Existing visit preparation entry point
// Legacy visit links use the same live, concise flow without overwriting historical reports.
import type { Visit } from '../../core/models';
import { VisitPreparation } from './VisitPreparation';
export function VisitBrief({ visit }: { visit: Visit }) {
  return (
    <VisitPreparation initial={{ type: visit.type, concern: visit.concern, questions: visit.questions }} />
  );
}
