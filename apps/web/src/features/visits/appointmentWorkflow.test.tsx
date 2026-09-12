// Purpose: Keep the appointment interface focused on consent, recording, transcription and summaries.
// Inputs: An initialized synthetic store and server-rendered React components with inert browser stubs.
// Outputs: Assertions for consent-gated controls, removed calling UI and summary provenance display.
// Side effects: Static markup only; no effects, microphone, browser navigation or provider requests run.

import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { RevaProvider } from '../../core/RevaContext';
import { RevaStore } from '../../core/store';
import { MemoryRepository, sample, transport } from '../../core/__tests__/fixtures';
import { RecordingCapture } from './RecordingCapture';
import { RecordingDetail } from './RecordingDetail';
import { VisitDetail } from './VisitDetail';
import { Dashboard } from '../Dashboard';

// MARK: - Prepared store and readable button extraction avoid executing any interactive effects
async function ready() {
  const repository = new MemoryRepository();
  repository.saved!.snapshot.recordings = [{ ...sample(), isSample: false, audioFilename: 'synthetic.webm' }];
  const store = new RevaStore(repository, () => transport());
  await store.initialize();
  await store.checkServer();
  return store;
}
function button(markup: string, text: string): string {
  const found = markup
    .match(/<button\b[^>]*>[\s\S]*?<\/button>/g)
    ?.find((value) => value.replace(/<[^>]*>/g, '').includes(text));
  expect(found, `Button ${text}`).toBeDefined();
  return found!;
}

describe('appointment recording interface', () => {
  it('puts preparation and recording on home without a saved upcoming appointment list', async () => {
    const store = await ready();
    const html = renderToStaticMarkup(
      <RevaProvider store={store}>
        <Dashboard />
      </RevaProvider>,
    );
    expect(button(html, 'Upcoming visit')).toBeDefined();
    expect(button(html, 'Record session')).toBeDefined();
    expect(html).toContain('Session recordings');
    expect(html).not.toMatch(/Your next appointment|Add an appointment|All appointments/);
  });

  it('requires doctor and everyone consent before starting, uploading or saving', async () => {
    const store = await ready();
    vi.stubGlobal('window', { isSecureContext: true });
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: vi.fn() } });
    vi.stubGlobal('MediaRecorder', class {});
    try {
      const html = renderToStaticMarkup(
        <RevaProvider store={store}>
          <RecordingCapture onClose={() => {}} />
        </RevaProvider>,
      );
      expect(html).toContain(
        'Get your doctor’s consent and permission from everyone present before recording.',
      );
      expect(html).toContain('My doctor and everyone present agreed to recording.');
      expect(button(html, 'Start recording')).toContain('disabled=""');
      expect(button(html, 'Save recording')).toContain('disabled=""');
      expect(html.match(/<input\b[^>]*type="file"[^>]*>/)?.[0]).toContain('disabled=""');
      expect(html).not.toContain('Microphone recording is unavailable');
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('shows Record appointment with no booking or calling controls', async () => {
    const store = await ready();
    vi.stubGlobal('window', { location: { hash: '' } });
    try {
      const html = renderToStaticMarkup(
        <RevaProvider store={store}>
          <VisitDetail id={store.getState().snapshot!.visits[0].id} />
        </RevaProvider>,
      );
      expect(button(html, 'Record appointment')).toBeDefined();
      expect(html).not.toMatch(/Call clinic|Appointment booking|Try booking demo|Place real call/);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('presents transcription, attributed AI summary and personal notes as separate sections', async () => {
    const store = await ready();
    const recording = {
      ...store.getState().snapshot!.recordings[0],
      summary: 'My separate personal notes',
      aiSummary: 'Generated appointment summary',
      aiSummaryModel: 'mock-gemini',
      aiSummaryGeneratedAt: '2026-09-12T12:00:00Z',
    };
    const html = renderToStaticMarkup(
      <RevaProvider store={store}>
        <RecordingDetail recording={recording} onClose={() => {}} />
      </RevaProvider>,
    );
    expect(button(html, 'Transcribe again')).toBeDefined();
    expect(button(html, 'Summarize appointment')).toBeDefined();
    expect(html).toContain('Generated appointment summary');
    expect(html).toContain('mock-gemini');
    expect(html).toContain('Review it against the transcript and original audio. It may contain mistakes.');
    expect(html).toContain('My separate personal notes');
    const incomplete = renderToStaticMarkup(
      <RevaProvider store={store}>
        <RecordingDetail recording={{ ...recording, aiSummaryModel: undefined }} onClose={() => {}} />
      </RevaProvider>,
    );
    expect(incomplete).not.toContain('Generated appointment summary');
  });
});
