// Purpose: Keep displayed dates and entered wall times independent of the device time zone.
// Inputs: ISO timestamps, date-only strings, optional IANA zones, and datetime-local values.
// Outputs: Central-time defaults, calendar fields, and validated ISO instants.
// Side effects: None; explicit zones and date-only source values remain unchanged.

// MARK: - Shared time-zone and display conventions
// Chicago follows US Central standard and daylight time as the calendar requires.
export const defaultTimeZone = 'America/Chicago';

export function validZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

export function displayTimeZone(zone?: string): string {
  return zone && validZone(zone) ? zone : defaultTimeZone;
}

export function formatDate(text: string, withTime = false, zone?: string): string {
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(text);
  const value = new Date(dateOnly ? `${text}T00:00:00Z` : text);
  if (!Number.isFinite(value.getTime())) return 'Invalid date';
  const options: Intl.DateTimeFormatOptions = {
    dateStyle: 'medium',
    ...(withTime && !dateOnly ? { timeStyle: 'short' as const } : {}),
    timeZone: dateOnly ? 'UTC' : displayTimeZone(zone),
  };
  return new Intl.DateTimeFormat(undefined, options).format(value);
}

// MARK: - Zoned calendar fields for new dates and occurrence editors
export function dateFieldValue(iso: string, zone = defaultTimeZone): string {
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

export function calendarDay(date = new Date(), zone = defaultTimeZone): string {
  return dateFieldValue(date.toISOString(), zone).slice(0, 10);
}

// MARK: - Resolve wall times without silently accepting nonexistent DST hours
export function dateFieldISO(value: string, zone = defaultTimeZone): string {
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
