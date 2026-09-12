// Purpose: Convert appointment form values without silently changing their chosen time zone.
// Inputs: ISO timestamps, IANA time zones, and datetime-local field values.
// Outputs: Displayable form values or validated ISO instants.
// Side effects: None.

// MARK: - Zoned calendar components
export const visitTimeZones = [
  'America/Chicago',
  'America/New_York',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'UTC',
];

export function dateFieldValue(iso: string, zone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(iso));
  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? '';
  return `${value('year')}-${value('month')}-${value('day')}T${value('hour')}:${value('minute')}`;
}

// MARK: - Resolve the entered wall time and reject nonexistent DST times
export function dateFieldISO(value: string, zone: string): string {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw new Error('Enter a complete date and time.');
  const target = Date.parse(`${value}:00Z`);
  if (!Number.isFinite(target) || new Date(target).toISOString().slice(0, 16) !== value)
    throw new Error('Enter a valid date and time.');
  let instant = target;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const shown = dateFieldValue(new Date(instant).toISOString(), zone);
    const delta = target - Date.parse(`${shown}:00Z`);
    if (delta === 0) return new Date(instant).toISOString();
    instant += delta;
  }
  throw new Error('This time does not exist in the selected time zone. Choose another time.');
}
