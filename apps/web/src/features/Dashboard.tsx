// Purpose: Put upcoming care, recent source records, and quick medical information in one overview.
// Inputs: The locally persisted profile, visits, and records from RevaContext.
// Outputs: Actionable appointment and record links with clearly labeled source state.
// Side effects: Navigation only; preparation and edits happen on their dedicated screens.

import { useState } from 'react';
import {
  Activity,
  ArrowRight,
  CalendarDays,
  ChevronRight,
  FilePlus2,
  FileText,
  HeartPulse,
  Mic,
  Pill,
  ShieldAlert,
} from 'lucide-react';
import { useReva } from '../core/RevaContext';
import { defaultTimeZone, formatDate } from '../core/domain';
import { demoLabel } from '../core/presentation';
import { Card, Modal } from '../components/ui';
import { VisitPreparation } from './visits/VisitPreparation';
import { RecordingCapture } from './visits/RecordingCapture';
import { RecordingDetail } from './visits/RecordingDetail';

// MARK: - Dashboard projections never mutate the underlying clinical data
export function Dashboard() {
  const { snapshot } = useReva();
  const [prepare, setPrepare] = useState(false);
  const [capture, setCapture] = useState(false);
  const [recordingID, setRecordingID] = useState<string | null>(null);
  if (!snapshot) return null;
  const { profile, records, recordings } = snapshot;
  const recording = recordings.find((item) => item.id === recordingID);
  const sessions = [...recordings].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
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
      <div className="home-care-actions" aria-label="Visit actions">
        <button onClick={() => setPrepare(true)}>
          <CalendarDays size={26} />
          <span>
            <strong>Upcoming visit</strong>
            <small>Run a pre-visit brief</small>
          </span>
        </button>
        <button onClick={() => setCapture(true)}>
          <Mic size={26} />
          <span>
            <strong>Record session</strong>
            <small>Record, transcribe, summarize</small>
          </span>
        </button>
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
      </div>

      <div className="dashboard-grid">
        <div className="dashboard-primary">
          {sessions.length > 0 && (
            <>
              <div className="section-heading">
                <h2>Session recordings</h2>
              </div>
              <Card className="recent-records">
                <div className="record-list">
                  {sessions.map((session) => (
                    <button
                      className="record-row session-row"
                      key={session.id}
                      onClick={() => setRecordingID(session.id)}
                    >
                      <span className="record-icon">
                        <Mic size={20} />
                      </span>
                      <span className="record-main">
                        <strong>{demoLabel(session.title, session.isSample)}</strong>
                        <span className="record-meta">
                          {formatDate(session.createdAt)}
                          {session.isSample ? ' · Sample' : ''}
                        </span>
                      </span>
                      <ChevronRight size={17} />
                    </button>
                  ))}
                </div>
              </Card>
            </>
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
      {prepare && (
        <Modal title="Upcoming visit" onClose={() => setPrepare(false)} wide>
          <VisitPreparation />
        </Modal>
      )}
      {capture && <RecordingCapture onClose={() => setCapture(false)} onSaved={setRecordingID} />}
      {recording && <RecordingDetail recording={recording} onClose={() => setRecordingID(null)} />}
    </div>
  );
}
