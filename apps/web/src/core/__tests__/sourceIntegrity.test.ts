// Purpose: Reproduce source quotation, fixture provenance and calendar-day defects.
// Inputs: Synthetic boundary text and the existing fictional acceptance snapshot.
// Outputs: Assertions against production browser domain functions.
// Side effects: In-memory report generation only; no provider calls or persistence.
import { describe, expect, it } from 'vitest';
import { formatDate, generateReport, localExcerpt, selectedRecords, reportIsStale } from '../domain';
import { seed } from './fixtures';

// MARK: - A preview must retain complete lines and exact source bytes.
describe('source integrity repairs', () => {
  it('never changes a dose by cutting through a long source line', async () => {
    const text = 'x'.repeat(1791) + ' dose: 100 mg';
    expect(localExcerpt(text)).toBe('');
    const data = seed();
    const record = { ...data.records[0], text, pageTexts: [text], isDemo: false };
    const visit = { ...data.visits[0], pinnedRecordIDs: [record.id] };
    const report = await generateReport(visit, [record]);
    expect(report.sections.find((section) => section.sources.length)?.body).toContain('Open the original');
  });
  it('keeps complete values, units, negation, Unicode and whitespace in a bounded exact span', () => {
    for (const finalLine of ['Dose: 100 mg', 'Potassium: 4.15 mmol/L', 'No chest pain', 'Dose: １０ µg 👩🏽‍⚕️']) {
      const prefix = '  Exact source line.\r\n';
      const text = prefix + 'x'.repeat(1790) + finalLine;
      expect(localExcerpt(text)).toBe('  Exact source line.');
      expect(text.includes(localExcerpt(text))).toBe(true);
      expect(localExcerpt(finalLine)).toBe(finalLine);
    }
  });
  it('preserves ordinary source headers and demonstration-like wording', () => {
    const text = 'Medication: synthetic A\nSource date: 2026-09-12\nPlan: synthetic follow-up';
    expect(localExcerpt(text)).toBe(text);
    const trailer = 'Before\nInvented for Reva software demonstration.\nAfter';
    expect(localExcerpt(trailer)).toBe(trailer);
  });
  it('excludes resolved ear infection from the completed primary visit unless pinned', () => {
    const data = seed();
    const visit = data.visits.find((item) => item.id === 'demo-visit-primary-20260908')!;
    expect(selectedRecords(visit, data.records).map((record) => record.id)).not.toContain(
      'demo-record-ear-infection',
    );
    visit.pinnedRecordIDs.push('demo-record-ear-infection');
    expect(selectedRecords(visit, data.records).map((record) => record.id)).toContain(
      'demo-record-ear-infection',
    );
  });
  it('displays timestamp days in their zone while preserving date-only document days', () => {
    expect(formatDate('2026-09-12T02:30:00Z', false, 'America/Chicago')).toContain('11');
    expect(formatDate('2026-09-12', false, 'America/Chicago')).toContain('12');
  });
  it('marks a pre-repair brief stale without rewriting its originals', async () => {
    const data = seed();
    const before = structuredClone(data.records);
    const visit = data.visits[0];
    visit.report = await generateReport(visit, data.records);
    expect(await reportIsStale(visit, data.records)).toBe(false);
    visit.report.sourceSignature = 'b2437a79a5c1570e95aa2b950dcfab9c4902cae100e345b3a916e46416b67731';
    expect(await reportIsStale(visit, data.records)).toBe(true);
    expect(data.records).toEqual(before);
  });
});
