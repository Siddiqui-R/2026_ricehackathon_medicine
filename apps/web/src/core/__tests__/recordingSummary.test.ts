// Purpose: Verify appointment summaries remain attributed to their exact saved transcript.
// Inputs: Synthetic recordings, deferred AI responses, edits, cancellation, and persistence failures.
// Outputs: Assertions for full sources, separate notes, stale-result rejection and original retention.
// Side effects: Test memory and injected provider responses only; no live services.

import { describe, expect, it, vi } from 'vitest';
import type { AISummary, VisitRecording } from '../models';
import { RevaAPI } from '../api';
import { createMemoryRecord, hasRecordingSummary, recordingTranscript } from '../mutations';
import { validateSnapshot } from '../domain';
import { RevaStore, type APITransport } from '../store';
import { deferred, MemoryRepository, sample, transport } from './fixtures';

// MARK: - Synthetic appointments and provider boundaries keep every test offline
const answer = { summary: 'Summary of the saved appointment transcript.', model: 'mock-gemini' };
async function ready(overrides: Partial<APITransport> = {}) {
  const repository = new MemoryRepository();
  const recording: VisitRecording = {
    ...sample(),
    id: 'appointment-audio',
    isSample: false,
    audioFilename: 'appointment.webm',
    summary: 'Private personal notes that must not be sent to the summary provider.',
    transcriptionModel: 'mock-transcription',
  };
  repository.saved!.snapshot.recordings = [recording];
  repository.attachments.set(recording.audioFilename!, new Blob(['unchanged audio'], { type: 'audio/webm' }));
  const summarize = vi.fn<APITransport['summarize']>().mockResolvedValue(answer);
  const store = new RevaStore(repository, () => transport({ summarize, ...overrides }));
  await store.initialize();
  await store.checkServer();
  return { store, repository, recording, summarize };
}
const current = (store: RevaStore) => store.getState().snapshot!.recordings[0];

describe('transcript-only appointment summaries', () => {
  it('titles only a date fallback from its transcript and updates untouched memory titles', async () => {
    const { store, recording, summarize } = await ready();
    await store.mutate((draft) =>
      Object.assign(draft.recordings[0], {
        title: 'Sep 12, 2026',
        titleSource: 'date',
        capturedAt: '2026-09-13T02:00:00Z',
        savedAt: '2026-09-13T02:30:00Z',
      }),
    );
    await store.saveMemory(recording.id);
    summarize.mockResolvedValueOnce({ ...answer, title: 'Follow-up on sleep and blood pressure' });
    const onRetry = vi.fn();
    await store.summarizeRecording(recording.id, undefined, true, onRetry);
    expect(summarize.mock.calls[0][2]).toEqual({ generateTitle: true, date: '2026-09-12', onRetry });
    expect(current(store)).toMatchObject({
      title: 'Follow-up on sleep and blood pressure',
      titleSource: 'ai',
    });
    expect(
      store.getState().snapshot!.records.find((item) => item.sourceRecordingID === recording.id),
    ).toMatchObject({
      title: 'Follow-up on sleep and blood pressure · memory',
      date: '2026-09-12',
      dateSource: 'recorded',
    });
    await store.summarizeRecording(recording.id);
    expect(summarize.mock.calls[1][2]?.generateTitle).toBe(false);
  });

  it('preserves concurrent manual titles and saved memory edits while a fallback title is generated', async () => {
    const result = deferred<AISummary>();
    const { store, recording } = await ready({ summarize: () => result.promise });
    await store.mutate((draft) =>
      Object.assign(draft.recordings[0], {
        title: 'Sep 12, 2026',
        titleSource: 'date',
        savedAt: '2026-09-13T02:30:00Z',
      }),
    );
    await store.saveMemory(recording.id);
    const pending = store.summarizeRecording(recording.id);
    await store.mutate((draft) => {
      draft.recordings[0].title = 'My chosen session title';
      draft.recordings[0].titleSource = 'user';
      draft.records.find((item) => item.sourceRecordingID === recording.id)!.title = 'My memory title';
    });
    result.resolve({ ...answer, title: 'AI suggested title' });
    await pending;
    expect(current(store)).toMatchObject({
      title: 'My chosen session title',
      titleSource: 'user',
      aiSummary: answer.summary,
    });
    expect(
      store.getState().snapshot!.records.find((item) => item.sourceRecordingID === recording.id)!.title,
    ).toBe('My memory title');
  });

  it('keeps import dates distinct from event dates and retains metadata through snapshot validation', async () => {
    const { store, recording, summarize } = await ready();
    await store.mutate((draft) =>
      Object.assign(draft.recordings[0], {
        title: 'Sep 12, 2026',
        titleSource: 'date',
        savedAt: '2026-09-13T02:30:00Z',
      }),
    );
    summarize.mockResolvedValueOnce({ ...answer, title: 'Medication review' });
    await store.summarizeRecording(recording.id);
    expect(summarize.mock.calls[0][2]?.date).toBe('Added 2026-09-12; event date unknown');
    expect(summarize.mock.calls[0][0].uploadedAt).toBe('2026-09-13T02:30:00Z');
    await store.saveMemory(recording.id);
    const saved = validateSnapshot(JSON.parse(JSON.stringify(store.getState().snapshot)));
    expect(saved.recordings[0]).toMatchObject({ titleSource: 'ai', savedAt: '2026-09-13T02:30:00Z' });
    expect(saved.recordings[0].capturedAt).toBeUndefined();
    expect(saved.records.find((item) => item.sourceRecordingID === recording.id)).toMatchObject({
      date: '2026-09-12',
      dateSource: 'added',
    });
  });

  it('ignores unsolicited titles for manual recordings and rejects invalid generated titles', async () => {
    const { store, recording, summarize } = await ready();
    summarize.mockResolvedValueOnce({ ...answer, title: 'Unexpected rename' });
    await store.summarizeRecording(recording.id);
    expect(current(store).title).toBe(recording.title);
    await store.mutate((draft) => {
      draft.recordings[0].titleSource = 'date';
    });
    summarize.mockResolvedValueOnce({ ...answer, title: '界'.repeat(41) });
    await expect(store.summarizeRecording(recording.id)).rejects.toThrow('no usable recording title');
    expect(current(store).title).toBe(recording.title);
    expect(current(store).aiSummary).toBe(answer.summary);
  });

  it('sends the full timestamped transcript, retains separate notes, and attributes saved memory', async () => {
    const { store, recording, summarize } = await ready();
    await store.mutate((draft) => {
      draft.recordings[0].segments[0].text = `  Exact original wording\n${'More words from this conversation. '.repeat(300)}  `;
    });
    const transcript = recordingTranscript(current(store));
    await store.saveMemory(recording.id);
    await store.mutate((draft) => {
      draft.records.find((item) => item.sourceRecordingID === recording.id)!.notes =
        'Edited saved-memory notes';
    });
    await store.summarizeRecording(recording.id);
    const source = summarize.mock.calls[0][0];
    expect(source.id).toBe(recording.id);
    expect(source.title).toBe(recording.title);
    expect(source.text).toBe(transcript);
    expect(source.text.length).toBeGreaterThan(9000);
    expect(source.notes).toBe('');
    expect(source.summary).toBe('');
    expect(source.text).not.toContain(recording.summary);
    expect(current(store)).toMatchObject({
      aiSummary: answer.summary,
      aiSummaryModel: answer.model,
      summary: recording.summary,
    });
    expect(Number.isFinite(Date.parse(current(store).aiSummaryGeneratedAt!))).toBe(true);
    const memory = store
      .getState()
      .snapshot!.records.find((item) => item.sourceRecordingID === recording.id)!;
    expect(memory.text).toBe(transcript);
    expect(memory.summary).toBe(answer.summary);
    expect(memory.summaryModel).toBe(answer.model);
    expect(memory.summaryGeneratedAt).toBe(current(store).aiSummaryGeneratedAt);
    expect(memory.pageTexts).toBeUndefined();
    expect(memory.notes).toBe('Edited saved-memory notes');
  });

  it('allows personal notes to change during generation and keeps them separate from the result', async () => {
    const result = deferred<AISummary>();
    const { store, recording } = await ready({ summarize: () => result.promise });
    const pending = store.summarizeRecording(recording.id);
    await store.mutate((draft) => {
      draft.recordings[0].summary = 'Newer personal notes';
    });
    result.resolve(answer);
    await pending;
    expect(current(store)).toMatchObject({ summary: 'Newer personal notes', aiSummary: answer.summary });
  });

  it.each([
    'title',
    'createdAt',
    'duration',
    'audioFilename',
    'isSample',
    'visitID',
    'segments',
    'deleted',
  ] as const)('rejects an AI result when %s changes while it is running', async (field) => {
    const result = deferred<AISummary>();
    const { store, recording } = await ready({ summarize: () => result.promise });
    const pending = store.summarizeRecording(recording.id);
    const rejected = expect(pending).rejects.toThrow('changed during summarization');
    await store.mutate((draft) => {
      const saved = draft.recordings[0];
      if (field === 'deleted') draft.recordings = [];
      else if (field === 'segments') saved.segments[0].text = 'A corrected transcript';
      else if (field === 'duration') saved.duration += 1;
      else if (field === 'isSample') saved.isSample = true;
      else if (field === 'visitID')
        saved.visitID = draft.visits.find((visit) => visit.id !== saved.visitID)!.id;
      else if (field === 'createdAt') saved.createdAt = '2026-09-13T12:00:00Z';
      else saved[field] = field === 'audioFilename' ? 'replacement.webm' : 'Renamed appointment';
    });
    result.resolve(answer);
    await rejected;
    expect(store.getState().snapshot!.recordings[0]?.aiSummary).toBeUndefined();
  });

  it('ignores canceled results even when a provider finishes after cancellation', async () => {
    const result = deferred<AISummary>();
    const { store, recording } = await ready({ summarize: () => result.promise });
    const controller = new AbortController();
    const pending = store.summarizeRecording(recording.id, controller.signal);
    const rejected = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    controller.abort();
    result.resolve(answer);
    await rejected;
    expect(current(store).aiSummary).toBeUndefined();
    expect(await (await store.getAttachment(recording.audioFilename!)).text()).toBe('unchanged audio');
  });

  it('rejects notes-only recordings and failed results without replacing prior data', async () => {
    const { store, recording, repository, summarize } = await ready();
    await store.mutate((draft) => {
      draft.recordings[0].segments = [];
    });
    await expect(store.summarizeRecording(recording.id)).rejects.toThrow('Transcribe');
    expect(summarize).not.toHaveBeenCalled();
    await store.mutate((draft) => {
      draft.recordings[0].segments = recording.segments;
    });
    await store.summarizeRecording(recording.id);
    summarize.mockRejectedValueOnce(new Error('Provider unavailable'));
    await expect(store.summarizeRecording(recording.id)).rejects.toThrow('Provider unavailable');
    summarize.mockResolvedValueOnce({ summary: '', model: answer.model });
    await expect(store.summarizeRecording(recording.id)).rejects.toThrow('no usable summary');
    repository.failure = new Error('Storage full');
    await expect(store.summarizeRecording(recording.id)).rejects.toThrow('Storage full');
    repository.failure = null;
    expect(current(store).aiSummary).toBe(answer.summary);
    expect(await (await store.getAttachment(recording.audioFilename!)).text()).toBe('unchanged audio');
  });
});

describe('summary provenance after edits', () => {
  it('uses the Central day for new memories while retaining edited existing dates', async () => {
    const { store, recording } = await ready();
    const source = { ...recording, createdAt: '2026-09-12T02:00:00Z' };
    const snapshot = structuredClone(store.getState().snapshot!);
    const memory = createMemoryRecord(source, snapshot);
    expect(memory.date).toBe('2026-09-11');
    expect(source.createdAt).toBe('2026-09-12T02:00:00Z');
    snapshot.records.push({ ...memory, date: '2026-08-15' });
    expect(createMemoryRecord(source, snapshot).date).toBe('2026-08-15');
  });
  it('does not present or save incomplete AI summary metadata as a generated summary', async () => {
    const { store, recording } = await ready();
    for (const missing of ['aiSummary', 'aiSummaryModel', 'aiSummaryGeneratedAt'] as const) {
      const partial = {
        ...recording,
        aiSummary: answer.summary,
        aiSummaryModel: answer.model,
        aiSummaryGeneratedAt: '2026-09-12T12:00:00Z',
        [missing]: undefined,
      };
      expect(hasRecordingSummary(partial)).toBe(false);
      expect(createMemoryRecord(partial, store.getState().snapshot!).summaryModel).toBeUndefined();
    }
  });
  it('preserves AI on note-only and unchanged corrections, and clears it before updating corrected memory', async () => {
    const { store, recording } = await ready();
    await store.summarizeRecording(recording.id);
    await store.saveMemory(recording.id);
    await store.mutate((draft) => {
      draft.recordings[0].summary = 'Changed personal notes';
      draft.records.find((item) => item.sourceRecordingID === recording.id)!.notes =
        'Keep edited memory notes';
    });
    const texts = Object.fromEntries(current(store).segments.map((segment) => [segment.id, segment.text]));
    await store.saveMemory(recording.id, texts);
    expect(current(store).aiSummary).toBe(answer.summary);
    await store.saveMemory(recording.id, {
      ...texts,
      [current(store).segments[0].id]: 'Corrected first segment',
    });
    expect(current(store).aiSummary).toBeUndefined();
    expect(current(store).aiSummaryModel).toBeUndefined();
    expect(current(store).aiSummaryGeneratedAt).toBeUndefined();
    const memory = store
      .getState()
      .snapshot!.records.find((item) => item.sourceRecordingID === recording.id)!;
    expect(memory.text).toBe(recordingTranscript(current(store)));
    expect(memory.summaryModel).toBeUndefined();
    expect(memory.summaryGeneratedAt).toBeUndefined();
    expect(memory.summary).not.toBe(answer.summary);
    expect(memory.notes).toBe('Keep edited memory notes');
  });

  it('clears old AI before refreshing memory after a new transcription', async () => {
    const transcript = {
      text: 'New transcript text.',
      segments: [{ id: 'new', speaker: 'Doctor', start: 0, end: 1, text: 'New transcript text.' }],
      model: 'new-transcription-model',
    };
    const { store, recording } = await ready({ transcribe: async () => transcript });
    await store.summarizeRecording(recording.id);
    await store.saveMemory(recording.id);
    await store.mutate((draft) => {
      draft.records.find((item) => item.sourceRecordingID === recording.id)!.notes = 'Keep this memory note';
    });
    await store.transcribeRecording(recording.id);
    const memory = store
      .getState()
      .snapshot!.records.find((item) => item.sourceRecordingID === recording.id)!;
    expect(current(store).aiSummary).toBeUndefined();
    expect(memory.text).toBe(recordingTranscript(current(store)));
    expect(memory.summaryModel).toBeUndefined();
    expect(memory.notes).toBe('Keep this memory note');
  });

  it('reads old snapshots unchanged and round-trips optional AI summary metadata', async () => {
    const { store } = await ready();
    const legacy = structuredClone(store.getState().snapshot!);
    expect(validateSnapshot(legacy)).toEqual(legacy);
    const next = structuredClone(legacy);
    Object.assign(next.recordings[0], {
      aiSummary: answer.summary,
      aiSummaryModel: answer.model,
      aiSummaryGeneratedAt: '2026-09-12T12:00:00Z',
    });
    expect(validateSnapshot(JSON.parse(JSON.stringify(next)))).toEqual(next);
    next.recordings[0].aiSummaryGeneratedAt = 'invalid';
    expect(() => validateSnapshot(next)).toThrow('aiSummaryGeneratedAt');
  });
});

describe('removed calling and summary transport', () => {
  it('recognizes only the remaining providers and has no calling API methods', async () => {
    const providers = {
      gemini: { configured: true, model: 'mock' },
      transcription: { configured: true, model: 'mock-transcription' },
    };
    const api = new RevaAPI(
      'test',
      vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(providers))),
    );
    expect(await api.providers()).toEqual(providers);
    expect('startCall' in api).toBe(false);
    expect('callStatus' in api).toBe(false);
  });

  it('aborts the actual summary request and distinguishes cancellation from timeout', async () => {
    const controller = new AbortController();
    const fetcher = vi.fn<typeof fetch>(
      (_path, options) =>
        new Promise((_resolve, reject) => {
          options!.signal!.addEventListener('abort', () =>
            reject(new DOMException('Canceled', 'AbortError')),
          );
        }),
    );
    const { store, recording } = await ready();
    const source = {
      ...store.getState().snapshot!.records[0],
      id: recording.id,
      title: recording.title,
      text: recordingTranscript(recording),
    };
    const api = new RevaAPI('test', fetcher);
    const pending = api.summarize(source, controller.signal);
    const rejected = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    controller.abort();
    await rejected;
    expect(fetcher.mock.calls[0][1]!.signal!.aborted).toBe(true);
  });
});
