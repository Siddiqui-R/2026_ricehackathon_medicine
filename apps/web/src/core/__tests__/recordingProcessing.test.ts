// Purpose: Exercise automatic recording processing against the real store and durable in-memory originals.
// Inputs: Synthetic audio, controlled provider promises, queued status markers and workspace edits.
// Outputs: Regression checks for sequential work, resumability, cancellation and nonblocking failures.
// Side effects: In-memory persistence and mocked HTTP only; no microphone or live provider access.
import { afterEach, describe, expect, it, vi, type Mock } from 'vitest';
import { RecordingProcessingAutomation } from '../recordingProcessing';
import { RevaStore, SESSION_ENDED_PATH, type APITransport } from '../store';
import { APIError } from '../api';
import { createMemoryRecord } from '../mutations';
import type { AISummary, AudioTranscription, VisitRecording } from '../models';
import {
  MemoryRepository,
  authTransport,
  capabilities,
  deferred,
  fakeStorage,
  testUser,
  transport,
} from './fixtures';

const transcription: AudioTranscription = {
  text: 'The clinician asked me to bring my existing records.',
  model: 'mock-transcription',
  segments: [
    {
      id: 'segment-1',
      speaker: 'Speaker 1',
      start: 0,
      end: 8,
      text: 'The clinician asked me to bring my existing records.',
    },
  ],
};
const summary: AISummary = { summary: 'Discussed bringing existing records.', model: 'mock-gemini' };
const controllers: RecordingProcessingAutomation[] = [];
afterEach(() => {
  controllers.splice(0).forEach((controller) => controller.stop());
  vi.useRealTimers();
});
async function setup(
  options: {
    transcribe?: Mock<APITransport['transcribe']>;
    summarize?: Mock<APITransport['summarize']>;
    configured?: boolean;
    account?: boolean;
  } = {},
) {
  const repository = new MemoryRepository();
  const transcribe =
    options.transcribe ?? vi.fn<APITransport['transcribe']>(async () => structuredClone(transcription));
  const summarize = options.summarize ?? vi.fn<APITransport['summarize']>(async () => summary);
  const providerState = structuredClone(capabilities);
  if (options.configured === false) providerState.transcription.configured = false;
  const redirect = vi.fn();
  const store = new RevaStore(
    repository,
    () => transport({ transcribe, summarize, providers: async () => providerState }),
    options.account
      ? {
          mode: 'account',
          token: 'synthetic-session-token',
          user: testUser,
          storage: fakeStorage(),
          redirect,
          authFactory: () => authTransport(),
          syncDelay: 60_000,
        }
      : {},
  );
  await store.initialize();
  await store.checkServer();
  const processor = new RecordingProcessingAutomation(store);
  controllers.push(processor);
  const add = async (id = 'recording-1', status = 'processing-queued', segments = []) => {
    const recording: VisitRecording = {
      id,
      title: `Synthetic ${id}`,
      visitID: '',
      createdAt: '2026-09-12T18:00:00Z',
      duration: 12,
      audioFilename: `${id}.webm`,
      segments,
      summary: 'My own notes',
      isSample: false,
      status,
    };
    await store.saveRecording(recording, new Blob(['synthetic audio'], { type: 'audio/webm' }));
  };
  return { repository, store, processor, transcribe, summarize, providerState, add, redirect };
}
describe('background recording processing', () => {
  it('rebuilds analysis when explicit reprocessing returns the identical transcript', async () => {
    const test = await setup();
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    test.summarize.mockResolvedValueOnce({
      summary: 'Refreshed analysis of the same source.',
      model: 'new-summary-model',
    });
    test.processor.reprocess('recording-1');
    await vi.waitFor(() => expect(test.summarize).toHaveBeenCalledTimes(2));
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(test.transcribe).toHaveBeenCalledTimes(2);
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1'),
    ).toMatchObject({
      segments: transcription.segments,
      aiSummary: 'Refreshed analysis of the same source.',
      aiSummaryModel: 'new-summary-model',
    });
  });

  it('durably resumes analysis after identical retranscription is interrupted before AI finishes', async () => {
    const test = await setup();
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    const interrupted = deferred<AISummary>();
    test.summarize.mockReturnValueOnce(interrupted.promise);
    test.processor.reprocess('recording-1');
    await vi.waitFor(() => expect(test.summarize).toHaveBeenCalledTimes(2));
    expect(
      test.repository.saved!.snapshot.recordings.find((item) => item.id === 'recording-1'),
    ).toMatchObject({
      status: 'processing-analyzing',
      segments: transcription.segments,
      aiSummary: undefined,
      aiSummaryModel: undefined,
      aiSummaryGeneratedAt: undefined,
    });
    test.processor.stop();
    await vi.waitFor(() => expect(test.store.getState().providerWork).toBe(false));
    const restarted = new RecordingProcessingAutomation(test.store);
    controllers.push(restarted);
    restarted.start();
    await vi.waitFor(() => expect(restarted.getState()[0].stage).toBe('complete'));
    expect(test.transcribe).toHaveBeenCalledTimes(2);
    expect(test.summarize).toHaveBeenCalledTimes(3);
    interrupted.resolve({ summary: 'Stale interrupted analysis.', model: 'obsolete-model' });
    await Promise.resolve();
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')?.aiSummary,
    ).toBe(summary.summary);
  });

  it('reprocesses both steps together and retains previous results when replacement transcription fails', async () => {
    const test = await setup();
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    const previous = structuredClone(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')!,
    );
    test.transcribe.mockRejectedValueOnce(new Error('Replacement request unavailable'));
    test.processor.reprocess('recording-1');
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('failed'));
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1'),
    ).toMatchObject({
      status: 'processing-reprocess-failed',
      segments: previous.segments,
      aiSummary: previous.aiSummary,
    });
    const replacement = {
      ...transcription,
      text: 'Complete replacement transcript.',
      segments: [{ ...transcription.segments[0], text: 'Complete replacement transcript.' }],
    };
    test.transcribe.mockResolvedValueOnce(replacement);
    test.summarize.mockResolvedValueOnce({ summary: 'Replacement summary.', model: 'mock-summary' });
    test.processor.retry('recording-1');
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(test.transcribe).toHaveBeenCalledTimes(3);
    expect(test.summarize).toHaveBeenCalledTimes(2);
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1'),
    ).toMatchObject({
      segments: replacement.segments,
      aiSummary: 'Replacement summary.',
    });
  });

  it('automatically refreshes the summary from saved word corrections without replacing them from audio', async () => {
    const test = await setup();
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    const recording = test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')!;
    await test.store.saveMemory(
      recording.id,
      { [recording.segments[0].id]: 'Corrected words from the conversation.' },
      JSON.stringify(recording.segments),
    );
    await vi.waitFor(() => expect(test.summarize).toHaveBeenCalledTimes(2));
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(test.transcribe).toHaveBeenCalledOnce();
    expect(test.summarize.mock.calls[1][0].text).toContain('Corrected words from the conversation.');
  });
  it('keeps canceled work resumable without restarting it until the user retries', async () => {
    const late = deferred<AudioTranscription>();
    const transcribe = vi
      .fn<APITransport['transcribe']>()
      .mockReturnValueOnce(late.promise)
      .mockResolvedValue(transcription);
    const test = await setup({ transcribe });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(transcribe).toHaveBeenCalledOnce());
    await test.store.cancelProviderWork();
    await vi.waitFor(() =>
      expect(test.processor.getState()[0]).toMatchObject({
        stage: 'waiting',
        message: expect.stringContaining('stopped'),
      }),
    );
    expect(test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')!.status).toBe(
      'processing-transcribing',
    );
    test.processor.wake();
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(transcribe).toHaveBeenCalledOnce();
    test.processor.retry('recording-1');
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(transcribe).toHaveBeenCalledTimes(2);
    late.resolve({ ...transcription, text: 'Stale canceled transcript' });
    await Promise.resolve();
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')!.segments,
    ).toEqual(transcription.segments);
  });
  it('transcribes then analyzes and saves sourced memory without blocking other edits', async () => {
    const speech = deferred<AudioTranscription>(),
      analysis = deferred<AISummary>();
    const test = await setup({
      transcribe: vi.fn(() => speech.promise),
      summarize: vi.fn(() => analysis.promise),
    });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.transcribe).toHaveBeenCalledOnce());
    expect(test.processor.getState()[0].stage).toBe('transcribing');
    expect(test.store.getState().busy).toBe(false);
    await test.store.mutate((draft) => {
      draft.profile.careNotes = 'Concurrent personal edit';
    });
    expect(test.summarize).not.toHaveBeenCalled();
    speech.resolve(structuredClone(transcription));
    await vi.waitFor(() => expect(test.summarize).toHaveBeenCalledOnce());
    expect(test.processor.getState()[0].stage).toBe('analyzing');
    expect(test.store.getState().busy).toBe(false);
    analysis.resolve(summary);
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    const snapshot = test.store.getState().snapshot!;
    expect(snapshot.profile.careNotes).toBe('Concurrent personal edit');
    expect(snapshot.recordings.find((item) => item.id === 'recording-1')).toMatchObject({
      summary: 'My own notes',
      aiSummary: summary.summary,
    });
    expect(snapshot.records.find((item) => item.sourceRecordingID === 'recording-1')).toBeDefined();
    expect(test.repository.attachments.get('recording-1.webm')?.size).toBeGreaterThan(0);
    test.processor.dismiss('recording-1');
    await vi.waitFor(() => expect(test.processor.getState()).toEqual([]));
  });
  it('runs only one recording at a time and never processes legacy saved audio implicitly', async () => {
    const speech = deferred<AudioTranscription>();
    const transcribe = vi.fn().mockReturnValueOnce(speech.promise).mockResolvedValue(transcription);
    const test = await setup({ transcribe });
    await test.add('first');
    await test.add('second');
    await test.add('legacy', 'saved');
    test.processor.start();
    await vi.waitFor(() => expect(transcribe).toHaveBeenCalledOnce());
    expect(test.processor.getState().find((item) => item.id === 'second')?.stage).toBe('queued');
    speech.resolve(transcription);
    await vi.waitFor(() =>
      expect(test.processor.getState().filter((item) => item.stage === 'complete')).toHaveLength(2),
    );
    expect(transcribe).toHaveBeenCalledTimes(2);
    expect(test.store.getState().snapshot!.recordings.find((item) => item.id === 'legacy')?.status).toBe(
      'saved',
    );
  });
  it('waits for service availability and resumes automatically when it returns', async () => {
    const test = await setup({ configured: false });
    await test.add();
    test.processor.start();
    expect(test.processor.getState()[0].stage).toBe('waiting');
    expect(test.transcribe).not.toHaveBeenCalled();
    test.providerState.transcription.configured = true;
    await test.store.checkServer();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
  });
  it('resumes from a saved transcript without paying for transcription again', async () => {
    const test = await setup();
    await test.add();
    await test.store.mutate((draft) => {
      const item = draft.recordings.find((item) => item.id === 'recording-1')!;
      item.segments = structuredClone(transcription.segments);
      item.status = 'processing-analyzing';
    });
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(test.transcribe).not.toHaveBeenCalled();
    expect(test.summarize).toHaveBeenCalledOnce();
  });
  it('shows an analysis backoff as waiting while the rest of the workspace remains editable', async () => {
    const analysis = deferred<AISummary>();
    const retryAt = Date.now() + 60_000;
    const test = await setup({
      summarize: vi.fn<APITransport['summarize']>((_record, _signal, options) => {
        options?.onRetry?.({ retryAt, attempt: 0 });
        return analysis.promise;
      }),
    });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0]).toMatchObject({ stage: 'waiting', retryAt }));
    expect(test.store.getState().busy).toBe(false);
    await test.store.mutate((draft) => {
      draft.profile.careNotes = 'Edited during retry wait';
    });
    analysis.resolve(summary);
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(test.processor.getState()[0].retryAt).toBeUndefined();
    expect(test.transcribe).toHaveBeenCalledOnce();
    expect(test.store.getState().snapshot!.profile.careNotes).toBe('Edited during retry wait');
  });
  it('keeps the transcript on analysis failure, then retries only analysis', async () => {
    const summarize = vi.fn().mockRejectedValueOnce(new APIError(422)).mockResolvedValue(summary);
    const test = await setup({ summarize });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('failed'));
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')?.segments,
    ).toEqual(transcription.segments);
    test.processor.wake();
    await new Promise((resolve) => setTimeout(resolve, 15));
    expect(summarize).toHaveBeenCalledOnce();
    test.processor.retry('recording-1');
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    expect(test.transcribe).toHaveBeenCalledOnce();
    expect(summarize).toHaveBeenCalledTimes(2);
  });
  it('aborts on unmount and does not apply a late transcript', async () => {
    const speech = deferred<AudioTranscription>();
    const test = await setup({ transcribe: vi.fn(() => speech.promise) });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.transcribe).toHaveBeenCalledOnce());
    const signal = test.transcribe.mock.calls[0][2] as AbortSignal;
    test.processor.stop();
    expect(signal.aborted).toBe(true);
    speech.resolve(transcription);
    await vi.waitFor(() =>
      expect(
        test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')?.segments,
      ).toEqual([]),
    );
    expect(test.summarize).not.toHaveBeenCalled();
  });
  it('does not loop when persistence fails before a stage can be written', async () => {
    const test = await setup();
    await test.add();
    test.repository.failure = new Error('Storage unavailable');
    test.processor.start();
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('failed'));
    test.processor.wake();
    await new Promise((resolve) => setTimeout(resolve, 15));
    expect(test.transcribe).not.toHaveBeenCalled();
    test.repository.failure = null;
    test.processor.retry('recording-1');
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
  });
  it('preserves notes edited on an existing memory while analysis is pending', async () => {
    const analysis = deferred<AISummary>();
    const test = await setup({ summarize: vi.fn(() => analysis.promise) });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.summarize).toHaveBeenCalledOnce());
    await test.store.mutate((draft) => {
      const recording = draft.recordings.find((item) => item.id === 'recording-1')!;
      const memory = createMemoryRecord(recording, draft);
      memory.notes = 'My personal follow-up notes, edited during analysis.';
      draft.records.push(memory);
    });
    analysis.resolve(summary);
    await vi.waitFor(() => expect(test.processor.getState()[0].stage).toBe('complete'));
    const memories = test.store
      .getState()
      .snapshot!.records.filter((item) => item.sourceRecordingID === 'recording-1');
    expect(memories).toHaveLength(1);
    expect(memories[0].notes).toBe('My personal follow-up notes, edited during analysis.');
    expect(memories[0].summary).toBe(summary.summary);
  });
  it('keeps pending work resumable when the server expires the session', async () => {
    const test = await setup({ account: true, transcribe: vi.fn().mockRejectedValue(new APIError(401)) });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.redirect).toHaveBeenCalledWith(SESSION_ENDED_PATH));
    expect(test.store.isWorkspaceActive()).toBe(false);
    expect(test.processor.getState()).toEqual([]);
    expect(test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1')?.status).toBe(
      'processing-transcribing',
    );
    test.processor.wake();
    expect(test.transcribe).toHaveBeenCalledOnce();
    expect(test.summarize).not.toHaveBeenCalled();
  });
  it('aborts on logout without applying a late result or marking the saved work failed', async () => {
    const speech = deferred<AudioTranscription>();
    const test = await setup({ account: true, transcribe: vi.fn(() => speech.promise) });
    await test.add();
    test.processor.start();
    await vi.waitFor(() => expect(test.transcribe).toHaveBeenCalledOnce());
    const signal = test.transcribe.mock.calls[0][2] as AbortSignal;
    await test.store.logout();
    expect(signal.aborted).toBe(true);
    speech.resolve(transcription);
    await new Promise((resolve) => setTimeout(resolve, 15));
    expect(test.processor.getState()).toEqual([]);
    expect(
      test.store.getState().snapshot!.recordings.find((item) => item.id === 'recording-1'),
    ).toMatchObject({
      status: 'processing-transcribing',
      segments: [],
    });
    expect(test.summarize).not.toHaveBeenCalled();
  });
});
