// Purpose: Keep account actions in the patient plaque instead of separate navigation items.
// Inputs: The current profile, demo/account mode, busy state, and the existing sign-out action.
// Outputs: A keyboard-accessible account disclosure with settings, sign out, and optional demo switching.
// Side effects: Dismisses on outside clicks, Escape, or navigation; delegates session and demo changes.

import { useEffect, useId, useRef, useState } from 'react';
import { ChevronsUpDown, LogOut, Settings } from 'lucide-react';
import type { PatientProfile } from '../core/models';
import { demoLabel } from '../core/presentation';
import { DemoSwitcher } from '../features/demo/DemoSwitcher';
import '../styles/account-menu.css';

// MARK: - One disclosure serves the desktop plaque and the compact phone avatar
export function AccountMenu({
  profile,
  demo,
  busy,
  onSignOut,
  compact = false,
}: {
  profile: PatientProfile;
  demo: boolean;
  busy: boolean;
  onSignOut: () => void;
  compact?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const id = useId();
  const name = demoLabel(profile.name, profile.isDemo);
  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || root.current?.querySelector('dialog[open]')) return;
      setOpen(false);
      trigger.current?.focus();
    };
    const navigate = () => setOpen(false);
    document.addEventListener('pointerdown', outside);
    document.addEventListener('keydown', escape);
    window.addEventListener('hashchange', navigate);
    return () => {
      document.removeEventListener('pointerdown', outside);
      document.removeEventListener('keydown', escape);
      window.removeEventListener('hashchange', navigate);
    };
  }, [open]);
  return (
    <div ref={root} className={`account-menu${compact ? ' account-menu-compact' : ''}`}>
      <button
        ref={trigger}
        type="button"
        className="patient-link account-menu-trigger"
        aria-label={`${name} — account options`}
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen(!open)}
      >
        <span className="avatar" aria-hidden="true">
          {profile.initials}
        </span>
        <span className="account-menu-identity">
          <strong>{name}</strong>
          <small>{demo ? 'Demo account' : 'Your account'}</small>
        </span>
        <ChevronsUpDown size={15} aria-hidden="true" />
      </button>
      {open && (
        <div id={id} className="account-menu-panel" role="group" aria-label="Account options">
          {demo && <DemoSwitcher disabled={busy} label="Switch account" className="account-menu-item" />}
          <a className="account-menu-item" href="#/settings" onClick={() => setOpen(false)}>
            <Settings size={17} aria-hidden="true" /> View settings
          </a>
          <button type="button" className="account-menu-item" disabled={busy} onClick={onSignOut}>
            <LogOut size={17} aria-hidden="true" /> Sign out
          </button>
        </div>
      )}
    </div>
  );
}
