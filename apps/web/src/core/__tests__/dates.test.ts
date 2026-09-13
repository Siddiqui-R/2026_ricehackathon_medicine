// Purpose: Protect Central defaults while preserving explicit zones and date-only sources.
// Inputs: Fixed instants around midnight and US daylight-saving boundaries.
// Outputs: Assertions for displayed days, entered wall times, and precise symptom edits.
// Side effects: None; run in multiple host time zones to detect device-local dependencies.

import { describe, expect, it } from 'vitest';
import {
  calendarDay,
  dateFieldISO,
  dateFieldValue,
  defaultTimeZone,
  displayTimeZone,
  formatDate,
} from '../dates';
import { editedSymptomOccurrence } from '../symptoms';
import { documentDate, recordDateContext, recordDateLabel } from '../recordDates';
import { seed } from './fixtures';

// MARK: - Central defaults follow both standard and daylight time
describe('Central date defaults', () => {
  it('keeps an unknown document date distinct from a known source date and its upload timestamp', () => {
    const uploadedAt = '2026-09-13T02:30:00Z';
    const unknown = { ...seed().records[0], ...documentDate('', uploadedAt), uploadedAt };
    expect(unknown).toMatchObject({ date: '2026-09-12', dateSource: 'added', uploadedAt });
    expect(recordDateLabel(unknown)).toBe(`Added ${formatDate('2026-09-12')}`);
    expect(recordDateContext(unknown)).toBe('Added 2026-09-12; event date unknown');
    const known = { ...unknown, ...documentDate('2025-12-02', uploadedAt) };
    expect(known).toMatchObject({ date: '2025-12-02', dateSource: 'document', uploadedAt });
    expect(recordDateContext(known)).toBe('2025-12-02');
    expect(recordDateContext({ ...known, dateSource: undefined })).toBe('Date 2025-12-02; source unverified');
  });
  it('uses the same named zone for inputs and unspecified display zones', () => {
    expect(defaultTimeZone).toBe('America/Chicago');
    expect(displayTimeZone()).toBe('America/Chicago');
    expect(displayTimeZone('Invalid/Zone')).toBe('America/Chicago');
    expect(displayTimeZone('Asia/Tokyo')).toBe('Asia/Tokyo');
  });

  it.each([
    ['winter', '2026-01-15T09:30', '2026-01-15T15:30:00.000Z'],
    ['summer', '2026-07-15T09:30', '2026-07-15T14:30:00.000Z'],
  ])('interprets an unzoned field in Central %s time', (_season, field, instant) => {
    expect(dateFieldISO(field)).toBe(instant);
    expect(dateFieldValue(instant)).toBe(field);
    expect(formatDate(instant, true)).toBe(formatDate(instant, true, 'America/Chicago'));
    expect(formatDate(instant, true)).not.toBe(formatDate(instant, true, 'UTC'));
  });

  it.each([
    ['2026-01-15T05:30:00Z', '2026-01-14'],
    ['2026-01-15T06:30:00Z', '2026-01-15'],
    ['2026-07-15T04:30:00Z', '2026-07-14'],
    ['2026-07-15T05:30:00Z', '2026-07-15'],
  ])('uses the Central calendar day for %s', (instant, expectedDay) => {
    expect(calendarDay(new Date(instant))).toBe(expectedDay);
    expect(formatDate(instant)).toBe(formatDate(expectedDay));
    expect(formatDate(instant, false, 'Invalid/Zone')).toBe(formatDate(expectedDay));
  });

  it('keeps explicit non-Central zones and date-only sources unchanged', () => {
    const instant = '2026-07-15T04:30:00Z';
    expect(calendarDay(new Date(instant), 'Asia/Tokyo')).toBe('2026-07-15');
    expect(formatDate(instant, false, 'Asia/Tokyo')).toBe(formatDate('2026-07-15'));
    for (const zone of ['America/Chicago', 'Asia/Tokyo', 'Pacific/Honolulu']) {
      expect(formatDate('2026-07-15', true, zone)).toBe(formatDate('2026-07-15'));
    }
  });

  it('rejects a nonexistent Central hour and resolves the repeated hour consistently', () => {
    expect(() => dateFieldISO('2026-03-08T02:30')).toThrow('does not exist');
    expect(dateFieldISO('2026-11-01T01:30')).toBe('2026-11-01T06:30:00.000Z');
  });
});

// MARK: - Editing descriptions must not rewrite source time or the repeated-hour occurrence
describe('symptom occurrence editing', () => {
  it('preserves exact seconds and the second fall-back occurrence when the field is unchanged', () => {
    const initial = {
      observedAt: '2026-11-01T07:30:46.123Z',
      timeZone: 'America/Chicago',
    };
    expect(editedSymptomOccurrence(initial, '2026-11-01T01:30')).toEqual(initial);
  });

  it('interprets an edited time in the existing explicit zone', () => {
    const initial = { observedAt: '2026-07-15T00:30:45Z', timeZone: 'Asia/Tokyo' };
    expect(editedSymptomOccurrence(initial, '2026-07-15T09:30')).toEqual(initial);
    expect(editedSymptomOccurrence(initial, '2026-07-15T10:30')).toEqual({
      observedAt: '2026-07-15T01:30:00.000Z',
      timeZone: 'Asia/Tokyo',
    });
  });

  it('uses Central for new symptom edits and rejects nonexistent wall times', () => {
    const initial = { observedAt: '2026-03-08T07:00:00Z', timeZone: defaultTimeZone };
    expect(editedSymptomOccurrence(initial, '2026-03-08T03:30')).toEqual({
      observedAt: '2026-03-08T08:30:00.000Z',
      timeZone: 'America/Chicago',
    });
    expect(() => editedSymptomOccurrence(initial, '2026-03-08T02:30')).toThrow('does not exist');
  });
});
