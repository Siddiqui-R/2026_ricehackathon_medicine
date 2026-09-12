// Purpose: Regress exact source spans, omission metadata, demo provenance and date-only display.
// Inputs: Synthetic boundary text, fixture records and saved JSON.
// Outputs: Assertions for the audited excerpt/relevance/date contracts.
// Side effects: In-memory report generation only.
import { describe, expect, it } from 'vitest';
import {
  excerptOmissionNotice,
  formatDate,
  generateReport,
  reportIsStale,
  localExcerpt,
  localExcerptDetails,
  selectedRecords,
  validateSnapshot,
} from '../domain';
import { seed } from './fixtures';

describe('source integrity regressions', () => {
  it('never splits doses, units, negation or Unicode at the cap', () => {
    for (const ending of [
      'dose: 100 mg',
      'potassium: 4.1 mmol/L',
      'No evidence of fracture',
      '👩🏽‍⚕️ reviewed café: 100 mg',
    ]) {
      const text = 'x'.repeat(1792) + '\n' + ending;
      const excerpt = localExcerptDetails(text);
      expect(excerpt.text).toBe('x'.repeat(1792));
      expect(excerpt.omitted).toBe(true);
      expect(text).toContain(excerpt.text);
      expect(excerpt.text).not.toContain('dose: 10');
    }
    const audited = 'x'.repeat(1792) + 'dose: 100 mg';
    expect(audited.slice(0, 1800).slice(-8)).toBe('dose: 10');
    expect(localExcerptDetails(audited)).toEqual({ text: '', omitted: true });
  });
  it('preserves contiguous whitespace and full lines', () => {
    const text = '  dose: 100 mg\r\n\r\n  Do not discontinue.\r\n👩🏽‍⚕️ reviewed café.';
    expect(localExcerpt(text)).toBe(text);
    const lines = Array.from({ length: 30 }, (_, index) => `line ${index + 1}`);
    expect(localExcerptDetails(lines.join('\n'))).toEqual({
      text: lines.slice(0, 24).join('\n'),
      omitted: true,
    });
  });
  it('requires demo provenance and the complete known wrapper', () => {
    const text =
      'Source date: 2026-09-01\nPotassium 4.1 mmol/L\nInvented for Reva software demonstration. is a quoted phrase.';
    expect(localExcerpt(text)).toBe(text);
    expect(localExcerpt(text, true)).toBe(text);
    const wrapper =
      'SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD\nSource date: 2026-09-01\nPotassium 4.1 mmol/L\nInvented for Reva software demonstration. Not a real patient record or medical advice.';
    expect(localExcerpt(wrapper)).toBe(wrapper);
    expect(localExcerpt(wrapper, true)).toBe('Potassium 4.1 mmol/L');
  });
  it('excludes unrelated ear note for completed palpitation visit and retains pins', () => {
    const data = seed(),
      visit = data.visits.find((item) => item.id === 'demo-visit-primary-20260908')!;
    expect(selectedRecords(visit, data.records).map((record) => record.id)).not.toContain(
      'demo-record-ear-infection',
    );
    visit.pinnedRecordIDs.push('demo-record-ear-infection');
    expect(selectedRecords(visit, data.records).map((record) => record.id)).toContain(
      'demo-record-ear-infection',
    );
  });
  it('keeps omission metadata outside quote and through saved validation', async () => {
    const data = seed(),
      visit = data.visits[0],
      record = data.records[0];
    record.text = Array.from({ length: 30 }, (_, index) => `retained source line ${index}`).join('\n');
    record.pageTexts = undefined;
    record.isDemo = false;
    visit.pinnedRecordIDs = [record.id];
    visit.report = await generateReport(visit, [record]);
    const source = visit.report.sections.flatMap((section) => section.sources)[0];
    expect(source.excerptOmitted).toBe(true);
    expect(record.text).toContain(source.excerpt);
    expect(source.excerpt).not.toContain(excerptOmissionNotice);
    const decoded = validateSnapshot(JSON.parse(JSON.stringify(data)));
    expect(decoded.visits[0].report?.sections.flatMap((section) => section.sources)[0].excerptOmitted).toBe(
      true,
    );
    expect(await reportIsStale(visit, [record])).toBe(false);
    delete source.excerptOmitted;
    expect(await reportIsStale(visit, [record])).toBe(true);
    expect(() => validateSnapshot(data)).not.toThrow();
  });
});

describe('calendar day and instant display', () => {
  it('uses the requested instant zone without requiring time display', () => {
    expect(formatDate('2026-09-12T01:00:00Z', false, 'America/Chicago')).toBe(formatDate('2026-09-11'));
    expect(formatDate('2026-09-11T23:30:00Z', false, 'Asia/Tokyo')).toBe(formatDate('2026-09-12'));
  });
  it('keeps source calendar days and never invents a time', () => {
    expect(formatDate('2026-09-12', true, 'Pacific/Honolulu')).toBe(formatDate('2026-09-12'));
  });
});
