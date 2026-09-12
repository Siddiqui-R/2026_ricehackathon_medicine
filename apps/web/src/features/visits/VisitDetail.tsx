// Purpose: Bring one appointment's preparation, recording, and visit memory into one workspace.
// Inputs: A routed visit ID and the current persisted snapshot.
// Outputs: Appointment details, editable context, source-linked brief and recording sections.
// Side effects: Opens child flows; mutations and connected requests remain owned by context methods.

import { useState } from 'react';
import { ArrowLeft, CalendarDays, MapPin, Pencil } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { formatDate } from '../../core/domain';
import { demoLabel } from '../../core/presentation';
import { Badge, Button, Card, EmptyState, PageHeading } from '../../components/ui';
import { VisitEditor } from './VisitEditor';
import { VisitBrief } from './VisitBrief';
import { RecordingsPanel } from './RecordingsPanel';

// MARK: - Appointment workspace and child feature boundaries
export function VisitDetail({ id }: { id: string }) {
  const { snapshot } = useReva();
  const [editing, setEditing] = useState(false);
  const visit = snapshot?.visits.find((item) => item.id === id);
  if (!visit)
    return (
      <Card>
        <EmptyState title="Visit not found">
          <a className="text-link" href="#/visits">
            Return to visits
          </a>
        </EmptyState>
      </Card>
    );
  return (
    <div className="stack visit-workspace">
      <a className="text-link back-link no-print" href="#/visits">
        <ArrowLeft size={17} /> All visits
      </a>
      <div className="no-print">
        <PageHeading
          eyebrow={visit.type}
          title={visit.title}
          description={demoLabel(visit.provider, snapshot?.profile.isDemo)}
          actions={
            <Button variant="secondary" onClick={() => setEditing(true)}>
              <Pencil size={16} /> Edit visit
            </Button>
          }
        />
      </div>
      <Card className="visit-overview stack no-print">
        <div className="row">
          <span className="row">
            <CalendarDays size={18} />
            {formatDate(visit.date, true, visit.timeZone)}
          </span>
          <Badge>{visit.timeZone}</Badge>
          {visit.clinic && (
            <span className="row">
              <MapPin size={17} />
              {demoLabel(visit.clinic, snapshot?.profile.isDemo)}
            </span>
          )}
        </div>
        <div className="form-grid">
          <div>
            <h3>What I want to discuss</h3>
            <p className="prose">{visit.concern}</p>
          </div>
          <div>
            <h3>My goal for this visit</h3>
            <p className="prose">{visit.goal || 'Add what would make this appointment useful.'}</p>
          </div>
        </div>
      </Card>
      <div className="visit-workspace-grid">
        <div className="visit-primary">
          <VisitBrief visit={visit} />
        </div>
        <aside className="stack visit-secondary no-print">
          <RecordingsPanel key={visit.id} visit={visit} />
        </aside>
      </div>
      {editing && <VisitEditor visit={visit} onClose={() => setEditing(false)} />}
    </div>
  );
}
