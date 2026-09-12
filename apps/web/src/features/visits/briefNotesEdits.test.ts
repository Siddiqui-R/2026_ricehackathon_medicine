// Purpose: Reproduce notes-editor saves racing with generated questions and other local edits.
// Inputs: The real serialized store, fictional visits and captured editor-opening baselines.
// Outputs: Assertions for changed-field merging, conflict atomicity and explicit clearing.
// Side effects: Isolated test-memory state only; no browser storage or connected services.

import { describe, expect, it } from 'vitest';
import { RevaStore } from '../../core/store';
import { deferred, MemoryRepository, transport } from '../../core/__tests__/fixtures';
import { applyBriefNotes } from './briefNotesEdits';

async function ready() {
  const store = new RevaStore(new MemoryRepository(), () => transport());
  await store.initialize();
  await store.mutate((draft) => {
    draft.visits[0].questions = [];
    draft.visits[0].notes = '';
    draft.visits[0].report = null;
  });
  return store;
}

// MARK: - Untouched editor fields retain same-store changes made after the editor opened
describe('questions and notes editor concurrency', () => {
  it('preserves questions generated after opening when the user saves notes only', async () => {
    const store = await ready();
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    await store.prepareVisit(baseline.id);
    const questions = [...store.getState().snapshot!.visits[0].questions];
    expect(questions.length).toBeGreaterThan(0);
    await store.mutate((draft) =>
      applyBriefNotes(draft, baseline, { questions: baseline.questions, notes: 'My new notes' }),
    );
    const saved = store.getState().snapshot!.visits[0];
    expect(saved.questions).toEqual(questions);
    expect(saved.notes).toBe('My new notes');
    expect(saved.report!.questions).toEqual(questions);
    expect(saved.report!.notes).toBe(saved.notes);
  });

  it('preserves notes queued ahead of saving an edited question', async () => {
    const store = await ready();
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    const gate = deferred<void>();
    const preceding = store.mutate(async (draft) => {
      await gate.promise;
      draft.visits[0].notes = 'Notes already saved elsewhere';
    });
    const saving = store.mutate((draft) =>
      applyBriefNotes(draft, baseline, { questions: ['My question?'], notes: baseline.notes }),
    );
    gate.resolve();
    await preceding;
    await saving;
    expect(store.getState().snapshot!.visits[0]).toMatchObject({
      questions: ['My question?'],
      notes: 'Notes already saved elsewhere',
    });
  });

  // MARK: - A competing field rejects the entire save, including independently valid changes
  it('rejects a competing edit without partially updating either the visit or report', async () => {
    const store = await ready();
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    await store.prepareVisit(baseline.id);
    const before = structuredClone(store.getState().snapshot);
    await expect(
      store.mutate((draft) =>
        applyBriefNotes(draft, baseline, { questions: ['Competing question?'], notes: 'Unsaved notes' }),
      ),
    ).rejects.toThrow('changed while this editor was open');
    expect(store.getState().snapshot).toEqual(before);
  });

  it('accepts an already-converged field and explicit clearing from a current baseline', async () => {
    const store = await ready();
    await store.prepareVisit(store.getState().snapshot!.visits[0].id);
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    const values = { questions: ['Shared question?'], notes: 'Shared notes' };
    await store.mutate((draft) => applyBriefNotes(draft, baseline, values));
    await store.mutate((draft) => applyBriefNotes(draft, baseline, values));
    const current = structuredClone(store.getState().snapshot!.visits[0]);
    await store.mutate((draft) => applyBriefNotes(draft, current, { questions: [], notes: '' }));
    expect(store.getState().snapshot!.visits[0]).toMatchObject({
      questions: [],
      notes: '',
      report: { questions: [], notes: '' },
    });
  });

  it('does not recreate a visit deleted after opening', async () => {
    const store = await ready();
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    await store.mutate((draft) => {
      draft.visits = draft.visits.filter((visit) => visit.id !== baseline.id);
    });
    await expect(
      store.mutate((draft) => applyBriefNotes(draft, baseline, { questions: [], notes: 'My notes' })),
    ).rejects.toThrow('no longer available');
    expect(store.getState().snapshot!.visits.some((visit) => visit.id === baseline.id)).toBe(false);
  });
});
