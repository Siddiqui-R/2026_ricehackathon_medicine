// Purpose: Preserve the visits route as an entry point to on-demand visit preparation.
// Inputs: The active patient workspace through the nested preparation component.
// Outputs: An upcoming-visit preparation form without creating an appointment list.
// Side effects: Delegates explicit generation to VisitPreparation; no action occurs on mount.

// MARK: - Standalone preparation route
import { PageHeading, Card } from '../../components/ui';
import { VisitPreparation } from './VisitPreparation';

export function VisitsPage() {
  return (
    <div className="stack">
      <PageHeading title="Upcoming visit" />
      <Card>
        <VisitPreparation />
      </Card>
    </div>
  );
}
