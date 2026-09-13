// Purpose: Protect manual medical details and require source-backed generated profile updates.
// Inputs: Synthetic reports, AI responses and manual corrections.
// Outputs: Regression checks for provenance, replacement, deletion and response validation.
// Side effects: None outside in-memory test fixtures.
import { describe, expect, it } from 'vitest';
import {
  applyMedicalProfile,
  emptyProfileFacts,
  profileSources,
  validateProfileResult,
  validateProfileSources,
} from '../medicalProfileAI';
import { seed } from './fixtures';

// MARK: - Generated facts can change without erasing patient-authored history.
const result = () => ({
  ...emptyProfileFacts(),
  model: 'mock-gemini',
  conditions: [{ text: 'Documented condition', recordIDs: ['report-1'] }],
});
describe('AI medical profile', () => {
  it('preserves identity and manual details while replacing prior generated facts', () => {
    const profile = seed().profile;
    const first = applyMedicalProfile(profile, result(), 'a'.repeat(64), '2026-09-12T12:00:00Z');
    expect(first.conditions).toEqual([...profile.conditions, 'Documented condition']);
    const next = applyMedicalProfile(
      first,
      {
        ...result(),
        conditions: [{ text: 'Documented condition resolved on September 12', recordIDs: ['report-2'] }],
      },
      'b'.repeat(64),
      '2026-09-12T13:00:00Z',
    );
    expect(next.conditions).toEqual([...profile.conditions, 'Documented condition resolved on September 12']);
    expect(next.name).toBe(profile.name);
    expect(next.dateOfBirth).toBe(profile.dateOfBirth);
    expect(next.allergies).toEqual(profile.allergies);
  });
  it('does not restore generated text removed or corrected manually', () => {
    const profile = applyMedicalProfile(seed().profile, result(), 'a'.repeat(64), '2026-09-12T12:00:00Z');
    profile.conditions = ['My corrected history'];
    const updated = applyMedicalProfile(profile, result(), 'b'.repeat(64), '2026-09-12T13:00:00Z');
    expect(updated.conditions).toEqual(['My corrected history']);
    expect(applyMedicalProfile(updated, result(), 'c'.repeat(64), '2026-09-12T14:00:00Z').conditions).toEqual(
      ['My corrected history'],
    );
  });
  it('keeps identical preexisting manual facts after their source is deleted', () => {
    const profile = seed().profile;
    profile.conditions = ['Documented condition'];
    const first = applyMedicalProfile(profile, result(), 'a'.repeat(64), '2026-09-12T12:00:00Z');
    expect(first.aiMedicalHistory?.facts.conditions).toEqual([]);
    expect(
      applyMedicalProfile(
        first,
        { ...emptyProfileFacts(), model: 'none' },
        'b'.repeat(64),
        '2026-09-12T13:00:00Z',
      ).conditions,
    ).toEqual(['Documented condition']);
  });
  it('does not reintroduce a corrected source with different AI wording', () => {
    const profile = applyMedicalProfile(seed().profile, result(), 'a'.repeat(64), '2026-09-12T12:00:00Z');
    profile.conditions = ['My corrected history'];
    const updated = applyMedicalProfile(
      profile,
      {
        ...result(),
        conditions: [
          { text: 'The same condition paraphrased', recordIDs: ['report-1'] },
          { text: 'New independently documented fact', recordIDs: ['report-2'] },
        ],
      },
      'b'.repeat(64),
      '2026-09-12T13:00:00Z',
    );
    expect(updated.conditions).toEqual(['My corrected history', 'New independently documented fact']);
  });
  it('removes only generated care notes when reports no longer support them', () => {
    const profile = seed().profile;
    profile.careNotes = 'My own care note';
    const first = applyMedicalProfile(
      profile,
      { ...result(), careNotes: [{ text: 'Recorded follow-up', recordIDs: ['report-1'] }] },
      'a'.repeat(64),
      '2026-09-12T12:00:00Z',
    );
    expect(first.careNotes).toBe('My own care note\nRecorded follow-up');
    expect(
      applyMedicalProfile(
        first,
        { ...emptyProfileFacts(), model: 'none' },
        'b'.repeat(64),
        '2026-09-12T13:00:00Z',
      ).careNotes,
    ).toBe('My own care note');
  });
  it('normalizes multiline generated facts so deleting sources removes the complete fact', () => {
    const profile = seed().profile;
    profile.careNotes = 'My note';
    const first = applyMedicalProfile(
      profile,
      { ...result(), careNotes: [{ text: 'Recorded follow-up\ncontinued detail', recordIDs: ['report-1'] }] },
      'a'.repeat(64),
      '2026-09-12T12:00:00Z',
    );
    expect(first.careNotes).toBe('My note\nRecorded follow-up continued detail');
    expect(
      applyMedicalProfile(
        first,
        { ...emptyProfileFacts(), model: 'none' },
        'b'.repeat(64),
        '2026-09-12T13:00:00Z',
      ).careNotes,
    ).toBe('My note');
  });
});

// MARK: - All readable original reports are considered; invalid output never becomes profile data.
describe('profile evidence boundary', () => {
  it('ignores recovered copies and empty reports and never sends AI summaries as source text', () => {
    const snapshot = seed();
    snapshot.records = [
      {
        ...snapshot.records[0],
        id: 'report-1',
        text: 'Original source',
        summary: 'Different generated summary',
      },
      { ...snapshot.records[0], id: 'recovery', kind: 'Sync recovery', text: 'Recovered edits' },
      { ...snapshot.records[0], id: 'empty', text: ' ' },
    ];
    expect(profileSources(snapshot)).toEqual([
      {
        id: 'report-1',
        version: 1,
        title: snapshot.records[0].title,
        date: snapshot.records[0].date,
        text: 'Original source',
      },
    ]);
  });
  it('rejects unknown citations, empty evidence, oversized facts and extra fields', () => {
    const records = [{ id: 'report-1', version: 1, title: 'Report', date: '2026-09-12', text: 'Source' }];
    expect(validateProfileResult(result(), records)).toEqual(result());
    for (const value of [
      { ...result(), conditions: [{ text: 'Claim', recordIDs: ['other'] }] },
      { ...result(), conditions: [{ text: 'Claim', recordIDs: [] }] },
      { ...result(), conditions: [{ text: 'a'.repeat(501), recordIDs: ['report-1'] }] },
      { ...result(), name: 'Not permitted' },
    ])
      expect(() => validateProfileResult(value, records)).toThrow(/invalid/);
  });
  it('rejects oversized input without silently dropping reports', () => {
    const records = [
      { id: 'report-1', version: 1, title: 'Report', date: '2026-09-12', text: 'é'.repeat(50_001) },
    ];
    expect(() => validateProfileSources(records)).toThrow(/100 KB/);
  });
});
