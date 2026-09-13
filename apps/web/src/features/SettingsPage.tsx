// Purpose: Explain automatic account persistence and configure connected services.
// Inputs: Reva connection state; in demo mode a session-only owner token, in account mode the signed-in user.
// Outputs: Service configuration, a reviewed demo reset (demo only), and account cards
//          (identity, password change, deletion) in account mode.
// Side effects: May check server configuration or reset the local demo after confirmation.

import { useState } from 'react';
import { CheckCircle2, KeyRound, Link2, RefreshCw, RotateCcw, ShieldCheck } from 'lucide-react';
import { useReva } from '../core/RevaContext';
import { Badge, Button, Card, Field, Modal, PageHeading } from '../components/ui';
import { AccountCard, ChangePasswordCard, DeleteAccountCard } from './AccountSettings';

// MARK: - Service configuration and account management; synchronization runs automatically
export function SettingsPage() {
  const store = useReva();
  const [confirmReset, setConfirmReset] = useState(false);
  const [working, setWorking] = useState(false);
  const account = store.mode === 'account';
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
        title="Settings & connections"
        description={
          account
            ? 'Your account, your sessions, and connected services. Changes sync automatically.'
            : 'Explore the local demo and configure connected services.'
        }
      />
      <div className="settings-grid">
        <div className="stack">
          {account ? (
            <AccountCard working={working} run={run} />
          ) : (
            <Card className="settings-card">
              <div className="card-title">
                <span className="action-icon">
                  <Link2 size={22} />
                </span>
                <div>
                  <h2>Connect to Reva</h2>
                  <p className="muted">Configure services for this demo.</p>
                </div>
              </div>
              <p>
                Demo records stay in this browser. Connect to use the services configured on your Reva server,
                or sign in to keep your own records up to date across devices.
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
                    ? 'Check which services are available.'
                    : `Server revision ${store.serverRevision}`}
                </span>
                <Button disabled={working || store.busy} onClick={() => run(store.checkServer)}>
                  <RefreshCw size={16} />
                  Check connection
                </Button>
              </div>
            </Card>
          )}
          {account ? (
            <>
              <ChangePasswordCard working={working} run={run} />
              <DeleteAccountCard working={working} run={run} />
            </>
          ) : (
            <Card className="settings-card">
              <h2>Demo</h2>
              <p className="muted">
                Restore the original demonstration records in this browser. This replaces active local
                changes; it does not change the server or your iPhone.
              </p>
              <Button variant="ghost" disabled={working || store.busy} onClick={() => setConfirmReset(true)}>
                <RotateCcw size={16} />
                Restore demo
              </Button>
            </Card>
          )}
        </div>
        <div className="stack">
          <Card className="settings-card">
            <div className="card-title">
              <ShieldCheck size={23} />
              <h2>Connected services</h2>
            </div>
            <p className="muted small">
              Provider accounts are configured on the Reva server. Check availability if a service is missing.
            </p>
            <Button
              variant="secondary"
              disabled={working || store.busy}
              onClick={() => run(store.checkServer)}
            >
              <RefreshCw size={16} />
              Check services
            </Button>
            {[
              { key: 'gemini', title: 'Document & visit AI', detail: 'Relevant summaries and preparation' },
              {
                key: 'transcription',
                title: 'Audio transcription',
                detail: 'Reviewable words from saved audio',
              },
            ].map((item) => {
              const status = store.providers?.[item.key as 'gemini' | 'transcription'];
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
              <strong>{account ? 'Automatic account sync' : 'Saved in this browser'}</strong>
              <p>
                {account
                  ? 'Records and originals sync automatically to your account and between signed-in devices. This browser keeps a private copy for offline reading. Changes made offline sync when you reconnect.'
                  : 'Demo records and originals stay in this browser. Clearing site data removes this copy. Sign in to use your own account with automatic syncing across devices.'}
              </p>
            </div>
          </div>
          <div className="storage-note">
            <KeyRound size={21} />
            <div>
              <strong>Connected services, explained</strong>
              <p>
                Provider keys stay on the server. In your account, configured AI keeps your medical profile up
                to date from your reports. Visit briefs and document summaries run when you request them.
              </p>
            </div>
          </div>
        </div>
      </div>
      {confirmReset && (
        <Modal title="Restore the demo?" onClose={() => !working && setConfirmReset(false)}>
          <p>
            Your active local edits will be replaced with the original demo data. Other devices and the server
            are unchanged.
          </p>
          <div className="form-actions">
            <Button variant="secondary" disabled={working} onClick={() => setConfirmReset(false)}>
              Keep my current copy
            </Button>
            <Button
              disabled={working}
              onClick={() =>
                run(async () => {
                  await store.resetDemo();
                  setConfirmReset(false);
                })
              }
            >
              {working ? 'Working…' : 'Restore demo'}
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}
