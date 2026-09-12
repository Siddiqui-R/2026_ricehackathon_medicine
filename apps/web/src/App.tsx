// Purpose: Coordinate responsive navigation, global record search, and shared status feedback.
// Inputs: Browser hash routes and the current Reva context.
// Outputs: Desktop sidebar, tablet/mobile navigation, and the selected functional screen.
// Side effects: Changes routes, announces operation feedback, and moves focus after navigation.

import { useEffect, useRef, useState, type FormEvent } from 'react';
import {
  Activity,
  ArrowUpRight,
  CalendarDays,
  Check,
  ChevronRight,
  FileText,
  LayoutDashboard,
  Search,
  Settings,
  ShieldCheck,
  UserRound,
  X,
} from 'lucide-react';
import { useReva } from './core/RevaContext';
import { Brand } from './components/Brand';
import { Button } from './components/ui';
import { Dashboard } from './features/Dashboard';
import { SettingsPage } from './features/SettingsPage';
import { RecordsPage } from './features/records/RecordsPage';
import { RecordDetail } from './features/records/RecordDetail';
import { MedicalProfilePage } from './features/profile/MedicalProfilePage';
import { VisitsPage } from './features/visits/VisitsPage';
import { VisitDetail } from './features/visits/VisitDetail';

// MARK: - Small hash router supports bookmarks and native browser history
const navigation = [
  { id: 'summary', title: 'Overview', mobile: 'Overview', icon: LayoutDashboard },
  { id: 'records', title: 'Health records', mobile: 'Records', icon: FileText },
  { id: 'visits', title: 'Appointments', mobile: 'Visits', icon: CalendarDays },
  { id: 'profile', title: 'Medical profile', mobile: 'Profile', icon: UserRound },
];
function readRoute() {
  const hash = location.hash.slice(1) || '/summary';
  const [path, query] = hash.split('?');
  const [section = 'summary', id] = path.split('/').filter(Boolean);
  return { section, id: id ? decodeURIComponent(id) : undefined, query: new URLSearchParams(query), hash };
}

export function App() {
  const store = useReva();
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
    const name = navigation.find((item) => item.id === route.section)?.title ?? 'Settings';
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
  const navTitle = navigation.find((item) => item.id === route.section)?.title ?? 'Settings';

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
              aria-current={route.section === item.id ? 'page' : undefined}
            >
              <item.icon size={20} />
              <span>{item.title}</span>
              {route.section === item.id && <span className="active-dot" />}
            </a>
          ))}
        </nav>
        <a href="#/records?add=symptom" className="sidebar-log">
          <Activity size={19} />
          <span>Log a symptom</span>
          <ArrowUpRight size={16} />
        </a>
        <div className="sidebar-bottom">
          <a
            className={`nav-item ${route.section === 'settings' ? 'active' : ''}`}
            href="#/settings"
            aria-current={route.section === 'settings' ? 'page' : undefined}
          >
            <Settings size={19} />
            <span>Settings & connections</span>
          </a>
          <div className="sidebar-divider" />
          <a href="#/profile" className="patient-link">
            <span className="avatar">{profile.initials}</span>
            <span>
              <strong>{profile.name.replace(' (Synthetic)', '')}</strong>
              <small>{profile.isDemo ? 'Fictional demo profile' : 'Your medical profile'}</small>
            </span>
            <ChevronRight size={16} />
          </a>
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
          <a
            href="#/settings"
            className="workspace-status"
            aria-label={profile.isDemo ? 'Fictional demo settings' : 'Browser storage settings'}
          >
            <ShieldCheck size={17} />
            <span>{profile.isDemo ? 'Fictional demo' : 'Saved in this browser'}</span>
          </a>
          <a href="#/settings" className="mobile-settings icon-button" aria-label="Settings">
            <Settings size={21} />
          </a>
        </header>
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
          ) : route.section === 'profile' ? (
            <MedicalProfilePage />
          ) : route.section === 'settings' ? (
            <SettingsPage />
          ) : (
            <Dashboard />
          )}
          <footer className="workspace-footer">
            <span>
              reva<span aria-hidden="true"> · </span>Making every appointment count.
            </span>
            <span>
              {profile.isDemo
                ? 'Demonstration with fictional health records'
                : 'Your sources. Your questions. Your next step.'}
            </span>
          </footer>
        </main>
      </div>
      <nav className="mobile-nav" aria-label="Mobile navigation">
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
      {(store.error || store.notice) && (
        <div
          className={`feedback ${store.error ? 'feedback-error' : ''}`}
          role={store.error ? 'alert' : 'status'}
        >
          <span className="feedback-icon">{store.error ? <Activity size={18} /> : <Check size={18} />}</span>
          <p>{store.error || store.notice}</p>
          <Button
            variant="ghost"
            className="icon-button"
            onClick={store.clearFeedback}
            aria-label="Dismiss notification"
          >
            <X size={18} />
          </Button>
        </div>
      )}
    </div>
  );
}
