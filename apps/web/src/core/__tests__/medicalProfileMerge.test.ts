// Purpose: Prevent automatic account merges from turning stale generated facts into permanent manual data.
// Inputs: Synthetic simultaneous AI results and patient corrections on separate devices.
// Outputs: Assertions for coherent provenance and preservation of manual additions and removals.
// Side effects: None outside in-memory fixtures.
import { describe, expect, it } from 'vitest';
import { applyMedicalProfile, emptyProfileFacts } from '../medicalProfileAI';
import { mergeSnapshots } from '../syncMerge';
import { seed } from './fixtures';

// MARK: - Only the selected AI bundle survives; its facts remain replaceable.
describe('medical profile sync', () => {
  it('keeps one generated wording and removes it when sources disappear', () => {
    const base = seed(),
      local = seed(),
      remote = seed();
    const result = (text: string) => ({
      ...emptyProfileFacts(),
      model: 'mock-gemini',
      conditions: [{ text, recordIDs: [base.records[0].id] }],
    });
    local.profile = applyMedicalProfile(
      local.profile,
      result('History of asthma'),
      'a'.repeat(64),
      '2026-09-12T12:00:00Z',
    );
    remote.profile = applyMedicalProfile(
      remote.profile,
      result('Asthma documented'),
      'a'.repeat(64),
      '2026-09-12T12:00:00Z',
    );
    local.profile.conditions.push('My own history');
    const merged = mergeSnapshots(base, local, remote).snapshot.profile;
    expect(merged.conditions).not.toContain('History of asthma');
    expect(merged.conditions).toContain('Asthma documented');
    expect(merged.conditions).toContain('My own history');
    const cleared = applyMedicalProfile(
      merged,
      { ...emptyProfileFacts(), model: 'none' },
      'b'.repeat(64),
      '2026-09-12T13:00:00Z',
    );
    expect(cleared.conditions).toEqual([...base.profile.conditions, 'My own history']);
  });
  it('carries a manual correction across a different generated wording on another device', () => {
    const base = seed();
    const result = (text: string) => ({
      ...emptyProfileFacts(),
      model: 'mock-gemini',
      allergies: [{ text, recordIDs: [base.records[0].id] }],
    });
    base.profile = applyMedicalProfile(
      base.profile,
      result('Penicillin allergy'),
      'a'.repeat(64),
      '2026-09-12T12:00:00Z',
    );
    const local = structuredClone(base),
      remote = structuredClone(base);
    local.profile.allergies = ['Patient-corrected allergy history'];
    remote.profile = applyMedicalProfile(
      remote.profile,
      result('Allergic to penicillin'),
      'b'.repeat(64),
      '2026-09-12T13:00:00Z',
    );
    const merged = mergeSnapshots(base, local, remote).snapshot.profile;
    expect(merged.allergies).toEqual(['Patient-corrected allergy history']);
    expect(merged.aiMedicalHistory?.suppressedRecordIDs?.allergies).toContain(base.records[0].id);
  });
});
