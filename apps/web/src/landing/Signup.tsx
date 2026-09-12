// Purpose: Create a new account at /signup and open its empty personal workspace.
// Inputs: Name, email, a new password and its confirmation typed by the user.
// Outputs: A validated sign-up request, inline field errors, the server's reason on failure, or navigation to /app.
// Side effects: One POST /v1/auth/signup; on success writes the session to localStorage and calls location.assign.

import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { AuthAPI, emailProblem, nameProblem, passwordProblem } from '../core/auth';
import { readSession, writeSession } from '../core/session';
import { AccountShell, FormStatus, PasswordField, TextField } from './accountForm';

// MARK: - The same policy the server enforces is checked first so most mistakes never leave the browser
export function Signup() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [errors, setErrors] = useState<{
    name?: string;
    email?: string;
    password?: string;
    confirmPassword?: string;
  }>({});
  const [failure, setFailure] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const existing = useMemo(() => readSession(), []);
  useEffect(() => {
    document.title = 'Sign up · Reva';
  }, []);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (submitting) return;
    const next = {
      name: nameProblem(name) ?? undefined,
      email: emailProblem(email) ?? undefined,
      password: passwordProblem(password, email) ?? undefined,
      confirmPassword: !confirmPassword
        ? 'Confirm your password.'
        : confirmPassword !== password
          ? 'Passwords do not match.'
          : undefined,
    };
    setErrors(next);
    setFailure(null);
    if (next.name || next.email || next.password || next.confirmPassword) return;
    setSubmitting(true);
    try {
      const session = await new AuthAPI().signup({ name, email, password });
      if (!writeSession(session))
        throw new Error(
          'Your account was created, but this browser could not keep you logged in. Allow site storage and log in.',
        );
      location.assign('/app');
    } catch (error) {
      setFailure(error instanceof Error ? error.message : 'Sign-up did not complete. Try again.');
      setSubmitting(false);
    }
  }
  const clear = (key: 'name' | 'email' | 'password' | 'confirmPassword') => {
    if (errors[key]) setErrors((current) => ({ ...current, [key]: undefined }));
  };
  return (
    <AccountShell
      title="Start with your own records."
      lede="A private workspace for your documents, questions and visits. Yours alone, on this server."
    >
      {existing && (
        <p className="account-note">
          You are already logged in as {existing.user.name}.{' '}
          <a href="/app" className="landing-demo">
            Open your workspace
          </a>
        </p>
      )}
      <form className="account-form" onSubmit={submit} noValidate>
        <TextField
          label="Name"
          value={name}
          onChange={(value) => {
            setName(value);
            clear('name');
          }}
          error={errors.name}
          help="Shown in your workspace and on printed visit briefs."
          autoComplete="name"
          disabled={submitting}
          maxLength={80}
        />
        <TextField
          label="Email"
          type="email"
          value={email}
          onChange={(value) => {
            setEmail(value);
            clear('email');
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
            clear('password');
            clear('confirmPassword');
          }}
          error={errors.password}
          help="At least 8 characters, 1 capital letter, 1 number, and 1 symbol."
          autoComplete="new-password"
          disabled={submitting}
        />
        <PasswordField
          label="Confirm password"
          value={confirmPassword}
          onChange={(value) => {
            setConfirmPassword(value);
            clear('confirmPassword');
          }}
          error={errors.confirmPassword}
          autoComplete="new-password"
          disabled={submitting}
        />
        <FormStatus error={failure} />
        <button type="submit" className="button button-primary account-submit" disabled={submitting}>
          {submitting ? 'Creating your account…' : 'Create account'}
        </button>
      </form>
      <div className="account-links">
        <a href="/login">Already have an account? Log in</a>
        <a href="/">Back to home</a>
      </div>
    </AccountShell>
  );
}
