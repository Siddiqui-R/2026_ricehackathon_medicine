// Purpose: Protect personal brief edits against generated questions and concurrent user changes.
// Inputs: Synthetic visits and the real serialized store with no connected providers.
// Outputs: Assertions for field-targeted merges, clearing, and all-or-nothing conflict rejection.
// Side effects: Test-memory persistence only; no browser data or outbound requests.

import { describe, expect, it } from 'vitest';
import { RevaStore } from '../../core/store';
import { MemoryRepository, seed, transport } from '../../core/__tests__/fixtures';
import { applyBriefNotesValues } from './briefNotesEdits';

// MARK: - Local generation and personal edits share the actual serialized mutation boundary
describe('brief notes editor merges', () => {
  it('preserves generated questions when the user edited only notes', async () => {
    const store = new RevaStore(new MemoryRepository(), () => transport());
    await store.initialize();
    await store.mutate((draft) => {
      draft.visits[0].questions = [];
      draft.visits[0].report = null;
    });
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    await store.prepareVisit(baseline.id);
    const questions = [...store.getState().snapshot!.visits[0].questions];
    expect(questions.length).toBeGreaterThan(0);
    await store.mutate((draft) =>
      applyBriefNotesValues(draft, baseline.id, { questions: [], notes: 'My new personal notes.' }, baseline),
    );
    const saved = store.getState().snapshot!.visits[0];
    expect(saved.questions).toEqual(questions);
    expect(saved.report!.questions).toEqual(questions);
    expect(saved.notes).toBe('My new personal notes.');
    expect(saved.report!.notes).toBe(saved.notes);
  });

  it('checks every changed field before applying any change on a conflict', () => {
    const snapshot = seed();
    const baseline = structuredClone(snapshot.visits[0]);
    snapshot.visits[0].notes = 'A note saved in another editor.';
    const latest = structuredClone(snapshot);
    expect(() =>
      applyBriefNotesValues(
        snapshot,
        baseline.id,
        {
          questions: ['A changed question?'],
          notes: 'A conflicting note.',
        },
        baseline,
      ),
    ).toThrow('changed while this editor was open');
    expect(snapshot).toEqual(latest);
  });

  it('allows explicit clearing and preserves concurrent notes when only questions were edited', () => {
    const snapshot = seed();
    snapshot.visits[0].questions = ['Opening question?'];
    const baseline = structuredClone(snapshot.visits[0]);
    snapshot.visits[0].notes = 'Newer notes to retain.';
    applyBriefNotesValues(snapshot, baseline.id, { questions: [], notes: baseline.notes }, baseline);
    expect(snapshot.visits[0].questions).toEqual([]);
    expect(snapshot.visits[0].notes).toBe('Newer notes to retain.');
  });

  it('accepts identical concurrent changes and rejects a deleted visit', () => {
    const snapshot = seed();
    const baseline = structuredClone(snapshot.visits[0]);
    snapshot.visits[0].notes = 'Shared new notes.';
    const values = { questions: baseline.questions, notes: 'Shared new notes.' };
    applyBriefNotesValues(snapshot, baseline.id, values, baseline);
    expect(snapshot.visits[0].notes).toBe(values.notes);
    snapshot.visits = [];
    expect(() => applyBriefNotesValues(snapshot, baseline.id, values, baseline)).toThrow(
      'no longer available',
    );
    expect(snapshot.visits).toEqual([]);
  });
});
