// Purpose: Present searchable source history and direct document/symptom intake actions.
// Inputs: Local snapshot records, optional route action, and the hash search query.
// Outputs: Filtered linked rows and the relevant creation dialog.
// Side effects: Observes hash navigation; record mutations are delegated to dialogs and Reva context.

import { useEffect, useState } from 'react';
import { ChevronRight, NotebookPen, Search, Upload } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { formatDate } from '../../core/domain';
import { demoLabel } from '../../core/presentation';
import { Badge, Button, Card, EmptyState, PageHeading } from '../../components/ui';
import { ImportDialog } from './ImportDialog';
import { SymptomDialog } from './SymptomDialog';
import { newestRecords, queryParameter, RecordSymbol } from './recordPresentation';

// MARK: - Search, category filtering, and source navigation
export function RecordsPage({ initialAction }: { initialAction?: 'import' | 'symptom' }) {
  const { snapshot, loading } = useReva();
  const [query, setQuery] = useState(() => queryParameter('q') ?? '');
  const [filter, setFilter] = useState('All records');
  const [dialog, setDialog] = useState<'import' | 'symptom' | null>(initialAction ?? null);
  useEffect(() => {
    if (initialAction) setDialog(initialAction);
  }, [initialAction]);
  useEffect(() => {
    const update = () => {
      setQuery(queryParameter('q') ?? '');
      setFilter('All records');
    };
    window.addEventListener('hashchange', update);
    return () => window.removeEventListener('hashchange', update);
  }, []);
  // Remove one-shot intake instructions so the same sidebar action can open again after cancellation.
  const closeDialog = () => {
    setDialog(null);
    const [path, search = ''] = location.hash.split('?');
    const params = new URLSearchParams(search);
    if (params.has('add')) {
      params.delete('add');
      const rest = params.toString();
      history.replaceState(history.state, '', `${path}${rest ? `?${rest}` : ''}`);
      window.dispatchEvent(new HashChangeEvent('hashchange'));
    }
  };
  const all = newestRecords(snapshot?.records ?? []);
  const needle = query.trim().toLocaleLowerCase();
  const records = all.filter(
    (record) =>
      (filter === 'All records' ||
        (filter === 'Symptoms' ? Boolean(record.symptomEntry) : record.kind === filter)) &&
      (!needle ||
        [
          record.title,
          record.provider,
          record.kind,
          record.text,
          record.summary,
          record.date,
          formatDate(record.date),
          ...record.tags,
        ]
          .join(' ')
          .toLocaleLowerCase()
          .includes(needle)),
  );
  return (
    <div className="stack">
      <PageHeading
        eyebrow="Your health information"
        title="Records"
        description="Documents, symptom entries, and visit memories — together in one place."
        actions={
          <>
            <Button variant="secondary" onClick={() => setDialog('symptom')}>
              <NotebookPen size={18} /> Log symptoms
            </Button>
            <Button onClick={() => setDialog('import')}>
              <Upload size={18} /> Add a record
            </Button>
          </>
        }
      />
      <Card className="records-toolbar">
        <label className="record-search">
          <Search size={20} aria-hidden="true" />
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search records, dates, or details"
            aria-label="Search records"
          />
        </label>
        <label className="record-filter">
          <span className="small muted">Show</span>
          <select
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
            aria-label="Record category"
          >
            {['All records', 'Symptoms', 'Notes', 'Labs', 'Imaging', 'Procedure', 'Scan', 'Recording'].map(
              (item) => (
                <option key={item}>{item}</option>
              ),
            )}
          </select>
        </label>
      </Card>
      <div className="row section-heading">
        <h2>{filter}</h2>
        <span className="muted small">
          {records.length} {records.length === 1 ? 'record' : 'records'}
        </span>
      </div>
      {records.length ? (
        <Card className="record-list">
          {records.map((record) => (
            <a key={record.id} href={`#/records/${encodeURIComponent(record.id)}`} className="record-row">
              <span className="record-icon">
                <RecordSymbol record={record} />
              </span>
              <div className="record-main">
                <h3>{demoLabel(record.title, record.isDemo)}</h3>
                <p className="record-meta">
                  {record.kind} · {formatDate(record.date)}
                </p>
                <p className="small muted">{demoLabel(record.provider, record.isDemo)}</p>
              </div>
              <div className="record-row-status">
                {record.symptomEntry && <Badge tone="accent">Your entry</Badge>}
              </div>
              <ChevronRight size={19} aria-hidden="true" />
            </a>
          ))}
        </Card>
      ) : (
        <Card>
          <EmptyState
            title={
              loading
                ? 'Opening your records…'
                : query || filter !== 'All records'
                  ? 'No matching records'
                  : 'Build your health history'
            }
          >
            <p>
              {query || filter !== 'All records'
                ? 'Try another phrase or show all records.'
                : 'Add a medical document or log a symptom to keep useful details close.'}
            </p>
            {query || filter !== 'All records' ? (
              <Button
                variant="secondary"
                onClick={() => {
                  setQuery('');
                  setFilter('All records');
                }}
              >
                Clear filters
              </Button>
            ) : (
              <Button onClick={() => setDialog('import')}>Add your first record</Button>
            )}
          </EmptyState>
        </Card>
      )}
      {dialog === 'import' && <ImportDialog onClose={closeDialog} />}
      {dialog === 'symptom' && <SymptomDialog onClose={closeDialog} />}
    </div>
  );
}
