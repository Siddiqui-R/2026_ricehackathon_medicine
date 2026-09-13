// Purpose: Keep recording progress honest, navigable, and recoverable across queue states.
// Inputs: Fictional queued, active, failed, waiting and completed recordings.
// Outputs: Static assertions for named stages, actual recording links and appropriate recovery controls.
// Side effects: None; never starts a recording, processor or network request.

import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { RecordingProcessingStatus, type RecordingProcessingJob } from './RecordingProcessingIndicator';

const job = (id: string, stage: RecordingProcessingJob['stage']): RecordingProcessingJob => ({
  id,
  title: `Session ${id}`,
  stage,
  message: '',
});
const render = (jobs: RecordingProcessingJob[]) =>
  renderToStaticMarkup(<RecordingProcessingStatus jobs={jobs} retry={() => {}} dismiss={() => {}} />);

// MARK: - A progress card describes work without inventing a percentage or hiding failed jobs
describe('recording processing status', () => {
  it('does not occupy space when no recordings are processing', () => {
    expect(render([])).toBe('');
  });
  it('shows the current job first and keeps the remaining recordings individually accessible', () => {
    const html = render([
      job('old', 'complete'),
      job('next', 'queued'),
      job('active', 'transcribing'),
      job('later', 'queued'),
    ]);
    expect(html.indexOf('Session active')).toBeLessThan(html.indexOf('Session old'));
    expect(html).toContain('Transcribing audio');
    expect(html).toContain('2 queued');
    for (const id of ['old', 'next', 'active', 'later']) expect(html).toContain(`href="#/recordings/${id}"`);
    expect(html).not.toMatch(/progressbar|%/);
  });
  it('names analysis accurately and encodes the saved recording destination', () => {
    const html = render([job('visit / 1?', 'analyzing')]);
    expect(html).toContain('Preparing summary');
    expect(html).toContain('href="#/recordings/visit%20%2F%201%3F"');
    expect(html).toContain('role="status"');
    expect(html).toContain('aria-live="polite"');
    expect(html).not.toContain('Try again');
  });
  it('offers recovery for failures and deliberate stops while service waits continue automatically', () => {
    for (const stage of ['failed', 'waiting'] as const) {
      const html = render([
        {
          ...job('one', stage),
          canRetry: stage === 'waiting',
          message: 'The service is unavailable. Your audio is saved.',
        },
      ]);
      expect(html).toContain('The service is unavailable. Your audio is saved.');
      expect(html).toContain('aria-label="Retry processing Session one"');
      expect(html).not.toContain('Dismiss processing status');
      expect(html).not.toContain('is-running');
    }
    expect(
      render([{ ...job('service', 'waiting'), message: 'Waiting for transcription service.' }]),
    ).not.toContain('Try again');
  });
  it('provides a completed recording link and dismissal without a misleading retry or spinner', () => {
    const html = render([job('finished', 'complete')]);
    expect(html).toContain('Ready to review');
    expect(html).toContain('View recording');
    expect(html).toContain('aria-label="Dismiss processing status for Session finished"');
    expect(html).not.toMatch(/Try again|is-running/);
  });
  it('shows a scheduled retry without offering a button that would bypass the delay', () => {
    const html = render([
      {
        ...job('waiting', 'waiting'),
        retryAt: Date.now() + 60_000,
        message: 'Analysis will retry at the scheduled time. Your transcript is saved.',
      },
    ]);
    expect(html).toContain('scheduled time');
    expect(html).not.toMatch(/Try again|is-running|Dismiss processing status/);
    expect(html).toContain('href="#/recordings/waiting"');
  });
});
