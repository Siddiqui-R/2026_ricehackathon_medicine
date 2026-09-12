// Purpose: Present all appointments and an accessible entry point for adding a visit.
// Inputs: The persisted visit collection from Reva context.
// Outputs: Filtered appointment cards and links to each preparation workspace.
// Side effects: Opens the visit editor; list filtering is local UI state only.

import { useState } from 'react';
import { CalendarDays, ChevronRight, Plus } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { formatDate } from '../../core/domain';
import { demoLabel } from '../../core/presentation';
import { Badge, Button, Card, EmptyState, PageHeading } from '../../components/ui';
import { VisitEditor } from './VisitEditor';

// MARK: - Visit navigation and filtering
export function VisitsPage() {
  const { snapshot } = useReva();
  const [editing, setEditing] = useState(
    () => new URLSearchParams(window.location.hash.split('?')[1] ?? '').get('add') === 'visit',
  );
  const [filter, setFilter] = useState('All visits');
  const visits = [...(snapshot?.visits ?? [])]
    .filter(
      (visit) =>
        filter === 'All visits' ||
        (filter === 'Upcoming'
          ? visit.status !== 'completed' && new Date(visit.date).getTime() >= Date.now()
          : visit.status === 'completed' || new Date(visit.date).getTime() < Date.now()),
    )
    .sort((a, b) => {
      const first = new Date(a.date).getTime(),
        second = new Date(b.date).getTime();
      const firstUpcoming = a.status !== 'completed' && first >= Date.now();
      const secondUpcoming = b.status !== 'completed' && second >= Date.now();
      if (filter === 'All visits' && firstUpcoming !== secondUpcoming) return firstUpcoming ? -1 : 1;
      return firstUpcoming ? first - second : second - first;
    });
  return (
    <div className="stack">
      <PageHeading
        title="Visits"
        description="Bring the right history and the questions that matter."
        actions={
          <Button onClick={() => setEditing(true)}>
            <Plus size={18} /> Add a visit
          </Button>
        }
      />
      <div className="row visit-filters" aria-label="Filter visits">
        {['All visits', 'Upcoming', 'Past visits'].map((item) => (
          <Button
            key={item}
            variant={filter === item ? 'primary' : 'secondary'}
            aria-pressed={filter === item}
            onClick={() => setFilter(item)}
          >
            {item}
          </Button>
        ))}
      </div>
      {visits.length ? (
        <div className="visits-grid">
          {visits.map((visit) => (
            <Card key={visit.id} className="visit-card">
              <a className="visit-card-link stack" href={`#/visits/${encodeURIComponent(visit.id)}`}>
                <div className="row">
                  <span className="record-icon">
                    <CalendarDays size={23} />
                  </span>
                  <Badge tone={visit.report ? 'accent' : 'neutral'}>
                    {visit.report ? 'Brief saved' : 'Ready to prepare'}
                  </Badge>
                  <ChevronRight size={18} />
                </div>
                <div>
                  <p className="record-meta">{visit.type}</p>
                  <h2>{visit.title}</h2>
                  <p className="muted">{formatDate(visit.date, true, visit.timeZone)}</p>
                  <p>
                    {demoLabel(visit.provider, snapshot?.profile.isDemo)}
                    {visit.clinic ? ` · ${demoLabel(visit.clinic, snapshot?.profile.isDemo)}` : ''}
                  </p>
                </div>
                <p className="visit-concern">{visit.concern}</p>
              </a>
            </Card>
          ))}
        </div>
      ) : (
        <Card>
          <EmptyState
            title={filter === 'All visits' ? 'Your next visit starts here' : `No ${filter.toLowerCase()} yet`}
          >
            <p>Add an appointment and tell Reva what you want to discuss.</p>
            <Button onClick={() => setEditing(true)}>Add a visit</Button>
          </EmptyState>
        </Card>
      )}
      {editing && <VisitEditor onClose={() => setEditing(false)} />}
    </div>
  );
}
