// Purpose: Verify demo-person switching retains independent snapshots and original files.
// Inputs: Three authored demo people, real repository transactions over fake IndexedDB and bundled seed bytes.
// Outputs: Assertions for reload isolation, seed identity and whitelisted selection.
// Side effects: In-memory test databases only; no live storage or network.
import { IDBFactory } from 'fake-indexeddb';
import { expect, it } from 'vitest';
import { DemoRepository } from '../repository';
import { demoPeople, demoDatabaseName, selectedDemoPerson, demoPersonURL } from '../demoProfiles';
import { seed } from './fixtures';

// MARK: - Switching names cannot replace another person's edits or attachments
it('keeps all three people separate through saves, reset and reopening', async () => {
  const factory = new IDBFactory();
  const fetcher: typeof fetch = async () => new Response(JSON.stringify(seed()));
  for (const person of demoPeople) {
    const repository = new DemoRepository(person.id, factory, fetcher);
    const data = await repository.seed();
    expect(data.profile.initials).toBe(person.initials);
    expect(data.records.length).toBeGreaterThan(0);
    expect(data.visits.length).toBeGreaterThan(0);
    expect(data.profile.isDemo).toBe(true);
    if (person.id !== 'jordan') {
      expect(data.records.every((record) => record.id.includes(person.id))).toBe(true);
      expect(data.records.every((record) => !record.sourceFilename)).toBe(true);
    }
    data.profile.careNotes = `Saved for ${person.id}`;
    await repository.commit(data, 0, new Map([['personal.txt', new Blob([person.id])]]));
    await repository.close();
  }
  const maya = new DemoRepository('maya', factory, fetcher);
  await maya.reset(await maya.seed());
  await maya.close();
  for (const person of demoPeople) {
    const reopened = new DemoRepository(person.id, factory, fetcher);
    const saved = await reopened.load();
    if (person.id !== 'maya') expect(saved!.snapshot.profile.careNotes).toBe(`Saved for ${person.id}`);
    expect(await (await reopened.getAttachment('personal.txt')).text()).toBe(person.id);
    await reopened.close();
  }
});

// MARK: - Existing Jordan storage and same-origin navigation remain stable
it('keeps the existing default database and limits URL selection to known examples', () => {
  expect(demoDatabaseName('jordan')).toBe('reva-workspace-v1');
  expect(selectedDemoPerson('?demo=unknown')).toBe('jordan');
  expect(selectedDemoPerson('?demo=maya')).toBe('maya');
  expect(demoPersonURL('alex', 'https://example.test/demo?x=1#/profile')).toBe(
    'https://example.test/demo?x=1&demo=alex#/summary',
  );
});
