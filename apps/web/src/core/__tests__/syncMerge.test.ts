// Purpose: Verify that bidirectional reconciliation retains independent and conflicting user work.
// Inputs: Fictional snapshots changed separately against a shared baseline.
// Outputs: Assertions for deletions, recoverable collisions, relationship integrity and idempotent retries.
// Side effects: None outside test memory.
import { describe, expect, it } from 'vitest';
import { mergeSnapshots, sameSyncValue } from '../syncMerge';
import { seed } from './fixtures';

// MARK: - Three-way changes combine by field and identity, with no timestamp guesses.
describe('automatic snapshot merge', () => {
  it('merges independent record edits and additions while applying known deletions', () => {
    const base = seed(),
      local = seed(),
      remote = seed();
    local.records[0].notes = 'Local user note';
    local.records[0].version += 1;
    remote.records[0].title = 'Title from other device';
    remote.records[0].version += 2;
    const removed = base.records[1].id;
    local.records = local.records.filter((item) => item.id !== removed);
    remote.records.push({ ...remote.records[0], id: 'new-remote-record' });
    const result = mergeSnapshots(base, local, remote);
    expect(result.recovered).toBe(0);
    expect(result.snapshot.records.find((item) => item.id === base.records[0].id)).toMatchObject({
      notes: 'Local user note',
      title: 'Title from other device',
      version: 4,
    });
    expect(result.snapshot.records.some((item) => item.id === removed)).toBe(false);
    expect(result.snapshot.records.some((item) => item.id === 'new-remote-record')).toBe(true);
  });
  it('preserves a local conflicting report as a labeled deterministic copy', () => {
    const base = seed(),
      local = seed(),
      remote = seed();
    local.records[0].text = 'Exact local source text';
    remote.records[0].text = 'Exact remote source text';
    const merged = mergeSnapshots(base, local, remote);
    expect(merged.recovered).toBe(1);
    expect(merged.snapshot.records.find((item) => item.id === base.records[0].id)?.text).toBe(
      'Exact remote source text',
    );
    const copy = merged.snapshot.records.find((item) => item.id.startsWith('sync-copy-'))!;
    expect(copy.text).toBe('Exact local source text');
    expect(copy.title).toContain('saved on another device');
    const retried = mergeSnapshots(remote, merged.snapshot, remote);
    expect(retried.snapshot.records.filter((item) => item.id === copy.id)).toHaveLength(1);
    expect(retried.recovered).toBe(0);
  });
  it('keeps an edited item if another device deleted its old version', () => {
    const base = seed(),
      local = seed(),
      remote = seed();
    local.records[0].notes = 'Edited during deletion';
    remote.records.shift();
    expect(
      mergeSnapshots(base, local, remote).snapshot.records.find((item) => item.id === base.records[0].id)
        ?.notes,
    ).toBe('Edited during deletion');
  });
  it('unions unknown-baseline collections instead of interpreting absence as deletion', () => {
    const local = seed(),
      remote = seed();
    local.records.splice(0, 1);
    remote.records.splice(1, 1);
    expect(mergeSnapshots(null, local, remote).snapshot.records).toHaveLength(seed().records.length);
  });
  it('merges profile list additions and removals and preserves conflicting demographics for review', () => {
    const base = seed(),
      local = seed(),
      remote = seed();
    base.profile.conditions = ['Before'];
    local.profile.conditions = ['Local'];
    remote.profile.conditions = ['Before', 'Remote'];
    local.profile.name = 'Name entered on device one';
    remote.profile.name = 'Name entered on device two';
    const result = mergeSnapshots(base, local, remote);
    expect(result.snapshot.profile.conditions).toEqual(['Remote', 'Local']);
    expect(result.snapshot.profile.name).toBe(remote.profile.name);
    const recovery = result.snapshot.records.find((record) => record.kind === 'Sync recovery')!;
    expect(recovery.text).toContain(local.profile.name);
    expect(recovery.notes).toMatch(/not a medical report/);
  });
  it('compares objects independent of JSON field order', () => {
    expect(sameSyncValue({ a: 1, b: { c: 2 } }, { b: { c: 2 }, a: 1 })).toBe(true);
  });
});
