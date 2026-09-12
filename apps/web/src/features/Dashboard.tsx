// Purpose: Put upcoming care, recent source records, and quick medical information in one overview.
// Inputs: The locally persisted profile, visits, and records from RevaContext.
// Outputs: Actionable appointment and record links with clearly labeled source state.
// Side effects: Navigation only; preparation and edits happen on their dedicated screens.

import {
  Activity,
  ArrowRight,
  CalendarDays,
  ChevronRight,
  ClipboardList,
  FilePlus2,
  FileText,
  HeartPulse,
  MapPin,
  Pill,
  Plus,
  ShieldAlert,
  Stethoscope,
} from 'lucide-react';
import { useReva } from '../core/RevaContext';
import { defaultTimeZone, displayTimeZone, formatDate } from '../core/domain';
import { demoLabel } from '../core/presentation';
import { Badge, Card } from '../components/ui';

// MARK: - Dashboard projections never mutate the underlying clinical data
export function Dashboard() {
  const { snapshot } = useReva();
  if (!snapshot) return null;
  const { profile, records, visits } = snapshot;
  const upcoming = visits
    .filter((visit) => visit.status !== 'completed')
    .sort((a, b) => a.date.localeCompare(b.date));
  const next = upcoming[0];
  const recent = [...records]
    .sort((a, b) => b.date.localeCompare(a.date) || b.uploadedAt.localeCompare(a.uploadedAt))
    .slice(0, 5);
  const firstName = profile.name.split(' ')[0];
  const today = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    timeZone: defaultTimeZone,
  }).format(new Date());

  // MARK: - Task-first welcome and action strip
  return (
    <div className="dashboard">
      <div className="dashboard-welcome">
        <div>
          <p className="eyebrow">YOUR HEALTH, TOGETHER</p>
          <h1>
            Hello, {firstName}
            <span className="greeting-dot">.</span>
          </h1>
          <p>Making every appointment meaningful</p>
        </div>
        <span className="today">
          <CalendarDays size={16} />
          {today}
        </span>
      </div>
      <div className="quick-actions" aria-label="Quick actions">
        <a href="#/records?add=import">
          <span className="action-icon">
            <FilePlus2 size={23} />
          </span>
          <span>
            <strong>Add a health record</strong>
            <small>Upload a document or scan</small>
          </span>
          <ChevronRight size={18} />
        </a>
        <a href="#/records?add=symptom">
          <span className="action-icon warm">
            <Activity size={23} />
          </span>
          <span>
            <strong>Log a symptom</strong>
            <small>Remember how you’re feeling</small>
          </span>
          <ChevronRight size={18} />
        </a>
        <a href="#/visits?add=visit">
          <span className="action-icon soft">
            <CalendarDays size={23} />
          </span>
          <span>
            <strong>Add an appointment</strong>
            <small>Start preparing for your visit</small>
          </span>
          <ChevronRight size={18} />
        </a>
      </div>

      <div className="dashboard-grid">
        <div className="dashboard-primary">
          <div className="section-heading">
            <h2>Your next appointment</h2>
            <a className="text-link" href="#/visits">
              All appointments <ArrowRight size={15} />
            </a>
          </div>
          {next ? (
            <Card className="next-appointment">
              <div className="appointment-top">
                <Badge tone="accent">UPCOMING VISIT</Badge>
                <span className="muted small">{next.type}</span>
              </div>
              <div className="appointment-body">
                <div className="date-tile">
                  <span>
                    {new Intl.DateTimeFormat('en-US', {
                      month: 'short',
                      timeZone: displayTimeZone(next.timeZone),
                    }).format(new Date(next.date))}
                  </span>
                  <strong>
                    {new Intl.DateTimeFormat('en-US', {
                      day: 'numeric',
                      timeZone: displayTimeZone(next.timeZone),
                    }).format(new Date(next.date))}
                  </strong>
                </div>
                <div className="appointment-info">
                  <h3>
                    <a href={`#/visits/${next.id}`}>{next.title}</a>
                  </h3>
                  <p>
                    <Stethoscope size={15} />
                    {demoLabel(next.provider, profile.isDemo) || 'Provider to be confirmed'}
                  </p>
                  <p>
                    <MapPin size={15} />
                    {demoLabel(next.clinic, profile.isDemo) || 'Location to be confirmed'}
                  </p>
                  <p className="appointment-time">{formatDate(next.date, true, next.timeZone)}</p>
                </div>
              </div>
              <div className="appointment-focus">
                <ClipboardList size={19} />
                <div>
                  <strong>A little preparation goes a long way</strong>
                  <p>Bring your relevant history and the questions that matter to you.</p>
                  <a className="button button-primary" href={`#/visits/${next.id}`}>
                    Prepare for this visit <ArrowRight size={16} />
                  </a>
                </div>
              </div>
              <div className="appointment-footer">
                <span className="small muted">{records.length} records available for preparation</span>
              </div>
            </Card>
          ) : (
            <Card>
              <div className="empty-state">
                <CalendarDays size={32} />
                <h3>Your next visit starts here</h3>
                <p>Add an appointment to bring your history and questions together.</p>
                <a className="button button-primary" href="#/visits?add=visit">
                  <Plus size={17} />
                  Add appointment
                </a>
              </div>
            </Card>
          )}

          <div className="section-heading records-heading">
            <div>
              <h2>Recent health records</h2>
              <p>Your documents, observations, and visit memories.</p>
            </div>
            <span className="count-label">{records.length} total</span>
          </div>
          <Card className="recent-records">
            <div className="record-list">
              {recent.length ? (
                recent.map((record) => (
                  <a className="record-row" href={`#/records/${record.id}`} key={record.id}>
                    <span className={`record-icon ${record.symptomEntry ? 'review' : ''}`}>
                      {record.symptomEntry ? (
                        <Activity size={20} />
                      ) : record.kind === 'Labs' ? (
                        <HeartPulse size={20} />
                      ) : (
                        <FileText size={20} />
                      )}
                    </span>
                    <span className="record-main">
                      <strong>{demoLabel(record.title, record.isDemo)}</strong>
                      <span className="record-meta">
                        {record.kind}
                        <span aria-hidden="true"> · </span>
                        {formatDate(record.date)}
                      </span>
                    </span>
                    <ChevronRight size={17} className="row-chevron" />
                  </a>
                ))
              ) : (
                <div className="empty-state">
                  <h3>A place for your whole history</h3>
                  <p>Add your first document or symptom entry.</p>
                </div>
              )}
            </div>
            <a className="card-footer-link" href="#/records">
              View all health records <ArrowRight size={16} />
            </a>
          </Card>
        </div>

        <div className="dashboard-secondary">
          <div className="section-heading">
            <h2>Health at a glance</h2>
            <a className="icon-link" href="#/profile" aria-label="Open medical profile">
              <ArrowRight size={17} />
            </a>
          </div>
          <Card className="health-glance">
            <div className="glance-heading">
              <span className="avatar avatar-large">{profile.initials}</span>
              <div>
                <h3>{demoLabel(profile.name, profile.isDemo)}</h3>
                <p className="muted small">Your medical profile</p>
              </div>
            </div>
            <div className="glance-section">
              <h4>
                <ShieldAlert size={16} />
                Allergies <span>{profile.allergies.length}</span>
              </h4>
              {profile.allergies.length ? (
                profile.allergies.map((value) => <p key={value}>{demoLabel(value, profile.isDemo)}</p>)
              ) : (
                <p className="muted">None recorded</p>
              )}
            </div>
            <div className="glance-section">
              <h4>
                <Pill size={16} />
                Medications <span>{profile.medications.length}</span>
              </h4>
              {profile.medications.slice(0, 2).map((value) => (
                <p key={value}>{demoLabel(value, profile.isDemo)}</p>
              ))}
              {!profile.medications.length && <p className="muted">None recorded</p>}
            </div>
            <a className="card-footer-link" href="#/profile">
              View medical profile <ArrowRight size={16} />
            </a>
          </Card>
        </div>
      </div>
    </div>
  );
}
