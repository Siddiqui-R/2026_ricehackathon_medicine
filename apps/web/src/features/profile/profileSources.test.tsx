// Purpose: Prevent source controls from attributing manual or changed medical facts to unrelated records.
// Inputs: Synthetic profile facts, missing/edited reports, and rendered source controls.
// Outputs: Regression assertions for explicit provenance and accessible citation navigation.
// Side effects: None outside test memory; never calls an AI provider or opens patient documents.

import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { seed } from '../../core/__tests__/fixtures';
import { emptyProfileFacts } from '../../core/medicalProfileAI';
import { demoSnapshot } from '../../core/demoProfiles';
import { SourceLink } from '../../components/SourceLink';
import { profileSources } from './profileSources';

// MARK: - Report identifiers, never similarity, establish the displayed provenance
describe('profile source destinations', () => {
  it('links an unchanged authored demo fact to its actual source', () => {
    const { profile, records } = seed();
    expect(profileSources(profile, records, 'allergies', profile.allergies[0])).toEqual([
      { href: '#/records/demo-record-history', label: 'Medication, allergy and health history' },
    ]);
    expect(profileSources(profile, records, 'allergies', 'Penicillin - new reaction')).toEqual([]);
    expect(profileSources({ ...profile, isDemo: false }, records, 'allergies', profile.allergies[0])).toEqual(
      [],
    );
  });

  it('does not retain authored demo citations after deletion or source edits', () => {
    const { profile, records } = seed();
    const withoutHistory = records.filter((record) => record.id !== 'demo-record-history');
    expect(profileSources(profile, withoutHistory, 'allergies', profile.allergies[0])).toEqual([]);
    const edited = records.map((record) =>
      record.id === 'demo-record-history' ? { ...record, text: 'Corrected source', version: 2 } : record,
    );
    expect(profileSources(profile, edited, 'allergies', profile.allergies[0])).toEqual([]);
  });

  it('uses only existing explicit AI sources and encodes their IDs', () => {
    const { profile, records } = seed();
    const id = 'report / 1?revision';
    const text = 'A source-backed care note';
    profile.aiMedicalHistory = {
      sourceSignature: 'test',
      generatedAt: '2026-09-12T12:00:00Z',
      model: 'test',
      facts: { ...emptyProfileFacts(), careNotes: [{ text, recordIDs: [id, id, 'missing'] }] },
    };
    const source = { ...records[0], id, title: 'Original report', version: 3, isDemo: false };
    expect(profileSources(profile, [source], 'careNotes', text)).toEqual([
      { href: '#/records/report%20%2F%201%3Frevision', label: 'Original report' },
    ]);
    expect(profileSources(profile, [source], 'careNotes', 'My edited care note')).toEqual([]);
  });

  it('does not replace missing AI citations with fallback demo citations', () => {
    const { profile, records } = seed();
    profile.aiMedicalHistory = {
      sourceSignature: 'test',
      generatedAt: '2026-09-12T12:00:00Z',
      model: 'test',
      facts: { ...emptyProfileFacts(), allergies: [{ text: profile.allergies[0], recordIDs: ['missing'] }] },
    };
    expect(profileSources(profile, records, 'allergies', profile.allergies[0])).toEqual([]);
  });

  it('keeps distinct demo people tied to their own authored reports', () => {
    const maya = demoSnapshot(seed(), 'maya');
    const alex = demoSnapshot(seed(), 'alex');
    expect(profileSources(maya.profile, maya.records, 'conditions', maya.profile.conditions[0])[0].href).toBe(
      '#/records/demo-maya-record-3',
    );
    expect(
      profileSources(
        alex.profile,
        alex.records,
        'surgeriesAndImplants',
        alex.profile.surgeriesAndImplants![0],
      )[0].href,
    ).toBe('#/records/demo-alex-record-1');
    expect(profileSources(maya.profile, maya.records, 'allergies', maya.profile.allergies[0])).toEqual([]);
  });
});

// MARK: - A compact visual still names its source for keyboard and screen-reader users
describe('source link accessibility', () => {
  it('renders a named link for one source and no icon without evidence', () => {
    const html = renderToStaticMarkup(
      <SourceLink sources={[{ href: '#/records/one', label: 'Original report' }]} />,
    );
    expect(html).toContain('href="#/records/one"');
    expect(html).toContain('aria-label="View source: Original report"');
    expect(renderToStaticMarkup(<SourceLink sources={[]} />)).toBe('');
  });
  it('offers the source picker only when multiple distinct sources exist', () => {
    const sources = [
      { href: '#/records/one', label: 'First report' },
      { href: '#/records/two', label: 'Second report' },
    ];
    const html = renderToStaticMarkup(<SourceLink sources={[...sources, sources[0]]} />);
    expect(html).toContain('aria-label="View 2 sources"');
    expect(html).toContain('aria-haspopup="dialog"');
    expect(html).not.toContain('href=');
  });
});
