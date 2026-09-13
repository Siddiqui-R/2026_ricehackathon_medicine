// Purpose: Verify transient preparation and standalone recording persistence boundaries.
// Inputs: Fictional snapshots, in-memory repositories, and mocked provider responses.
// Outputs: Assertions for uncached requests, stale results, source validation, and atomic audio saves.
// Side effects: Mutates isolated test stores only; no network or microphone access.

// MARK: - Mocked brief requests and standalone recording contracts
import { describe, it, expect, vi } from 'vitest';
import { RevaStore } from '../store';
import { BRIEF_MODEL, briefVisit, clinicalBrief, briefSources } from '../visitBrief';
import { deferred, MemoryRepository, sample, seed, transport } from './fixtures';
import type { AIPreparation } from '../models';

const input = { type: 'Cardiology follow-up', concern: 'Intermittent palpitations', questions: [] };
const response: AIPreparation = {
  overview: 'Reason: Intermittent palpitations.',
  questions: ['What follow-up is needed?'],
  selectedRecordIDs: [],
  model: BRIEF_MODEL,
};
async function ready(prepare = async () => response) {
  const repository = new MemoryRepository();
  const provider = vi.fn(prepare);
  const store = new RevaStore(repository, () => transport({ prepare: provider }));
  await store.initialize();
  return { repository, provider, store };
}
describe('on-demand visit brief', () => {
  it('calls Gemini for every request, includes profile context, and creates no saved appointment', async () => {
    const { store, repository, provider } = await ready();
    const before = structuredClone(repository.saved);
    expect(store.getState().connectedAI).toBe(false);
    await store.generateVisitBrief(input);
    await store.generateVisitBrief(input);
    expect(provider).toHaveBeenCalledTimes(2);
    const sources = (
      provider.mock.calls[0] as unknown as [unknown, { title: string; text: string; date: string }[]]
    )[1];
    expect(sources.at(-1)?.title).toBe('Medical profile');
    expect(sources.at(-1)?.text).toContain('medications');
    expect(sources.every((source) => Boolean(source.date.trim()))).toBe(true);
    const visit = (provider.mock.calls[0] as unknown as [unknown, unknown])[0];
    expect(visit).toMatchObject({ goal: expect.stringContaining('upcoming appointment') });
    expect(repository.saved).toEqual(before);
  });
  it('surfaces provider failure without falling back to a local report', async () => {
    const { store, repository } = await ready(async () => {
      throw new Error('Gemini unavailable');
    });
    const before = structuredClone(repository.saved);
    await expect(store.generateVisitBrief(input)).rejects.toThrow('Gemini unavailable');
    expect(repository.saved).toEqual(before);
  });
  it.each(['profile', 'records', 'identity'])('rejects a result after %s changes', async (change) => {
    const pending = deferred<AIPreparation>();
    const { store } = await ready(() => pending.promise);
    const generating = store.generateVisitBrief(input);
    if (change === 'identity') store.setToken('another-workspace');
    else
      await store.mutate((draft) => {
        if (change === 'profile') draft.profile.medications = ['Changed medication'];
        else draft.records[0].text += ' Changed source';
      });
    pending.resolve(response);
    await expect(generating).rejects.toThrow();
  });
  it.each([
    { ...response, model: 'other-model' },
    { ...response, selectedRecordIDs: ['unknown'] },
    { ...response, overview: 'word '.repeat(181) },
    { ...response, questions: Array(4).fill('Question?') },
  ])('rejects invalid or oversized output', (result) => {
    const snapshot = seed();
    expect(() => clinicalBrief(snapshot, briefVisit(input), briefSources(snapshot), result)).toThrow();
  });
});

describe('standalone home recording', () => {
  it('commits original audio without an appointment and keeps unknown nonempty visit IDs invalid', async () => {
    const { store, repository } = await ready();
    const visits = structuredClone(store.getState().snapshot!.visits);
    const recording = {
      ...sample(),
      id: 'standalone-recording',
      visitID: '',
      audioFilename: 'session.webm',
      isSample: false,
    };
    await store.saveRecording(recording, new Blob(['fictional audio']));
    expect(repository.saved!.snapshot.visits).toEqual(visits);
    expect(repository.saved!.snapshot.recordings).toContainEqual(recording);
    expect(await repository.attachments.get('session.webm')!.text()).toBe('fictional audio');
    await expect(
      store.saveRecording({ ...recording, id: 'second', visitID: 'missing' }, new Blob(['audio'])),
    ).rejects.toThrow('no longer available');
  });
  it('keeps a failed standalone audio save atomic', async () => {
    const { store, repository } = await ready();
    const before = structuredClone(repository.saved);
    repository.failure = new Error('Storage full');
    await expect(
      store.saveRecording(
        { ...sample(), id: 'standalone', visitID: '', audioFilename: 'session.webm' },
        new Blob(['audio']),
      ),
    ).rejects.toThrow('Storage full');
    expect(repository.saved).toEqual(before);
    expect(repository.attachments.size).toBe(0);
  });
});
