// Purpose: Log an existing account in at /login and open its workspace.
// Inputs: Email and password typed by the user; an optional ?reason=session query from an ended session.
// Outputs: A validated log-in request, inline field errors, the server's reason on failure, or navigation to /app.
// Side effects: One POST /v1/auth/login; on success writes the session to localStorage and calls location.assign.

import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { AuthAPI, emailProblem, passwordProblem } from '../core/auth';
import { readSession, writeSession } from '../core/session';
import { AccountShell, FormStatus, PasswordField, TextField } from './accountForm';

// MARK: - Validation runs on submit; the server's reason is shown verbatim, never guessed at
export function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});
  const [failure, setFailure] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const existing = useMemo(() => readSession(), []);
  const ended = useMemo(() => new URLSearchParams(location.search).get('reason') === 'session', []);
  useEffect(() => {
    document.title = 'Log in · Reva';
  }, []);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (submitting) return;
    const next = {
      email: emailProblem(email) ?? undefined,
      password: password ? (passwordProblem(password) ?? undefined) : 'Enter your password.',
    };
    setErrors(next);
    setFailure(null);
    if (next.email || next.password) return;
    setSubmitting(true);
    try {
      const session = await new AuthAPI().login({ email, password });
      if (!writeSession(session))
        throw new Error('This browser could not keep you logged in. Allow site storage and try again.');
      location.assign('/app');
    } catch (error) {
      setFailure(error instanceof Error ? error.message : 'Log-in did not complete. Try again.');
      setSubmitting(false);
    }
  }
  return (
    <AccountShell
      eyebrow="Log in"
      title="Welcome back."
      lede="Your records, questions and visit notes, exactly where you left them."
    >
      {existing && !ended && (
        <p className="account-note">
          You are logged in as {existing.user.name}.{' '}
          <a href="/app" className="landing-demo">
            Open your workspace
          </a>
        </p>
      )}
      <form className="account-form" onSubmit={submit} noValidate>
        <TextField
          label="Email"
          type="email"
          value={email}
          onChange={(value) => {
            setEmail(value);
            if (errors.email) setErrors((current) => ({ ...current, email: undefined }));
          }}
          error={errors.email}
          autoComplete="email"
          disabled={submitting}
          maxLength={254}
        />
        <PasswordField
          label="Password"
          value={password}
          onChange={(value) => {
            setPassword(value);
            if (errors.password) setErrors((current) => ({ ...current, password: undefined }));
          }}
          error={errors.password}
          autoComplete="current-password"
          disabled={submitting}
        />
        <FormStatus error={failure} notice={ended ? 'Your session ended. Log in again to continue.' : null} />
        <button type="submit" className="button button-primary account-submit" disabled={submitting}>
          {submitting ? 'Logging in…' : 'Log in'}
        </button>
      </form>
      <div className="account-links">
        <a href="/signup">New here? Create an account</a>
        <a href="/">Back to home</a>
      </div>
    </AccountShell>
  );
}
