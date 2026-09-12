// Purpose: Protect appointment wall times across time zones and daylight-saving transitions.
// Inputs: Fixed calendar values, IANA zones, and invalid or nonexistent local times.
// Outputs: Vitest assertions for exact ISO instants and reversible field display.
// Side effects: None; no clock, network, or browser resources are used.

import { describe, expect, it } from 'vitest';
import { dateFieldISO, dateFieldValue } from './visitDates';

// MARK: - Offset and calendar-day round-trips
const cases = [
  ['Chicago summer', '2026-09-15T09:30', 'America/Chicago', '2026-09-15T14:30:00.000Z'],
  ['Chicago winter', '2026-01-15T09:30', 'America/Chicago', '2026-01-15T15:30:00.000Z'],
  ['New York summer', '2026-09-15T09:30', 'America/New_York', '2026-09-15T13:30:00.000Z'],
  ['London summer', '2026-09-15T09:30', 'Europe/London', '2026-09-15T08:30:00.000Z'],
  ['UTC', '2026-09-15T09:30', 'UTC', '2026-09-15T09:30:00.000Z'],
  ['previous UTC day', '2026-01-01T00:15', 'Asia/Tokyo', '2025-12-31T15:15:00.000Z'],
  ['next UTC day', '2026-12-31T23:45', 'America/Los_Angeles', '2027-01-01T07:45:00.000Z'],
  ['valid leap day', '2028-02-29T12:00', 'UTC', '2028-02-29T12:00:00.000Z'],
] as const;

describe('appointment time-zone fields', () => {
  it.each(cases)('preserves the entered wall time for %s', (_label, entered, zone, expected) => {
    expect(dateFieldISO(entered, zone)).toBe(expected);
    expect(dateFieldValue(expected, zone)).toBe(entered);
  });

  // MARK: - Ambiguous hours resolve consistently; nonexistent hours never move silently
  it('chooses the first occurrence of the repeated Chicago fall-back hour', () => {
    expect(dateFieldISO('2026-11-01T01:30', 'America/Chicago')).toBe('2026-11-01T06:30:00.000Z');
    expect(dateFieldValue('2026-11-01T06:30:00.000Z', 'America/Chicago')).toBe('2026-11-01T01:30');
    expect(dateFieldValue('2026-11-01T07:30:00.000Z', 'America/Chicago')).toBe('2026-11-01T01:30');
  });

  it.each([
    ['Chicago spring gap', '2026-03-08T02:30', 'America/Chicago'],
    ['London spring gap', '2026-03-29T01:30', 'Europe/London'],
  ])('rejects a nonexistent wall time in the %s', (_label, entered, zone) => {
    expect(() => dateFieldISO(entered, zone)).toThrow('does not exist');
  });

  // MARK: - Invalid calendar values are rejected before offset calculation
  it.each([
    '2026-02-30T12:00',
    '2026-02-29T12:00',
    '2026-13-01T12:00',
    '2026-09-15T24:00',
    '2026-09-15',
    'not-a-date',
  ])('rejects %s', (entered) => {
    expect(() => dateFieldISO(entered, 'UTC')).toThrow();
  });

  it('rejects an unknown zone instead of silently using the browser zone', () => {
    expect(() => dateFieldISO('2026-09-15T09:30', 'Invalid/Zone')).toThrow();
  });
});
