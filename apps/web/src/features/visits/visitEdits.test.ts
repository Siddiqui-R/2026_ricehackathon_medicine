// Purpose: Protect appointment saves from overwriting queued reports, questions, or unrelated edits.
// Inputs: The real serialized RevaStore with synthetic fixtures and delayed in-memory mutations.
// Outputs: Vitest assertions for merge behavior, conflict rejection, and authoritative questions.
// Side effects: Test-memory snapshot writes only; no browser storage, network, or provider is used.

import { describe, expect, it } from 'vitest';
import type { Visit } from '../../core/models';
import { generateReport } from '../../core/domain';
import { RevaStore } from '../../core/store';
import { deferred, MemoryRepository, seed, transport } from '../../core/__tests__/fixtures';
import { applyVisitEditorValues, type VisitEditorValues } from './visitEdits';

function values(visit: Visit): VisitEditorValues {
  return structuredClone({
    title: visit.title,
    type: visit.type,
    provider: visit.provider,
    clinic: visit.clinic,
    date: visit.date,
    timeZone: visit.timeZone,
    concern: visit.concern,
    goal: visit.goal,
    questions: visit.questions,
    pinnedRecordIDs: visit.pinnedRecordIDs,
  });
}
async function ready() {
  const store = new RevaStore(new MemoryRepository(), () => transport());
  await store.initialize();
  return store;
}

// MARK: - Real serialized edits preserve state committed ahead of the appointment editor
describe('appointment editor concurrency', () => {
  it('retains a newer queued report, notes, status, and untouched clinic', async () => {
    const store = await ready();
    const snapshot = store.getState().snapshot!;
    const baseline = structuredClone(snapshot.visits[0]);
    const report = await generateReport(baseline, snapshot.records);
    const gate = deferred<void>();
    const preceding = store.mutate(async (draft) => {
      await gate.promise;
      const latest = draft.visits.find((visit) => visit.id === baseline.id)!;
      latest.report = report;
      latest.notes = 'Notes saved while the editor was open.';
      latest.status = 'completed';
      latest.clinic = 'Updated fictional clinic';
    });
    const entered = { ...values(baseline), title: 'My edited appointment title' };
    const saving = store.mutate((draft) => applyVisitEditorValues(draft, baseline.id, entered, baseline));
    gate.resolve();
    await preceding;
    await saving;
    const saved = store.getState().snapshot!.visits.find((visit) => visit.id === baseline.id)!;
    expect(saved.title).toBe(entered.title);
    expect(saved.report!.id).toBe(report.id);
    expect(saved.report!.sections).toEqual(report.sections);
    expect(saved.notes).toBe('Notes saved while the editor was open.');
    expect(saved.report!.notes).toBe(saved.notes);
    expect(saved.status).toBe('completed');
    expect(saved.clinic).toBe('Updated fictional clinic');
  });

  it('rejects competing changes to an edited field without applying other editor changes', async () => {
    const store = await ready(),
      baseline = structuredClone(store.getState().snapshot!.visits[0]);
    const first = store.mutate((draft) => {
      draft.visits[0].concern = 'New concern already saved elsewhere.';
    });
    const second = store.mutate((draft) =>
      applyVisitEditorValues(
        draft,
        baseline.id,
        { ...values(baseline), title: 'Unsaved title', concern: 'Different editor concern.' },
        baseline,
      ),
    );
    await first;
    await expect(second).rejects.toThrow('changed while you were editing');
    expect(store.getState().snapshot!.visits[0].title).toBe(baseline.title);
    expect(store.getState().snapshot!.visits[0].concern).toBe('New concern already saved elsewhere.');
  });

  // MARK: - User questions remain authoritative and untouched questions preserve newer suggestions
  it('keeps questions generated after an editor opened when its question field was untouched', async () => {
    const store = await ready();
    await store.mutate((draft) => {
      draft.visits[0].questions = [];
      draft.visits[0].report = null;
    });
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    await store.prepareVisit(baseline.id);
    const questions = [...store.getState().snapshot!.visits[0].questions];
    expect(questions.length).toBeGreaterThan(0);
    await store.mutate((draft) =>
      applyVisitEditorValues(
        draft,
        baseline.id,
        { ...values(baseline), title: 'Edited title only' },
        baseline,
      ),
    );
    expect(store.getState().snapshot!.visits[0].questions).toEqual(questions);
    expect(store.getState().snapshot!.visits[0].report!.questions).toEqual(questions);
  });

  it('applies explicit user questions and mirrors them into the current report, including clearing', async () => {
    const store = await ready();
    await store.prepareVisit(store.getState().snapshot!.visits[0].id);
    const baseline = structuredClone(store.getState().snapshot!.visits[0]);
    await store.mutate((draft) =>
      applyVisitEditorValues(
        draft,
        baseline.id,
        { ...values(baseline), questions: ['My own question?'] },
        baseline,
      ),
    );
    expect(store.getState().snapshot!.visits[0].report!.questions).toEqual(['My own question?']);
    const revised = structuredClone(store.getState().snapshot!.visits[0]);
    await store.mutate((draft) =>
      applyVisitEditorValues(draft, revised.id, { ...values(revised), questions: [] }, revised),
    );
    expect(store.getState().snapshot!.visits[0].questions).toEqual([]);
    expect(store.getState().snapshot!.visits[0].report!.questions).toEqual([]);
  });

  // MARK: - Coupled appointment time and deleted identities cannot be silently recreated
  it('rejects a new time when the time zone changed concurrently', () => {
    const snapshot = seed(),
      baseline = structuredClone(snapshot.visits[0]);
    snapshot.visits[0].timeZone = baseline.timeZone === 'UTC' ? 'America/New_York' : 'UTC';
    expect(() =>
      applyVisitEditorValues(
        snapshot,
        baseline.id,
        { ...values(baseline), date: '2026-09-20T10:30:00Z' },
        baseline,
      ),
    ).toThrow('changed while you were editing');
    expect(snapshot.visits[0].date).toBe(baseline.date);
  });

  it('refuses to recreate a deleted visit or duplicate an already-saved new visit', () => {
    const snapshot = seed(),
      baseline = structuredClone(snapshot.visits[0]);
    snapshot.visits = snapshot.visits.filter((visit) => visit.id !== baseline.id);
    expect(() => applyVisitEditorValues(snapshot, baseline.id, values(baseline), baseline)).toThrow(
      'no longer available',
    );
    expect(snapshot.visits.some((visit) => visit.id === baseline.id)).toBe(false);
    applyVisitEditorValues(snapshot, baseline.id, values(baseline));
    expect(() => applyVisitEditorValues(snapshot, baseline.id, values(baseline))).toThrow('already saved');
    expect(snapshot.visits.filter((visit) => visit.id === baseline.id)).toHaveLength(1);
  });
});
