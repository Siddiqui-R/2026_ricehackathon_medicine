// Purpose: Coordinate responsive navigation, global record search, and shared status feedback.
// Inputs: Browser hash routes and the current Reva context (demo or signed-in account mode).
// Outputs: Desktop sidebar, tablet/mobile navigation, an account action menu, and the selected screen.
// Side effects: Changes routes, announces operation feedback, moves focus after navigation, and in account
//               mode asks the store to revoke the session on Log out.

import { useEffect, useRef, useState, type FormEvent } from 'react';
import {
  Activity,
  ArrowUpRight,
  Check,
  ChevronRight,
  FileText,
  LayoutDashboard,
  Search,
  ShieldCheck,
  UserRound,
  X,
} from 'lucide-react';
import { useReva } from './core/RevaContext';
import { Brand } from './components/Brand';
import { NotFound } from './components/NotFound';
import { readWorkspaceRoute } from './routing';
import { Button } from './components/ui';
import { Dashboard } from './features/Dashboard';
import { AccountMenu } from './components/AccountMenu';
import { RecordingProcessingIndicator } from './components/RecordingProcessingIndicator';
import { SettingsPage } from './features/SettingsPage';
import { RecordsPage } from './features/records/RecordsPage';
import { RecordDetail } from './features/records/RecordDetail';
import { MedicalProfilePage } from './features/profile/MedicalProfilePage';
import { VisitsPage } from './features/visits/VisitsPage';
import { VisitDetail } from './features/visits/VisitDetail';
import { RecordingSessionProvider, useRecordingSession } from './features/visits/RecordingSession';
import { RecordingBanner, RecordingConsent } from './features/visits/RecordingSessionChrome';
import { RecordingPage } from './features/visits/RecordingPage';
import { SavedRecordingPage } from './features/visits/SavedRecordingPage';

// MARK: - Small hash router supports bookmarks and native browser history
const navigation = [
  { id: 'summary', title: 'Overview', mobile: 'Overview', icon: LayoutDashboard },
  { id: 'records', title: 'Health records', mobile: 'Records', icon: FileText },
  { id: 'profile', title: 'Medical profile', mobile: 'Profile', icon: UserRound },
];
function readRoute() {
  return readWorkspaceRoute(location.hash);
}

export function App() {
  return (
    <RecordingSessionProvider>
      <Workspace />
    </RecordingSessionProvider>
  );
}
function Workspace() {
  const store = useReva();
  const recordingSession = useRecordingSession();
  const [route, setRoute] = useState(readRoute);
  const [search, setSearch] = useState('');
  const content = useRef<HTMLElement>(null);
  useEffect(() => {
    const update = () => {
      setRoute(readRoute());
      window.scrollTo({ top: 0 });
    };
    window.addEventListener('hashchange', update);
    return () => window.removeEventListener('hashchange', update);
  }, []);
  useEffect(() => {
    const name =
      navigation.find((item) => item.id === route.section)?.title ??
      (route.section === 'visits'
        ? 'Pre-visit brief'
        : route.section.startsWith('recording')
          ? 'Session recording'
          : route.section === 'settings'
            ? 'Settings'
            : 'Page not found');
    document.title = `${name} · Reva`;
    content.current?.focus({ preventScroll: true });
  }, [route.hash]);
  function searchRecords(event: FormEvent) {
    event.preventDefault();
    location.hash = '/records?q=' + encodeURIComponent(search.trim());
  }

  // MARK: - Startup preserves storage failures instead of substituting another patient's demo
  if (store.loading)
    return (
      <main className="startup-state">
        <Brand />
        <div className="loading-ring" />
        <p>Opening your health workspace…</p>
      </main>
    );
  if (!store.snapshot)
    return (
      <main className="startup-state">
        <Brand />
        <h1>Your workspace could not open</h1>
        <p role="alert">{store.error || 'Please reload to try again.'}</p>
        <Button onClick={() => location.reload()}>Try again</Button>
      </main>
    );
  const profile = store.snapshot.profile;
  const navTitle =
    navigation.find((item) => item.id === route.section)?.title ??
    (route.section === 'visits'
      ? 'Pre-visit brief'
      : route.section.startsWith('recording')
        ? 'Session recording'
        : route.section === 'settings'
          ? 'Settings'
          : 'Page not found');
  const account = store.mode === 'account';
  const demo = store.mode === 'demo' && profile.isDemo;
  // The store reports a failed revoke in the feedback banner; a successful one leaves this page.
  const logout = () => {
    if (!recordingSession.allowWorkspaceExit()) return;
    void (async () => {
      await store.cancelProviderWork();
      if (account) await store.logout();
      else location.assign('/');
    })().catch(() => undefined);
  };

  // MARK: - Desktop navigation and phone tabs share the same active route and labels
  return (
    <div className="app-shell">
      <a
        className="skip-link"
        href="#main-content"
        onClick={(event) => {
          event.preventDefault();
          content.current?.focus();
        }}
      >
        Skip to content
      </a>
      <aside className="sidebar">
        <a className="brand-link" href="#/summary" aria-label="Reva overview">
          <Brand />
        </a>
        <p className="sidebar-label">MY HEALTH</p>
        <nav className="desktop-nav" aria-label="Main navigation">
          {navigation.map((item) => (
            <a
              key={item.id}
              href={`#/${item.id}`}
              className={`nav-item ${route.section === item.id ? 'active' : ''}`}
              aria-label={item.title}
              title={item.title}
              aria-current={route.section === item.id ? 'page' : undefined}
            >
              <item.icon size={20} />
              <span>{item.title}</span>
              {route.section === item.id && <span className="active-dot" />}
            </a>
          ))}
        </nav>
        <a
          href="#/records?add=symptom"
          className="sidebar-log"
          aria-label="Log a symptom"
          title="Log a symptom"
        >
          <Activity size={19} />
          <span>Log a symptom</span>
          <ArrowUpRight size={16} />
        </a>
        <div className="sidebar-bottom">
          <RecordingProcessingIndicator placement="sidebar" />
          <div className="sidebar-divider" />
          <AccountMenu
            profile={profile}
            demo={demo}
            busy={store.busy && !store.providerWork}
            onSignOut={logout}
          />
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <a href="#/summary" className="mobile-brand" aria-label="Reva overview">
            <Brand compact />
          </a>
          <span className="breadcrumb">
            My health <ChevronRight size={13} />
            <strong>{navTitle}</strong>
          </span>
          <form className="global-search" onSubmit={searchRecords} role="search">
            <Search size={18} />
            <input
              aria-label="Search your health records"
              placeholder="Search your health records"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            <button type="submit" aria-label="Search records">
              <ChevronRight size={17} />
            </button>
          </form>
          <span className="workspace-status">
            <ShieldCheck size={17} />
            <span>{account ? 'Your account' : 'Saved in this browser'}</span>
          </span>
          <AccountMenu
            profile={profile}
            demo={demo}
            busy={store.busy && !store.providerWork}
            onSignOut={logout}
            compact
          />
        </header>
        <RecordingBanner onRecordingPage={route.section === 'recording'} />
        <main ref={content} id="main-content" className="main-content" tabIndex={-1}>
          {route.section === 'records' ? (
            route.id ? (
              <RecordDetail key={route.id} id={route.id} />
            ) : (
              <RecordsPage
                key={route.hash}
                initialAction={
                  route.query.get('add') === 'import'
                    ? 'import'
                    : route.query.get('add') === 'symptom'
                      ? 'symptom'
                      : undefined
                }
              />
            )
          ) : route.section === 'visits' ? (
            route.id ? (
              <VisitDetail key={route.id} id={route.id} />
            ) : (
              <VisitsPage key={route.hash} />
            )
          ) : route.section === 'recording' ? (
            <RecordingPage />
          ) : route.section === 'recordings' && route.id ? (
            <SavedRecordingPage id={route.id} />
          ) : route.section === 'profile' ? (
            <MedicalProfilePage />
          ) : route.section === 'settings' ? (
            <SettingsPage />
          ) : route.section === 'summary' ? (
            <Dashboard />
          ) : (
            <NotFound />
          )}
          <footer className="workspace-footer">
            <span>
              reva<span aria-hidden="true"> · </span>Making every appointment count.
            </span>
            <span>Your sources. Your questions. Your next step.</span>
          </footer>
        </main>
      </div>
      <nav
        className="mobile-nav"
        aria-label="Mobile navigation"
        style={{ gridTemplateColumns: `repeat(${navigation.length}, minmax(0, 1fr))` }}
      >
        {navigation.map((item) => (
          <a
            key={item.id}
            href={`#/${item.id}`}
            className={route.section === item.id ? 'active' : ''}
            aria-current={route.section === item.id ? 'page' : undefined}
          >
            <item.icon size={21} />
            <span>{item.mobile}</span>
          </a>
        ))}
      </nav>
      <RecordingConsent />
      <RecordingProcessingIndicator placement="compact" />
      {(store.error || store.notice || (store.busy && store.providerWork)) && (
        <div
          className={`feedback ${store.error ? 'feedback-error' : ''}`}
          role={store.error ? 'alert' : 'status'}
        >
          <span className="feedback-icon">
            {store.error || (store.busy && store.providerWork) ? <Activity size={18} /> : <Check size={18} />}
          </span>
          <p>{store.error || store.notice || 'Analyzing your records…'}</p>
          {store.busy && store.providerWork && (
            <Button variant="ghost" onClick={() => void store.cancelProviderWork()}>
              Stop analysis
            </Button>
          )}
          {!(store.busy && store.providerWork) && (
            <Button
              variant="ghost"
              className="icon-button"
              onClick={store.clearFeedback}
              aria-label="Dismiss notification"
            >
              <X size={18} />
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
