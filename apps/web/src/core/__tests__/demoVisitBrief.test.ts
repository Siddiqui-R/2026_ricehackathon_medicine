// Run the example through the real store; real account preparation must never receive fixture output.
import { describe, expect, it, vi } from 'vitest';
import { demoBriefDefaults, demoClinicalBrief } from '../demoVisitBrief';
import { demoPeople, demoSnapshot } from '../demoProfiles';
import { RevaStore } from '../store';
import { validateBriefText } from '../visitBrief';
import { authTransport, fakeStorage, MemoryRepository, seed, testUser, transport } from './fixtures';

describe('demo pre-visit examples', () => {
  it.each(demoPeople)(
    'runs $name without an API key or provider call and keeps all data unchanged',
    async ({ id }) => {
      const repository = new MemoryRepository();
      repository.saved!.snapshot = demoSnapshot(seed(), id);
      const api = vi.fn(() =>
        transport({
          prepare: vi.fn(() => {
            throw new Error('No provider available');
          }),
        }),
      );
      const store = new RevaStore(repository, api);
      await store.initialize();
      const snapshot = store.getState().snapshot!;
      const before = structuredClone(repository.saved);
      const defaults = demoBriefDefaults(snapshot)!;
      expect(defaults.type).not.toBe('');
      expect(defaults.concern).not.toBe('');
      expect(defaults.questions.length).toBeGreaterThan(0);
      const result = await store.generateVisitBrief(defaults);
      expect(result).toMatchObject({
        example: true,
        patient: { name: snapshot.profile.name },
      });
      expect(result.sources.length).toBeGreaterThan(0);
      expect(result.overviewSourceIDs).toEqual(result.sources.map((source) => source.id));
      expect(
        result.sources.every((source) => snapshot.records.some((record) => record.id === source.id)),
      ).toBe(true);
      expect(result.questions).toEqual(defaults.questions);
      expect(() => validateBriefText(result)).not.toThrow();
      expect(result.overview).not.toMatch(/[—–]/);
      expect(api).not.toHaveBeenCalled();
      expect(repository.saved).toEqual(before);
    },
  );
  it('uses separate orthopedic sources for Jordan and preserves edited questions', () => {
    const snapshot = seed();
    const visit = snapshot.visits.find((item) => item.type === 'Orthopedics')!;
    const brief = demoClinicalBrief(snapshot, {
      ...visit,
      questions: ['What does the interval imaging show?'],
    });
    expect(brief.overview).toContain('right distal fibula fracture');
    expect(brief.overview).toContain('separate from the 2026 fibula injury');
    expect(brief.sources.map((source) => source.id)).toEqual([
      'demo-record-fibula-injury',
      'demo-record-leg-imaging',
      'demo-record-tibia-procedure',
    ]);
    expect(brief.questions).toEqual(['What does the interval imaging show?']);
  });
  it('does not attach example claims to altered, removed, or personal sources', () => {
    const snapshot = seed();
    snapshot.records.find((record) => record.id === 'demo-record-ecg')!.text = 'Changed source';
    snapshot.records.find((record) => record.id === 'demo-record-labs')!.isDemo = false;
    snapshot.records = snapshot.records.filter((record) => record.id !== 'demo-record-asthma');
    const result = demoClinicalBrief(snapshot, demoBriefDefaults(snapshot)!);
    expect(result.sources.map((source) => source.id)).toEqual(['demo-record-symptom-diary']);
    expect(result.overview).not.toContain('82 beats');
    expect(result.overview).not.toContain('1.62');
    snapshot.records = [];
    expect(() => demoClinicalBrief(snapshot, demoBriefDefaults(snapshot)!)).toThrow('source records');
    snapshot.profile.isDemo = false;
    expect(demoBriefDefaults(snapshot)).toBeUndefined();
  });
  it('uses the real provider for account workspaces even if their profile carries a demo flag', async () => {
    const repository = new MemoryRepository();
    const user = { ...testUser, id: repository.saved!.snapshot.profile.id };
    const prepare = vi.fn(async () => ({
      overview: 'Provider response.',
      questions: [],
      selectedRecordIDs: [],
      model: 'actual-provider',
    }));
    const store = new RevaStore(repository, () => transport({ prepare }), {
      mode: 'account',
      token: 'synthetic-token',
      user,
      storage: fakeStorage(),
      authFactory: () => authTransport(),
    });
    await store.initialize();
    const result = await store.generateVisitBrief({ type: 'Primary care', concern: '', questions: [] });
    expect(prepare).toHaveBeenCalledOnce();
    expect(result.model).toBe('actual-provider');
    expect(result.example).toBeUndefined();
  });
});
