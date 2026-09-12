// Purpose: Convert appointment form values without silently changing their chosen time zone.
// Inputs: ISO timestamps, IANA time zones, and datetime-local field values.
// Outputs: Displayable form values or validated ISO instants.
// Side effects: None.

import { defaultTimeZone } from '../../core/dates';
export { dateFieldValue, dateFieldISO } from '../../core/dates';

// MARK: - Zoned calendar components
export const visitTimeZones = [
  defaultTimeZone,
  'America/New_York',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'UTC',
];
