// Purpose: Share the account-page shell and accessible form controls between /login and /signup.
// Inputs: Page copy, controlled field values, validation messages and submission state.
// Outputs: A single-column landing-styled page, labelled inputs with inline errors, and a live status line.
// Side effects: None; the password toggle only changes the input type in this document.

import { useId, useState, type ReactNode } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import { Brand } from '../components/Brand';

// MARK: - Page shell: the landing header/footer with a narrow reading measure for one form
export function AccountShell({
  title,
  lede,
  children,
}: {
  title: string;
  lede: string;
  children: ReactNode;
}) {
  return (
    <div className="landing account">
      <header className="landing-top">
        <a className="landing-home" href="/" aria-label="Reva home">
          <Brand />
        </a>
      </header>
      <main className="landing-hero" id="main">
        <h1>{title}</h1>
        <p className="landing-lede">{lede}</p>
        {children}
      </main>
      <footer className="landing-foot landing-mono">
        <span>Your data · your account</span>
        <span>No live services without your consent</span>
      </footer>
    </div>
  );
}

// MARK: - Text and password fields announce their error and never lose the typed value
interface FieldProps {
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  help?: string;
  autoComplete: string;
  disabled?: boolean;
  type?: 'text' | 'email';
  maxLength?: number;
}
export function TextField({
  label,
  value,
  onChange,
  error,
  help,
  autoComplete,
  disabled,
  type = 'text',
  maxLength,
}: FieldProps) {
  const id = useId(),
    errorID = `${id}-error`,
    helpID = `${id}-help`;
  return (
    <div className="account-field">
      <label className="account-label" htmlFor={id}>
        {label}
      </label>
      <input
        id={id}
        className="account-input"
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        autoComplete={autoComplete}
        disabled={disabled}
        maxLength={maxLength}
        spellCheck={false}
        autoCapitalize={type === 'email' ? 'none' : undefined}
        inputMode={type === 'email' ? 'email' : undefined}
        aria-invalid={error ? true : undefined}
        aria-describedby={[error ? errorID : '', help ? helpID : ''].filter(Boolean).join(' ') || undefined}
      />
      {help && !error && (
        <p id={helpID} className="account-help">
          {help}
        </p>
      )}
      {error && (
        <p id={errorID} className="account-error">
          {error}
        </p>
      )}
    </div>
  );
}
export function PasswordField({
  label,
  value,
  onChange,
  error,
  help,
  autoComplete,
  disabled,
}: Omit<FieldProps, 'type' | 'maxLength'> & { autoComplete: 'current-password' | 'new-password' }) {
  const id = useId(),
    errorID = `${id}-error`,
    helpID = `${id}-help`;
  const [visible, setVisible] = useState(false);
  return (
    <div className="account-field">
      <label className="account-label" htmlFor={id}>
        {label}
      </label>
      <div className="account-password">
        <input
          id={id}
          className="account-input"
          type={visible ? 'text' : 'password'}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          autoComplete={autoComplete}
          disabled={disabled}
          spellCheck={false}
          autoCapitalize="none"
          aria-invalid={error ? true : undefined}
          aria-describedby={[error ? errorID : '', help ? helpID : ''].filter(Boolean).join(' ') || undefined}
        />
        <button
          type="button"
          className="account-toggle"
          onClick={() => setVisible((current) => !current)}
          aria-pressed={visible}
          aria-label={visible ? 'Hide password' : 'Show password'}
          disabled={disabled}
        >
          {visible ? <EyeOff size={18} aria-hidden="true" /> : <Eye size={18} aria-hidden="true" />}
        </button>
      </div>
      {help && !error && (
        <p id={helpID} className="account-help">
          {help}
        </p>
      )}
      {error && (
        <p id={errorID} className="account-error">
          {error}
        </p>
      )}
    </div>
  );
}

// MARK: - One live region carries the server's reason or a quiet notice; it is always rendered
export function FormStatus({ error, notice }: { error?: string | null; notice?: string | null }) {
  return (
    <div className="account-status-region">
      <div
        role="alert"
        aria-live="assertive"
        className={error ? 'account-status account-status-error' : undefined}
      >
        {error}
      </div>
      <div
        role="status"
        aria-live="polite"
        className={notice ? 'account-status account-status-notice' : undefined}
      >
        {notice}
      </div>
    </div>
  );
}
