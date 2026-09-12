// Purpose: Mount the responsive browser interface inside the shared persistent state provider.
// Inputs: The root element and IndexedDB-backed application context.
// Outputs: Reva's routes and a recoverable render-error boundary.
// Side effects: Loads the application, style sheets, and local demo on first use.

import { Component, StrictMode, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { RevaProvider } from './core/RevaContext';
import { App } from './App';
import './styles/tokens.css';
import './styles/layout.css';
import './styles/components.css';
import './styles/features.css';

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
      <RevaProvider>
        <App />
      </RevaProvider>
    </RenderBoundary>
  </StrictMode>,
);
