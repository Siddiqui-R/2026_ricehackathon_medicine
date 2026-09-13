// Purpose: Verify observable browser actions protect newer edits and require deliberate external effects.
// Inputs: Fictional snapshots, controllable provider promises and injectable persistence failures.
// Outputs: Assertions for durable publication, source races, CAS conflicts, atomic pull and inert legacy booking data.
// Side effects: Test memory only; no requests reach a network or paid provider.
import { describe, expect, it, vi } from 'vitest';
import type { AIPreparation, AISummary, AudioTranscription, BookingRequest } from '../models.ts';
import { APIError } from '../api.ts';
import { RevaStore, type APITransport } from '../store.ts';
import { deferred, MemoryRepository, sample, seed, transport } from './fixtures.ts';

// MARK: - Setup initializes real store coordination over controllable boundaries.
async function ready(api = transport(), repository = new MemoryRepository()) {
  const store = new RevaStore(repository, () => api);
  await store.initialize();
  return { store, repository };
}
const callRequest = (): BookingRequest => {
  const visit = seed().visits[0];
  return {
    id: 'synthetic-call-id',
    visitID: visit.id,
    clinic: 'Fictional clinic',
    phone: '+13125550123',
    reason: 'Fictional booking test',
    earliest: visit.date,
    latest: visit.date,
    timeZone: visit.timeZone,
    preferences: '',
    status: 'draft',
    scenario: 'live',
    createdAt: visit.date,
  };
};

// MARK: - State never publishes an edit that storage failed to commit.
describe('local state publication', () => {
  it('aborts a pending provider request when the workspace token changes and ignores its late result', async () => {
    const response = deferred<AISummary>();
    const summarize = vi.fn<APITransport['summarize']>(() => response.promise);
    const { store } = await ready(transport({ summarize }));
    await store.checkServer();
    store.setConnectedAI(true);
    const source = store.getState().snapshot!.records[0];
    const pending = store.summarizeRecord(source.id);
    const rejected = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    await vi.waitFor(() => expect(summarize).toHaveBeenCalledOnce());
    store.setToken('new-workspace-token');
    await rejected;
    expect(summarize.mock.calls[0][1]!.aborted).toBe(true);
    expect(store.getState()).toMatchObject({
      token: 'new-workspace-token',
      busy: false,
      providerWork: false,
    });
    response.resolve({ summary: 'Late source summary', model: 'synthetic-model' });
    await Promise.resolve();
    expect(store.getState().snapshot!.records[0].summary).toBe(source.summary);
  });
  it('refreshes old demo labels once while preserving source wording and edited samples', async () => {
    const repository = new MemoryRepository();
    const records = repository.saved!.snapshot.records;
    const diary = records.find((record) => record.id === 'demo-record-symptom-diary')!;
    diary.title = 'Scanned symptom note - date needs review';
    diary.status = 'needsReview';
    diary.tags.push('needs review');
    const source = diary.text;
    const labs = records.find((record) => record.id === 'demo-record-labs')!;
    labs.title = 'My bloodwork notes';
    labs.version = 2;
    const { store } = await ready(transport(), repository);
    expect(store.getState().snapshot!.records.find((record) => record.id === diary.id)).toMatchObject({
      title: 'Weekly symptom diary',
      status: 'ready',
      text: source,
      version: 2,
    });
    expect(store.getState().snapshot!.records.find((record) => record.id === labs.id)).toEqual(labs);
    const revision = repository.saved!.revision;
    await ready(transport(), repository);
    expect(repository.saved!.revision).toBe(revision);
  });

  it('serializes simultaneous local edits without losing either field', async () => {
    const { store, repository } = await ready();
    await Promise.all([
      store.mutate((draft) => {
        draft.profile.careNotes = 'First edit';
      }),
      store.mutate((draft) => {
        draft.profile.surgeriesAndImplants = ['Second edit'];
      }),
    ]);
    expect(store.getState().snapshot!.profile).toMatchObject({
      careNotes: 'First edit',
      surgeriesAndImplants: ['Second edit'],
    });
    expect(repository.saved!.revision).toBe(3);
  });
  it('keeps the last published snapshot when persistence fails', async () => {
    const { store, repository } = await ready(),
      original = structuredClone(store.getState().snapshot);
    repository.failure = new Error('Storage is full');
    await expect(
      store.mutate((draft) => {
        draft.records = [];
      }),
    ).rejects.toThrow('Storage is full');
    expect(store.getState().snapshot).toEqual(original);
    expect(store.getState().error).toBe('Storage is full');
  });
  it('surfaces corrupt startup without replacing it with seed data', async () => {
    const repository = new MemoryRepository();
    repository.failure = new Error('Persisted workspace is corrupt');
    const seedSpy = vi.spyOn(repository, 'seed');
    const { store } = await ready(transport(), repository);
    expect(store.getState()).toMatchObject({
      snapshot: null,
      loading: false,
      error: 'Persisted workspace is corrupt',
    });
    expect(seedSpy).not.toHaveBeenCalled();
    await store.resetDemo();
    expect(store.getState().snapshot!.profile.isDemo).toBe(true);
  });
  it('retains legacy booking history without recovery, calls or appointment changes', async () => {
    const repository = new MemoryRepository();
    const request = { ...callRequest(), isLive: true, status: 'starting' };
    repository.saved!.snapshot.bookings = [request];
    const before = structuredClone(repository.saved!.snapshot);
    const { store } = await ready(transport(), repository);
    expect(store.getState().snapshot).toEqual(before);
    expect('startCall' in store).toBe(false);
    expect('refreshCall' in store).toBe(false);
  });
});

// MARK: - Connected results cannot overwrite sources or the user's question/notes authority.
describe('provider result publication', () => {
  it.each(['title', 'date', 'dateSource'] as const)(
    'invalidates an old AI summary after %s correction while preserving notes-only edits',
    async (field) => {
      const { store } = await ready(
        transport({
          summarize: async () => ({
            summary: 'Generated from the original date and title',
            model: 'mock-gemini',
          }),
        }),
      );
      await store.checkServer();
      store.setConnectedAI(true);
      const source = store.getState().snapshot!.records[0];
      await store.summarizeRecord(source.id);
      const generated = store.getState().snapshot!.records.find((item) => item.id === source.id)!;
      await store.saveRecord({ ...generated, notes: 'My new private note' }, generated.version);
      const noted = store.getState().snapshot!.records.find((item) => item.id === source.id)!;
      expect(noted).toMatchObject({
        summary: generated.summary,
        summaryModel: generated.summaryModel,
        summaryGeneratedAt: generated.summaryGeneratedAt,
      });
      const corrected = { ...noted };
      if (field === 'dateSource') corrected.dateSource = 'document';
      else corrected[field] = field === 'date' ? '2026-08-01' : 'Corrected source title';
      await store.saveRecord(corrected, noted.version);
      const result = store.getState().snapshot!.records.find((item) => item.id === source.id)!;
      expect(result.summaryModel).toBeUndefined();
      expect(result.summaryGeneratedAt).toBeUndefined();
      expect(result.summary).not.toBe(generated.summary);
      expect(result.notes).toBe('My new private note');
    },
  );
  it('dates generated summaries separately from medical source dates and clears attribution after source edits', async () => {
    const { store } = await ready(
      transport({
        summarize: async () => ({ summary: 'Synthetic generated summary', model: 'mock-gemini' }),
      }),
    );
    await store.checkServer();
    store.setConnectedAI(true);
    const original = store.getState().snapshot!.records[0];
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-13T02:30:00Z'));
    try {
      await store.summarizeRecord(original.id);
      const generated = store.getState().snapshot!.records.find((item) => item.id === original.id)!;
      expect(generated).toMatchObject({
        summaryGeneratedAt: '2026-09-13T02:30:00Z',
        date: original.date,
        uploadedAt: original.uploadedAt,
      });
      await store.saveRecord({ ...generated, text: 'Corrected original source text' }, generated.version);
      const revised = store.getState().snapshot!.records.find((item) => item.id === original.id)!;
      expect(revised.summaryModel).toBeUndefined();
      expect(revised.summaryGeneratedAt).toBeUndefined();
      expect(revised.summary).not.toBe(generated.summary);
    } finally {
      vi.useRealTimers();
    }
  });
  it('sends safe current local excerpts without replacing attributed summaries or saved sources', async () => {
    const prepare = vi.fn<APITransport['prepare']>().mockResolvedValue({
        overview: 'Fictional overview',
        questions: [],
        selectedRecordIDs: [],
        model: 'mock-gemini',
      }),
      { store } = await ready(transport({ prepare }));
    await store.mutate((draft) => {
      Object.assign(draft.records[0], {
        isDemo: false,
        summaryModel: undefined,
        text: `Complete source dose: 12.5 mg.\n${'Long following source wording '.repeat(100)}`,
        summary: 'Old clipped source dose: 12.',
      });
      Object.assign(draft.records[1], {
        isDemo: false,
        summaryModel: 'mock-summary-model',
        summary: 'Attributed overview.',
      });
      Object.assign(draft.records[2], {
        isDemo: true,
        summaryModel: undefined,
        summary: 'Authored fictional overview.',
      });
      const legacyDemoText = `${'x'.repeat(1792)}dose: 100 mg`;
      Object.assign(draft.records[3], {
        isDemo: true,
        summaryModel: undefined,
        text: legacyDemoText,
        summary: legacyDemoText.slice(0, 1800),
      });
    });
    const savedRecords = structuredClone(store.getState().snapshot!.records);
    await store.checkServer();
    store.setConnectedAI(true);
    await store.prepareVisit(store.getState().snapshot!.visits[0].id);
    expect(prepare).toHaveBeenCalledTimes(1);
    const candidates = prepare.mock.calls[0][1];
    expect(candidates[0].summary).toBe('Complete source dose: 12.5 mg.');
    expect(candidates[1].summary).toBe('Attributed overview.');
    expect(candidates[2].summary).toBe('Authored fictional overview.');
    expect(candidates[3].summary).toBe('');
    expect(candidates.map((record) => record.text)).toEqual(savedRecords.map((record) => record.text));
    expect(store.getState().snapshot!.records).toEqual(savedRecords);
  });
  it('discards a delayed summary after the source has been edited', async () => {
    const response = deferred<AISummary>(),
      summarize = vi.fn(() => response.promise);
    const { store } = await ready(transport({ summarize }));
    await store.checkServer();
    store.setConnectedAI(true);
    const record = store.getState().snapshot!.records[0],
      operation = store.summarizeRecord(record.id);
    await vi.waitFor(() => expect(summarize).toHaveBeenCalledTimes(1));
    await store.saveRecord({ ...record, text: 'New reviewed source' }, record.version);
    response.resolve({ summary: 'Old provider answer', model: 'mock' });
    await expect(operation).rejects.toThrow('changed during');
    expect(store.getState().snapshot!.records[0].text).toBe('New reviewed source');
    expect(store.getState().snapshot!.records[0].summary).not.toBe('Old provider answer');
  });
  it('keeps questions and notes edited while AI preparation was in flight', async () => {
    const response = deferred<AIPreparation>(),
      prepare = vi.fn(() => response.promise);
    const { store } = await ready(transport({ prepare }));
    await store.checkServer();
    store.setConnectedAI(true);
    const visitID = store.getState().snapshot!.visits[0].id;
    await store.mutate((draft) => {
      const visit = draft.visits[0];
      visit.questions = [];
      visit.report = undefined;
    });
    const operation = store.prepareVisit(visitID);
    await vi.waitFor(() => expect(prepare).toHaveBeenCalled());
    await store.mutate((draft) => {
      draft.visits[0].questions = ['My explicit question'];
      draft.visits[0].notes = 'My notes during generation';
    });
    response.resolve({
      overview: 'Fictional overview',
      questions: ['Suggested question'],
      selectedRecordIDs: [seed().records[0].id],
      model: 'mock-gemini',
    });
    await operation;
    const visit = store.getState().snapshot!.visits[0];
    expect(visit.questions).toEqual(['My explicit question']);
    expect(visit.report!.questions).toEqual(visit.questions);
    expect(visit.report!.notes).toBe('My notes during generation');
    expect(visit.report!.generationModel).toBe('mock-gemini');
    expect(visit.report!.sections[1].sources).toEqual([]);
  });
  it('rejects unknown AI-selected source identities', async () => {
    const { store } = await ready(
      transport({
        prepare: async () => ({
          overview: 'Fictional',
          questions: [],
          selectedRecordIDs: ['unknown-record'],
          model: 'mock',
        }),
      }),
    );
    await store.checkServer();
    store.setConnectedAI(true);
    const original = structuredClone(store.getState().snapshot!.visits[0].report);
    await expect(store.prepareVisit(seed().visits[0].id)).rejects.toThrow('unknown source');
    expect(store.getState().snapshot!.visits[0].report).toEqual(original);
  });
  it('rejects preparation when its candidate records change in flight', async () => {
    const response = deferred<AIPreparation>(),
      prepare = vi.fn(() => response.promise),
      { store } = await ready(transport({ prepare }));
    await store.checkServer();
    store.setConnectedAI(true);
    const operation = store.prepareVisit(seed().visits[0].id);
    await vi.waitFor(() => expect(prepare).toHaveBeenCalled());
    await store.deleteRecord(seed().records[0].id);
    response.resolve({ overview: 'Old overview', questions: [], selectedRecordIDs: [], model: 'mock' });
    await expect(operation).rejects.toThrow('Sources or visit details changed');
  });
  it('updates a first local report’s authoritative visit questions and respects clearing on refresh', async () => {
    const { store } = await ready();
    await store.mutate((draft) => {
      draft.visits[0].questions = [];
      draft.visits[0].report = undefined;
    });
    await store.prepareVisit(seed().visits[0].id);
    expect(store.getState().snapshot!.visits[0].questions).toHaveLength(3);
    await store.mutate((draft) => {
      draft.visits[0].questions = [];
    });
    await store.prepareVisit(seed().visits[0].id);
    expect(store.getState().snapshot!.visits[0].report!.questions).toEqual([]);
  });
  it('rejects a transcript result if a user corrected source words during transcription', async () => {
    const response = deferred<AudioTranscription>(),
      transcribe = vi.fn(() => response.promise),
      { store } = await ready(transport({ transcribe }));
    const recording = { ...sample(), isSample: false, audioFilename: 'synthetic.webm' };
    await store.mutate((draft) => {
      draft.recordings = [recording];
    });
    await store.checkServer();
    const operation = store.transcribeRecording(recording.id);
    await vi.waitFor(() => expect(transcribe).toHaveBeenCalled());
    await store.mutate((draft) => {
      draft.recordings[0].segments[0].text = 'User-reviewed words';
    });
    response.resolve({
      text: 'Generated words',
      segments: [{ id: 'generated', speaker: 'Speaker', text: 'Generated words', start: 0, end: 5 }],
      model: 'mock-whisper',
    });
    await expect(operation).rejects.toThrow('changed during transcription');
    expect(store.getState().snapshot!.recordings[0].segments[0].text).toBe('User-reviewed words');
  });
});

// MARK: - CAS failures and incomplete original downloads preserve the browser's existing copy.
describe('explicit server synchronization', () => {
  it('requires known revision and accepts an empty owner tombstone on first check', async () => {
    const push = vi.fn(async (_snapshot: import('../models.ts').AppSnapshot, _revision: number) => 8),
      { store } = await ready(
        transport({
          pull: async () => {
            throw new APIError(404, 7);
          },
          push,
        }),
      );
    await expect(store.pushToServer()).rejects.toThrow('Check the connection');
    expect(push).not.toHaveBeenCalled();
    await store.checkServer();
    expect(store.getState().serverRevision).toBe(7);
    await store.pushToServer();
    expect(push.mock.calls[0][1]).toBe(7);
    expect(store.getState().serverRevision).toBe(8);
  });
  it('does not advance a stale write revision after a conflict or a subsequent check', async () => {
    let remote = 1;
    const push = vi.fn(async () => {
        throw new APIError(409, 2);
      }),
      { store } = await ready(
        transport({ pull: async () => ({ snapshot: seed(), revision: remote }), push }),
      );
    await store.checkServer();
    await store.mutate((draft) => {
      draft.profile.careNotes = 'Keep local';
    });
    remote = 2;
    await expect(store.pushToServer()).rejects.toMatchObject({ status: 409 });
    await store.checkServer();
    expect(store.getState().serverRevision).toBe(1);
    expect(store.getState().snapshot!.profile.careNotes).toBe('Keep local');
    await expect(store.pushToServer()).rejects.toThrow('pull');
    expect(push).toHaveBeenCalledTimes(1);
    await store.pullFromServer();
    expect(store.getState().serverRevision).toBe(2);
  });
  it('keeps all old originals and the local snapshot after any download fails', async () => {
    const repository = new MemoryRepository(),
      filename = seed().records[0].sourceFilename!;
    repository.attachments.set(filename, new Blob(['existing original']));
    let count = 0;
    const { store } = await ready(
      transport({
        pull: async () => ({ revision: 4, snapshot: seed() }),
        attachment: async () => {
          if (++count === 2) throw new Error('Missing source');
          return new Blob(['downloaded first']);
        },
      }),
      repository,
    );
    await store.mutate((draft) => {
      draft.profile.careNotes = 'Keep local notes';
    });
    const original = structuredClone(store.getState().snapshot);
    await expect(store.pullFromServer()).rejects.toThrow('Missing source');
    expect(store.getState().snapshot).toEqual(original);
    expect(await repository.attachments.get(filename)!.text()).toBe('existing original');
    expect(store.getState().serverRevision).toBeNull();
  });
  it('preserves edits made while originals were downloading', async () => {
    const download = deferred<Blob>(),
      attachment = vi.fn(() => download.promise),
      { store } = await ready(
        transport({ pull: async () => ({ revision: 4, snapshot: seed() }), attachment }),
      );
    const operation = store.pullFromServer();
    await vi.waitFor(() => expect(attachment).toHaveBeenCalled());
    await store.mutate((draft) => {
      draft.profile.careNotes = 'Edited during download';
    });
    download.resolve(new Blob(['remote source']));
    await expect(operation).rejects.toThrow('edited this browser');
    expect(store.getState().snapshot!.profile.careNotes).toBe('Edited during download');
  });
  it('resets capability/revision state when changing session identity and never persists its token', async () => {
    const { store, repository } = await ready();
    await store.checkServer();
    store.setConnectedAI(true);
    store.setToken('new-private-token');
    expect(store.getState()).toMatchObject({
      serverRevision: null,
      providers: null,
      connectedAI: false,
      token: 'new-private-token',
    });
    expect(JSON.stringify(repository.saved)).not.toContain('new-private-token');
  });
});
