import { describe, expect, it } from 'vitest';
import { demoDescription, demoLabel, demoSourceText } from '../presentation';
import { seed, sample } from './fixtures';

const markers = /\b(demo|demonstration|synthetic|fictional|invented|fake)\b/i;

describe('workspace presentation', () => {
  it('removes fixture labels without losing facts, units, or uncertainty', () => {
    for (const record of seed().records) {
      expect(demoLabel(record.provider, true)).not.toMatch(markers);
      expect(demoDescription(record.summary, true)).not.toMatch(markers);
      expect(demoDescription(record.notes, true)).not.toMatch(markers);
      expect(demoSourceText(record.text, true)).not.toMatch(markers);
    }
    const labs = seed().records.find((record) => record.id === 'demo-record-labs')!;
    expect(demoDescription(labs.summary, true)).toContain('potassium 4.1 mmol/L');
    expect(demoDescription(labs.summary, true)).toContain('do not establish the cause of symptoms');
    const diary = seed().records.find((record) => record.id === 'demo-record-symptom-diary')!;
    expect(demoSourceText(diary.text, true)).toContain('September 0[unclear], 2026');
    expect(demoSourceText(diary.text, true)).toContain('Do not infer its last digit.');
  });

  it('cleans previous transcript labels and keeps dialogue, timing, and identifiers intact', () => {
    const recording = sample();
    const before = structuredClone(recording);
    expect(demoLabel(recording.title, true)).toBe('Visit transcript · no audio');
    expect(demoDescription(recording.summary, true)).not.toMatch(markers);
    const dialogue = recording.segments.map((segment) => demoSourceText(segment.text, true)).filter(Boolean);
    expect(dialogue).toHaveLength(7);
    expect(dialogue.join(' ')).not.toMatch(markers);
    expect(dialogue.join(' ')).toContain('We have not documented a diagnosis or a medication change');
    expect(recording).toEqual(before);
  });

  it('never rewrites real account text or clinical uses of sample and synthetic', () => {
    const text = 'Demo summary: fictional history; synthetic implant; blood sample.';
    expect(demoLabel(text)).toBe(text);
    expect(demoDescription(text)).toBe(text);
    expect(demoSourceText(text)).toBe(text);
    expect(demoSourceText('Blood sample collected. Synthetic implant material.', true)).toBe(
      'Blood sample collected. Synthetic implant material.',
    );
  });
});
