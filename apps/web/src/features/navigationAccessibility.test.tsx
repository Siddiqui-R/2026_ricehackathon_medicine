// Purpose: Protect the visible sidebar's accessible names when tablet layout hides text labels.
// Inputs: Real App markup, synthetic store state, and accessible-name computation in jsdom.
// Outputs: Named, focusable links with stable route destinations before and after label hiding.
// Side effects: Test DOM only; page content is rendered without effects, providers, or browser storage.
// @vitest-environment jsdom

import { computeAccessibleName } from 'dom-accessibility-api';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, describe, expect, it } from 'vitest';
import { App } from '../App';
import { RevaProvider } from '../core/RevaContext';
import { RevaStore } from '../core/store';
import { MemoryRepository, transport } from '../core/__tests__/fixtures';

afterEach(() => {
  document.body.innerHTML = '';
});
const destinations = [
  ['Overview', '#/summary'],
  ['Health records', '#/records'],
  ['Appointments', '#/visits'],
  ['Medical profile', '#/profile'],
  ['Log a symptom', '#/records?add=symptom'],
  ['Settings & connections', '#/settings'],
];

// MARK: - Simulate the audited tablet display:none rule without relying on jsdom media-query layout
describe('responsive rail accessible names', () => {
  it.each([375, 768, 1440])(
    'retains explicit names and native anchor destinations for width %i',
    async (width) => {
      const store = new RevaStore(new MemoryRepository(), () => transport());
      await store.initialize();
      document.body.innerHTML = renderToStaticMarkup(
        <RevaProvider store={store}>
          <App />
        </RevaProvider>,
      );
      if (width >= 761 && width <= 979) {
        document.querySelectorAll<HTMLElement>('.nav-item span, .sidebar-log span').forEach((label) => {
          label.style.display = 'none';
        });
      }
      const anchors = [...document.querySelectorAll<HTMLAnchorElement>('.sidebar .nav-item, .sidebar-log')];
      expect(anchors).toHaveLength(destinations.length);
      for (const [index, anchor] of anchors.entries()) {
        expect(computeAccessibleName(anchor)).toBe(destinations[index][0]);
        expect(anchor.getAttribute('href')).toBe(destinations[index][1]);
        expect(anchor.tabIndex).toBe(0);
        anchor.focus();
        expect(document.activeElement).toBe(anchor);
      }
    },
  );
});
