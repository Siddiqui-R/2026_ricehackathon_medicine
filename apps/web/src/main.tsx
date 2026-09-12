// Purpose: Mount the public landing, the account forms, the signed-in workspace or the demo by URL path.
// Inputs: The root element, the current pathname, the stored session and the IndexedDB-backed context.
// Outputs: / landing, /login and /signup forms, /app account workspace, /demo workspace, and a render-error boundary.
// Side effects: Loads style sheets; /demo opens the local demo on first use; /app opens the per-account database
//               and redirects to /login when no live session is stored.

import { Component, StrictMode, useEffect, useState, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { RevaProvider } from './core/RevaContext';
import { RevaStore } from './core/store';
import { RevaAPI } from './core/api';
import { IndexedDBRepository } from './core/repository';
import { accountDatabaseName } from './core/account';
import { readSession } from './core/session';
import { App } from './App';
import { Brand } from './components/Brand';
import { Landing } from './landing/Landing';
import { TestLanding } from './landing/TestLanding';
import { Login } from './landing/Login';
import { Signup } from './landing/Signup';
import './styles/tokens.css';
import './styles/layout.css';
import './styles/components.css';
import './styles/features.css';
import './styles/landing.css';

// MARK: - Path routes: the landing and account forms stay outside the workspace provider
// The workspace keeps its hash routes under /demo and /app; older /#/… bookmarks are forwarded to /demo.
function Entry() {
  const path = location.pathname.replace(/\/+$/u, '') || '/';
  if (path === '/' && location.hash.startsWith('#/')) {
    location.replace('/demo' + location.search + location.hash);
    return null;
  }
  if (path === '/demo')
    return (
      <RevaProvider>
        <App />
      </RevaProvider>
    );
  if (path === '/test') return <TestLanding />;
  if (path === '/app') return <AccountEntry />;
  if (path === '/login') return <Login />;
  if (path === '/signup') return <Signup />;
  return <Landing />;
}

// MARK: - The account workspace binds one live session to its own database; no session means /login
function AccountEntry() {
  const [session] = useState(() => readSession());
  const [store, setStore] = useState<RevaStore | null>(null);
  useEffect(() => {
    if (!session) {
      location.replace('/login');
      return;
    }
    let cancelled = false;
    void accountDatabaseName(session.user.id).then((name) => {
      if (cancelled) return;
      setStore(
        new RevaStore(new IndexedDBRepository(name), (token) => new RevaAPI(token), {
          mode: 'account',
          token: session.token,
          user: session.user,
          expiresAt: session.expiresAt,
        }),
      );
    });
    return () => {
      cancelled = true;
    };
  }, [session]);
  if (!session || !store)
    return (
      <main className="startup-state">
        <Brand />
        <div className="loading-ring" />
        <p>{session ? 'Opening your workspace…' : 'Taking you to log in…'}</p>
      </main>
    );
  return (
    <RevaProvider store={store}>
      <App />
    </RevaProvider>
  );
}

// MARK: - Render failures preserve saved data and offer a reload without resetting storage
class RenderBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    if (this.state.failed)
      return (
        <main className="startup-state">
          <h1>Let’s reopen Reva</h1>
          <p>This screen could not be displayed. Your saved data has not been reset.</p>
          <button className="button button-primary" onClick={() => location.reload()}>
            Reload the page
          </button>
        </main>
      );
    return this.props.children;
  }
}
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RenderBoundary>
      <Entry />
    </RenderBoundary>
  </StrictMode>,
);
