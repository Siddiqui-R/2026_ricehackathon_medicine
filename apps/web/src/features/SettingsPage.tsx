// Purpose: Make browser persistence and explicit shared-server operations understandable and controllable.
// Inputs: Reva connection state and a session-only owner token supplied by the user.
// Outputs: Configuration status, deliberate push/pull, and a reviewed demo reset.
// Side effects: May contact the local Swift server or replace active browser state after confirmation.

import { useState } from 'react';
import {
  ArrowDownToLine,
  ArrowUpFromLine,
  CheckCircle2,
  Database,
  KeyRound,
  Link2,
  RefreshCw,
  RotateCcw,
  ShieldCheck,
} from 'lucide-react';
import { useReva } from '../core/RevaContext';
import { Badge, Button, Card, Field, Modal, PageHeading } from '../components/ui';

// MARK: - Explicit actions separate configuration discovery from data replacement
export function SettingsPage() {
  const store = useReva();
  const [confirm, setConfirm] = useState<'pull' | 'reset' | null>(null);
  const [working, setWorking] = useState(false);
  async function run(action: () => Promise<void>) {
    setWorking(true);
    try {
      await action();
    } catch (error) {
      store.reportError(error);
    } finally {
      setWorking(false);
    }
  }
  return (
    <div className="settings-page">
      <PageHeading
        eyebrow="YOUR WORKSPACE"
        title="Settings & connections"
        description="Choose when to connect and when to share your latest changes."
      />
      <div className="settings-grid">
        <div className="stack">
          <Card className="settings-card">
            <div className="card-title">
              <span className="action-icon">
                <Link2 size={22} />
              </span>
              <div>
                <h2>Connect to Reva</h2>
                <p className="muted">Use the same workspace as your iPhone.</p>
              </div>
            </div>
            <p>
              The browser keeps its own saved copy. Connect to the Reva server to exchange records,
              appointments, and your medical profile.
            </p>
            <Field
              label="Workspace access token"
              hint="Kept only for this browser session. Use the token configured on your Reva server."
            >
              <input
                type="password"
                autoComplete="off"
                value={store.token}
                onChange={(event) => store.setToken(event.target.value)}
                placeholder="Enter your workspace token"
              />
            </Field>
            <div className="form-actions">
              <span className="small muted">
                {store.serverRevision == null
                  ? 'Check your connection before syncing.'
                  : `Server revision ${store.serverRevision}`}
              </span>
              <Button disabled={working || store.busy} onClick={() => run(store.checkServer)}>
                <RefreshCw size={16} />
                Check connection
              </Button>
            </div>
          </Card>
          <Card className="settings-card">
            <div className="card-title">
              <Database size={23} />
              <div>
                <h2>Keep your devices in step</h2>
                <p className="muted">Transfers happen when you choose.</p>
              </div>
            </div>
            <div className="sync-options">
              <div>
                <h3>Send this browser’s changes</h3>
                <p>
                  Replace the server’s snapshot with this browser’s records and profile. A newer server
                  revision requires review first.
                </p>
                <Button
                  variant="secondary"
                  disabled={working || store.busy || store.serverRevision == null}
                  onClick={() => run(store.pushToServer)}
                >
                  <ArrowUpFromLine size={16} />
                  Push to server
                </Button>
              </div>
              <div>
                <h3>Get the server’s latest copy</h3>
                <p>
                  Download originals and replace this browser’s active records, visits, and profile with the
                  server copy.
                </p>
                <Button
                  variant="secondary"
                  disabled={working || store.busy}
                  onClick={() => setConfirm('pull')}
                >
                  <ArrowDownToLine size={16} />
                  Pull from server
                </Button>
              </div>
            </div>
          </Card>
          <Card className="settings-card">
            <h2>Fictional demo</h2>
            <p className="muted">
              Restore the original demonstration records in this browser. This replaces active local changes;
              it does not change the server or your iPhone.
            </p>
            <Button variant="ghost" disabled={working || store.busy} onClick={() => setConfirm('reset')}>
              <RotateCcw size={16} />
              Restore fictional demo
            </Button>
          </Card>
        </div>
        <div className="stack">
          <Card className="settings-card">
            <div className="card-title">
              <ShieldCheck size={23} />
              <h2>Connected services</h2>
            </div>
            <p className="muted small">
              Availability appears after checking your connection. Provider accounts are configured on the
              Reva server.
            </p>
            {[
              { key: 'gemini', title: 'Document & visit AI', detail: 'Relevant summaries and preparation' },
              {
                key: 'transcription',
                title: 'Audio transcription',
                detail: 'Reviewable words from saved audio',
              },
              { key: 'booking', title: 'Appointment calls', detail: 'Only after your explicit review' },
            ].map((item) => {
              const status = store.providers?.[item.key as 'gemini' | 'transcription' | 'booking'];
              return (
                <div className="service-status" key={item.key}>
                  <div>
                    <strong>{item.title}</strong>
                    <small>{item.detail}</small>
                  </div>
                  <Badge tone={status?.configured ? 'accent' : 'neutral'}>
                    {status?.configured ? 'Configured' : store.providers ? 'Not set up' : 'Not checked'}
                  </Badge>
                </div>
              );
            })}
            <label className="toggle-row">
              <span>
                <strong>Connected AI preparation</strong>
                <small>Send relevant record content when you prepare a visit or request a summary.</small>
              </span>
              <input
                type="checkbox"
                role="switch"
                checked={store.connectedAI}
                disabled={!store.providers?.gemini.configured || working || store.busy}
                onChange={(event) => store.setConnectedAI(event.target.checked)}
              />
            </label>
          </Card>
          <div className="storage-note">
            <CheckCircle2 size={21} />
            <div>
              <strong>Saved in this browser</strong>
              <p>
                Records and originals use local browser storage. Clearing site data removes this copy. Push to
                your server before switching browsers if you want to bring your history with you.
              </p>
            </div>
          </div>
          <div className="storage-note">
            <KeyRound size={21} />
            <div>
              <strong>Your choice, every time</strong>
              <p>
                Provider keys stay on the server. Importing and reviewing a document can work locally;
                connected requests use the services you enable.
              </p>
            </div>
          </div>
        </div>
      </div>
      {confirm && (
        <Modal
          title={confirm === 'pull' ? 'Replace this browser’s copy?' : 'Restore the fictional demo?'}
          onClose={() => !working && setConfirm(null)}
        >
          <p>
            {confirm === 'pull'
              ? 'Your active browser records, appointments, and medical profile will be replaced by the server copy. Unsynced local edits will leave the active snapshot.'
              : 'Your active local edits will be replaced with the original fictional data. Other devices and the server are unchanged.'}
          </p>
          <div className="form-actions">
            <Button variant="secondary" disabled={working} onClick={() => setConfirm(null)}>
              Keep my current copy
            </Button>
            <Button
              disabled={working}
              onClick={() =>
                run(async () => {
                  if (confirm === 'pull') await store.pullFromServer();
                  else await store.resetDemo();
                  setConfirm(null);
                })
              }
            >
              {working ? 'Working…' : confirm === 'pull' ? 'Pull and replace' : 'Restore demo'}
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}
