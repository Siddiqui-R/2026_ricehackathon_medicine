// Purpose: Verify recording page and banner controls with synthetic inert session state.
// Inputs: Mock session stages, static React rendering and explicit control callbacks.
// Outputs: Assertions for full-page capture, integrated upload and banner control wiring.
// Side effects: Optional local-only visual fixtures are written only when explicitly requested by an env flag.

import { Children, isValidElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ session: {} as Record<string, unknown>, effects: [] as (() => void)[] }));
vi.mock('react', async (original) => ({
  ...(await original<typeof import('react')>()),
  useEffect: (effect: () => void) => {
    mocks.effects.push(effect);
  },
}));
vi.mock('./RecordingSession', () => ({ useRecordingSession: () => mocks.session }));
import { RecordingBanner } from './RecordingSessionChrome';
import { RecordingPage } from './RecordingPage';

// MARK: - The synthetic draft has no real consent event, microphone, storage or providers
const capture = {
  state: 'idle',
  seconds: 0,
  blob: null,
  supported: true,
  error: '',
  notice: '',
  pause: vi.fn(),
  resume: vi.fn(),
  stop: vi.fn(),
};
const draft = {
  id: 'synthetic-qa',
  title: 'Session recording',
  returnHash: '#/summary',
  notes: '',
  mode: 'microphone',
  consented: true,
};
const save = vi.fn();
beforeEach(() => {
  vi.clearAllMocks();
  mocks.effects = [];
  capture.state = 'idle';
  capture.seconds = 0;
  mocks.session = {
    draft: { ...draft },
    capture,
    pending: null,
    original: null,
    upload: null,
    active: false,
    reading: false,
    saving: false,
    error: '',
    duration: 0,
    hasUnsaved: false,
    requestSession: vi.fn(),
    start: vi.fn(),
    setMode: vi.fn(),
    chooseAudio: vi.fn(),
    updateDraft: vi.fn(),
    save,
    discard: vi.fn(),
  };
});
afterEach(() => vi.unstubAllGlobals());
function controls(tree: ReactNode): Record<string, unknown>[] {
  const values: Record<string, unknown>[] = [];
  Children.forEach(tree, (child) => {
    if (!isValidElement<{ children?: ReactNode }>(child)) return;
    values.push(child.props);
    values.push(...controls(child.props.children));
  });
  return values;
}
function visualFixture(name: string, body: string) {
  if (process.env.REVA_RECORDING_VISUAL_FIXTURES !== '1') return;
  writeFileSync(
    resolve(`.qa-recording${name}.html`),
    `<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Synthetic recording design preview</title><link rel="stylesheet" href="/src/styles/tokens.css"><link rel="stylesheet" href="/src/styles/layout.css"><link rel="stylesheet" href="/src/styles/components.css"><link rel="stylesheet" href="/src/styles/features.css"><link rel="stylesheet" href="/src/styles/recording-session.css"></head><body style="padding:38px"><main>${body}</main></body></html>`,
  );
}

// MARK: - Banner controls remain useful outside the recording route; UI does not invent a waveform
describe('full-page recording interface', () => {
  it('shows a recorder page with a disabled save until original audio is available', () => {
    const html = renderToStaticMarkup(<RecordingPage />);
    expect(html).toContain('recording-workspace');
    expect(html).toContain('Record live');
    expect(html).toContain('Upload audio');
    expect(html).not.toContain('<dialog');
    expect(html.match(/<button[^>]*disabled=""[^>]*>Save recording<\/button>/)).not.toBeNull();
    visualFixture('', html);
  });
  it('replaces the live recorder with a coherent upload panel and an accessible file chooser', () => {
    mocks.session.draft = { ...draft, mode: 'upload' };
    const html = renderToStaticMarkup(<RecordingPage />);
    expect(html).toContain('Already have a recording?');
    expect(html).toContain('Choose audio file');
    expect(html).toContain('aria-label="Upload existing audio"');
    expect(html).not.toContain('Start recording</button>');
    visualFixture('-upload', html);
  });
  it('exposes no recording or upload controls when a direct route has not been consented', () => {
    mocks.session.draft = null;
    const html = renderToStaticMarkup(<RecordingPage />);
    expect(html).toContain('Confirm permission');
    expect(html).not.toContain('<button');
    expect(html).not.toContain('type="file"');
  });
  it('does not reopen consent during the final render after saving or cancelling navigation', () => {
    mocks.session.draft = null;
    renderToStaticMarkup(<RecordingPage />);
    vi.stubGlobal('window', { location: { hash: '#/recordings/saved-audio' } });
    mocks.effects[0]();
    expect(mocks.session.requestSession).not.toHaveBeenCalled();
    window.location.hash = '#/summary';
    mocks.effects[0]();
    expect(mocks.session.requestSession).not.toHaveBeenCalled();
    window.location.hash = '#/recording';
    mocks.effects[0]();
    expect(mocks.session.requestSession).toHaveBeenCalledOnce();
  });
  it('wires pause, stop and return from any other workspace screen', () => {
    mocks.session.active = true;
    mocks.session.duration = 127;
    capture.state = 'recording';
    const banner = RecordingBanner({ onRecordingPage: false });
    const elements = controls(banner);
    (elements.find((item) => item['aria-label'] === 'Pause recording')!.onClick as () => void)();
    (elements.find((item) => item['aria-label'] === 'Stop recording')!.onClick as () => void)();
    expect(capture.pause).toHaveBeenCalledOnce();
    expect(capture.stop).toHaveBeenCalledOnce();
    expect(elements.find((item) => item['aria-label'] === 'Return to recording page')?.href).toBe(
      '#/recording',
    );
    const html = renderToStaticMarkup(banner);
    expect(html).toContain('Recording in progress');
    expect(html).toContain('2:07');
    visualFixture(
      '-active',
      `${html}<div style="padding-top:32px">${renderToStaticMarkup(<RecordingPage />)}</div>`,
    );
  });
  it('offers resume for paused recording and save only when captured audio is stopped', () => {
    mocks.session.active = true;
    capture.state = 'paused';
    let elements = controls(RecordingBanner({ onRecordingPage: false }));
    (elements.find((item) => item['aria-label'] === 'Resume recording')!.onClick as () => void)();
    expect(capture.resume).toHaveBeenCalledOnce();
    expect(elements.find((item) => item.children === 'Save')).toBeUndefined();
    mocks.session.active = false;
    mocks.session.original = new Blob(['synthetic']);
    capture.state = 'stopped';
    elements = controls(RecordingBanner({ onRecordingPage: false }));
    (elements.find((item) => item.children === 'Save')!.onClick as () => void)();
    expect(save).toHaveBeenCalledOnce();
    mocks.session.saving = true;
    elements = controls(RecordingBanner({ onRecordingPage: false }));
    expect(elements.find((item) => item.children === 'Saving…')?.disabled).toBe(true);
  });
});
