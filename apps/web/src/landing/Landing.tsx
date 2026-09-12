// Purpose: Present the shared homepage hero with sign-up, log-in and demo entry points.
// Inputs: Static copy, the shared brand mark and the stored session (if one is live).
// Outputs: A minimal hero, a drawn pulse line, three capability labels and session-aware actions.
// Side effects: Sets the document title; Log out revokes the session on the server and clears localStorage.

import { useEffect, useState } from 'react';
import { ArrowUpRight } from 'lucide-react';
import { Brand } from '../components/Brand';
import { APIError } from '../core/api';
import { AuthAPI } from '../core/auth';
import { clearSession, readSession } from '../core/session';

// MARK: - One ECG trace drawn once on load; reduced-motion users see the finished line
const trace =
  'M0 60 H200 L214 60 L224 26 L236 96 L246 60 H400 L414 60 L424 38 L434 84 L444 60 H600 L612 60 L620 46 L628 72 L636 60 H760';
const facts = [
  { index: '01', title: 'Records', body: 'Imported and read on your device, never guessed.' },
  { index: '02', title: 'Preparation', body: 'Briefs that quote your own sources, page by page.' },
  { index: '03', title: 'Memory', body: 'Visit recordings and transcripts you control.' },
];

// MARK: - With a live session the primary action opens the workspace; Log out ends it on the server too
export function Landing() {
  const [session, setSession] = useState(() => readSession());
  const [leaving, setLeaving] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);
  useEffect(() => {
    document.title = 'Reva';
  }, []);
  async function logout() {
    if (!session || leaving) return;
    setLeaving(true);
    setFailure(null);
    try {
      await new AuthAPI(session.token).logout();
    } catch (error) {
      if (!(error instanceof APIError && error.status === 401)) {
        setFailure(
          error instanceof Error
            ? `Could not log out on the server: ${error.message}`
            : 'Could not log out on the server. Try again.',
        );
        setLeaving(false);
        return;
      }
    }
    clearSession();
    setSession(null);
    setLeaving(false);
  }
  return (
    <div className="landing">
      <header className="landing-top">
        <Brand />
      </header>
      <main className="landing-hero" id="main">
        <h1>Making every appointment count.</h1>
        <p className="landing-lede">
          Your records, your health, and a clearer conversation with your doctor.
        </p>
        <div className="landing-actions">
          {session ? (
            <>
              <a className="button button-primary" href="/app">
                Open your workspace
              </a>
              <a className="landing-demo" href="/demo">
                View the demo <ArrowUpRight size={16} aria-hidden="true" />
              </a>
              <button type="button" className="landing-text-action" onClick={logout} disabled={leaving}>
                {leaving ? 'Logging out…' : 'Log out'}
              </button>
            </>
          ) : (
            <>
              <a className="button button-primary" href="/signup">
                Sign up
              </a>
              <a className="button button-secondary" href="/login">
                Log in
              </a>
              <a className="landing-demo" href="/demo">
                View the demo <ArrowUpRight size={16} aria-hidden="true" />
              </a>
            </>
          )}
        </div>
        <div role="status" aria-live="polite" className="landing-session landing-mono">
          {session ? `Logged in as ${session.user.name}` : ''}
        </div>
        <div role="alert" className={failure ? 'account-status account-status-error' : undefined}>
          {failure}
        </div>
        <svg className="landing-pulse" viewBox="0 0 760 120" preserveAspectRatio="none" aria-hidden="true">
          <path d={trace} pathLength={1} />
        </svg>
        <dl className="landing-facts">
          {facts.map((fact) => (
            <div key={fact.index}>
              <dt>
                <span className="landing-mono">{fact.index}</span> {fact.title}
              </dt>
              <dd>{fact.body}</dd>
            </div>
          ))}
        </dl>
      </main>
    </div>
  );
}
