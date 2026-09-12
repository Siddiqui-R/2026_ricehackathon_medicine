// Purpose: Prevent legacy clipped local summaries from being sent as source evidence during preparation.
// Inputs: Synthetic saved records and a capturing provider transport injected into the real store.
// Outputs: Assertions for repaired payload previews, unchanged full text, and retained attributed summaries.
// Side effects: Test-memory snapshots only; the transport double makes no provider requests.

import { expect, it, vi } from 'vitest';
import { RevaStore, type APITransport } from '../../core/store';
import { MemoryRepository, transport } from '../../core/__tests__/fixtures';

// MARK: - Outbound preparation payloads use current complete-line local excerpts without rewriting saved records
it('refreshes only unattributed local summaries in the provider payload and retains every complete source', async () => {
  const prepare = vi.fn<APITransport['prepare']>().mockResolvedValue({
    overview: 'Mock source overview.',
    questions: [],
    selectedRecordIDs: [],
    model: 'mock-model',
  });
  const store = new RevaStore(new MemoryRepository(), () => transport({ prepare }));
  await store.initialize();
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
  });
  const savedRecords = structuredClone(store.getState().snapshot!.records);
  await store.checkServer();
  store.setConnectedAI(true);
  await store.prepareVisit(store.getState().snapshot!.visits[0].id);
  const candidates = prepare.mock.calls[0][1];
  expect(candidates[0].summary).toBe('Complete source dose: 12.5 mg.');
  expect(candidates[0].text).toBe(savedRecords[0].text);
  expect(candidates[1].summary).toBe('Attributed overview.');
  expect(candidates[2].summary).toBe('Authored fictional overview.');
  expect(store.getState().snapshot!.records).toEqual(savedRecords);
});
