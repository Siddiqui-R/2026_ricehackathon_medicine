// Purpose: Give a signed-in account its Settings cards: identity/session, password change and deletion.
// Inputs: The account user and session expiry from Reva context, plus passwords typed into the forms.
// Outputs: An Account card with Log out / Log out everywhere, a Change password form, and a typed-confirmation
//          Delete account form with honest inline errors.
// Side effects: Calls the store's account actions, which contact /v1/auth/* and may leave the workspace.

import { useState, type FormEvent } from 'react';
import { KeyRound, LogOut, Trash2, UserRound } from 'lucide-react';
import { useReva } from '../core/RevaContext';
import { passwordProblem } from '../core/auth';
import { formatDate } from '../core/domain';
import { initialsFor } from '../core/account';
import { Button, Card, Field, Modal } from '../components/ui';

// MARK: - Account identity and sessions; "everywhere" is confirmed because it also ends this session
export function AccountCard({
  working,
  run,
}: {
  working: boolean;
  run: (action: () => Promise<void>) => void;
}) {
  const store = useReva();
  const [confirm, setConfirm] = useState(false);
  const user = store.accountUser;
  if (!user) return null;
  const expiry = store.account?.expiresAt;
  return (
    <Card className="settings-card account-card">
      <div className="card-title">
        <span className="avatar avatar-large" aria-hidden="true">
          {initialsFor(user.name) || <UserRound size={20} />}
        </span>
        <div>
          <h2>{user.name}</h2>
          <p className="muted">{user.email}</p>
        </div>
      </div>
      <dl className="account-meta">
        <div>
          <dt>Account</dt>
          <dd>Created {formatDate(user.createdAt)}</dd>
        </div>
        <div>
          <dt>This session</dt>
          <dd>{expiry ? `Expires ${formatDate(expiry, true)}` : 'Expiry unknown'}</dd>
        </div>
        <div>
          <dt>Server copy</dt>
          <dd>
            {store.serverRevision == null
              ? 'Not checked yet'
              : `Revision ${store.serverRevision}${store.busy ? ' · syncing' : ''}`}
          </dd>
        </div>
      </dl>
      <p>
        Changes you save here are sent to your account about a second later. Log out on a shared computer;
        this browser keeps a private copy until you delete the account.
      </p>
      <div className="form-actions account-actions">
        <Button variant="ghost" disabled={working || store.busy} onClick={() => setConfirm(true)}>
          Log out everywhere
        </Button>
        <Button variant="secondary" disabled={working || store.busy} onClick={() => run(store.logout)}>
          <LogOut size={16} />
          Log out
        </Button>
      </div>
      {confirm && (
        <Modal title="Log out of every device?" onClose={() => !working && setConfirm(false)}>
          <p>
            Every session for this account will end, including this one. Log in again on each device you still
            use.
          </p>
          <div className="form-actions">
            <Button variant="secondary" disabled={working} onClick={() => setConfirm(false)}>
              Keep my sessions
            </Button>
            <Button
              disabled={working}
              onClick={() =>
                run(async () => {
                  await store.logoutAll();
                  setConfirm(false);
                })
              }
            >
              {working ? 'Working…' : 'Log out everywhere'}
            </Button>
          </div>
        </Modal>
      )}
    </Card>
  );
}

// MARK: - Password change: the same length rules as sign-up; other sessions end on success
export function ChangePasswordCard({
  working,
  run,
}: {
  working: boolean;
  run: (action: () => Promise<void>) => void;
}) {
  const store = useReva();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [problem, setProblem] = useState<string | null>(null);
  function submit(event: FormEvent) {
    event.preventDefault();
    const issue = !current
      ? 'Enter your current password.'
      : (passwordProblem(next, store.accountUser?.email ?? '') ??
        (next !== again ? 'The new passwords do not match.' : null) ??
        (next === current ? 'Choose a new password that differs from the current one.' : null));
    setProblem(issue);
    if (issue) return;
    run(async () => {
      await store.changePassword(current, next);
      setCurrent('');
      setNext('');
      setAgain('');
    });
  }
  return (
    <Card className="settings-card">
      <div className="card-title">
        <span className="action-icon">
          <KeyRound size={22} />
        </span>
        <div>
          <h2>Change password</h2>
          <p className="muted">Other devices will need to log in again.</p>
        </div>
      </div>
      <form className="account-form-grid" onSubmit={submit} noValidate>
        <Field label="Current password">
          <input
            type="password"
            autoComplete="current-password"
            value={current}
            onChange={(event) => setCurrent(event.target.value)}
            disabled={working || store.busy}
          />
        </Field>
        <Field label="New password" hint="At least 10 characters, not your email.">
          <input
            type="password"
            autoComplete="new-password"
            value={next}
            onChange={(event) => setNext(event.target.value)}
            disabled={working || store.busy}
            aria-invalid={problem ? true : undefined}
          />
        </Field>
        <Field label="Repeat new password">
          <input
            type="password"
            autoComplete="new-password"
            value={again}
            onChange={(event) => setAgain(event.target.value)}
            disabled={working || store.busy}
          />
        </Field>
        <div role="alert" className={problem ? 'inline-error' : undefined}>
          {problem}
        </div>
        <div className="form-actions">
          <Button type="submit" disabled={working || store.busy}>
            Change password
          </Button>
        </div>
      </form>
    </Card>
  );
}

// MARK: - Deletion needs the email typed exactly plus the password; the server deletes, then the local copy goes
export function DeleteAccountCard({
  working,
  run,
}: {
  working: boolean;
  run: (action: () => Promise<void>) => void;
}) {
  const store = useReva();
  const [typed, setTyped] = useState('');
  const [password, setPassword] = useState('');
  const [problem, setProblem] = useState<string | null>(null);
  const email = store.accountUser?.email ?? '';
  const matches = typed.trim().toLowerCase() === email.toLowerCase() && email.length > 0;
  function submit(event: FormEvent) {
    event.preventDefault();
    const issue = !matches
      ? 'Type your account email exactly to confirm.'
      : !password
        ? 'Enter your password to delete the account.'
        : null;
    setProblem(issue);
    if (issue) return;
    run(() => store.deleteAccount(password));
  }
  return (
    <Card className="settings-card danger-card">
      <div className="card-title">
        <span className="action-icon warm">
          <Trash2 size={22} />
        </span>
        <div>
          <h2>Delete account</h2>
          <p className="muted">Permanent. There is no recovery afterwards.</p>
        </div>
      </div>
      <p>
        Deleting removes your account, every session, and all records, originals and visits stored on the
        server. This browser’s private copy is removed too. Export or print anything you want to keep first.
      </p>
      <form className="account-form-grid" onSubmit={submit} noValidate>
        <Field label={`Type ${email || 'your email'} to confirm`}>
          <input
            type="text"
            autoComplete="off"
            spellCheck={false}
            autoCapitalize="none"
            value={typed}
            onChange={(event) => setTyped(event.target.value)}
            disabled={working || store.busy}
            aria-invalid={problem && !matches ? true : undefined}
          />
        </Field>
        <Field label="Password">
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            disabled={working || store.busy}
          />
        </Field>
        <div role="alert" className={problem ? 'inline-error' : undefined}>
          {problem}
        </div>
        <div className="form-actions">
          <Button type="submit" variant="danger" disabled={working || store.busy || !matches}>
            Delete my account permanently
          </Button>
        </div>
      </form>
    </Card>
  );
}
