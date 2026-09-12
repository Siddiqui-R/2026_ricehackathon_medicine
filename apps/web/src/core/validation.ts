// Purpose: Reject malformed persisted or remote snapshots before publication.
// Inputs: Unknown JSON from IndexedDB, bundled fixtures or the Swift server.
// Outputs: A validated native-compatible AppSnapshot, or an actionable error.
// Side effects: None; invalid data is never silently replaced with demo state.
import type { AppSnapshot } from './models';

// MARK: - Primitive and optional shape guards.
type Shape = Record<string, unknown>;
function fail(path: string): never {
  throw new Error(
    `Saved data is invalid at ${path}. Your existing data was kept; restore a valid backup or explicitly reset the demo.`,
  );
}
function object(value: unknown, path: string): Shape {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(path);
  return value as Shape;
}
function text(value: unknown, path: string): asserts value is string {
  if (typeof value !== 'string') fail(path);
}
function bool(value: unknown, path: string): void {
  if (typeof value !== 'boolean') fail(path);
}
function number(value: unknown, path: string, integer = false, minimum = 0): void {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < minimum ||
    (integer && !Number.isSafeInteger(value))
  )
    fail(path);
}
function array(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value) || value.length > 5000) fail(path);
  return value;
}
function strings(value: unknown, path: string): void {
  array(value, path).forEach((item, index) => text(item, `${path}[${index}]`));
}
function fields(value: Shape, names: string[], path: string): void {
  names.forEach((name) => text(value[name], `${path}.${name}`));
}
function optional(
  value: Shape,
  name: string,
  path: string,
  check: (value: unknown, path: string) => void = text,
): void {
  if (value[name] !== undefined && value[name] !== null) check(value[name], `${path}.${name}`);
}
export function safeFilename(name: string): boolean {
  return !!name && name !== '.' && name !== '..' && Array.from(name).length <= 240 && !/[\/\\\0]/u.test(name);
}

// MARK: - Nested native record/report/recording shapes.
function symptom(value: unknown, path: string): void {
  const entry = object(value, path);
  fields(entry, ['observedAt', 'timeZone', 'symptom', 'duration', 'details', 'triggers', 'whatHelped'], path);
  optional(entry, 'severity', path);
}
function report(value: unknown, path: string): void {
  const entry = object(value, path);
  fields(entry, ['id', 'visitID', 'createdAt', 'sourceSignature', 'notes'], path);
  strings(entry.questions, `${path}.questions`);
  strings(entry.selectedRecordIDs, `${path}.selectedRecordIDs`);
  bool(entry.isDemo, `${path}.isDemo`);
  optional(entry, 'generationModel', path);
  array(entry.sections, `${path}.sections`).forEach((raw, index) => {
    const section = object(raw, `${path}.sections[${index}]`);
    fields(section, ['id', 'title', 'body'], path);
    array(section.sources, `${path}.sources`).forEach((rawSource) => {
      const source = object(rawSource, `${path}.source`);
      fields(source, ['recordID', 'excerpt'], path);
      number(source.page, `${path}.page`, true);
      optional(source, 'sourceVersion', path, (v, p) => number(v, p, true, 1));
      optional(source, 'excerptOmitted', path, bool);
    });
  });
}
function unique(entries: Shape[], path: string): void {
  const ids = entries.map((entry) => entry.id);
  if (ids.some((id) => typeof id !== 'string' || !id) || new Set(ids).size !== ids.length) fail(`${path}.id`);
}

// MARK: - Full aggregate and cross-domain relationship validation.
export function validateSnapshot(value: unknown): AppSnapshot {
  const data = object(value, 'snapshot');
  if (data.schemaVersion !== 1) fail('schemaVersion');
  const profile = object(data.profile, 'profile');
  fields(profile, ['id', 'name', 'dateOfBirth', 'initials'], 'profile');
  if (!profile.id || !profile.name) fail('profile.name');
  ['allergies', 'medications', 'conditions'].forEach((key) => strings(profile[key], `profile.${key}`));
  bool(profile.isDemo, 'profile.isDemo');
  optional(profile, 'surgeriesAndImplants', 'profile', strings);
  optional(profile, 'careNotes', 'profile');
  const records = array(data.records, 'records').map((raw, index) => {
    const path = `records[${index}]`,
      record = object(raw, path);
    fields(
      record,
      ['id', 'title', 'kind', 'provider', 'date', 'uploadedAt', 'text', 'summary', 'status', 'notes'],
      path,
    );
    strings(record.tags, `${path}.tags`);
    bool(record.isDemo, `${path}.isDemo`);
    number(record.version, `${path}.version`, true, 1);
    number(record.pageCount, `${path}.pageCount`, true, 1);
    ['sourceFilename', 'mimeType', 'sourceRecordingID', 'summaryModel'].forEach((key) =>
      optional(record, key, path),
    );
    optional(record, 'pageTexts', path, strings);
    optional(record, 'symptomEntry', path, symptom);
    if (typeof record.sourceFilename === 'string' && !safeFilename(record.sourceFilename))
      fail(`${path}.sourceFilename`);
    return record;
  });
  unique(records, 'records');
  const visits = array(data.visits, 'visits').map((raw, index) => {
    const path = `visits[${index}]`,
      visit = object(raw, path);
    fields(
      visit,
      ['id', 'title', 'type', 'provider', 'clinic', 'date', 'timeZone', 'concern', 'goal', 'notes', 'status'],
      path,
    );
    strings(visit.questions, `${path}.questions`);
    strings(visit.pinnedRecordIDs, `${path}.pinnedRecordIDs`);
    optional(visit, 'report', path, report);
    return visit;
  });
  unique(visits, 'visits');
  const visitIDs = new Set(visits.map((visit) => visit.id));
  const bookings = array(data.bookings, 'bookings').map((raw, index) => {
    const path = `bookings[${index}]`,
      booking = object(raw, path);
    fields(
      booking,
      [
        'id',
        'visitID',
        'clinic',
        'phone',
        'reason',
        'earliest',
        'latest',
        'timeZone',
        'preferences',
        'status',
        'scenario',
        'createdAt',
      ],
      path,
    );
    ['confirmedVisitID', 'providerConversationID', 'providerTranscript'].forEach((key) =>
      optional(booking, key, path),
    );
    optional(booking, 'isLive', path, bool);
    if (!visitIDs.has(booking.visitID)) fail(`${path}.visitID`);
    return booking;
  });
  unique(bookings, 'bookings');
  const recordings = array(data.recordings, 'recordings').map((raw, index) => {
    const path = `recordings[${index}]`,
      recording = object(raw, path);
    fields(recording, ['id', 'visitID', 'title', 'createdAt', 'summary', 'status'], path);
    bool(recording.isSample, `${path}.isSample`);
    number(recording.duration, `${path}.duration`);
    optional(recording, 'audioFilename', path);
    optional(recording, 'transcriptionModel', path);
    if (typeof recording.audioFilename === 'string' && !safeFilename(recording.audioFilename))
      fail(`${path}.audioFilename`);
    const segments = array(recording.segments, `${path}.segments`).map((rawSegment) => {
      const segment = object(rawSegment, `${path}.segment`);
      fields(segment, ['id', 'speaker', 'text'], path);
      number(segment.start, `${path}.start`);
      number(segment.end, `${path}.end`);
      if ((segment.end as number) < (segment.start as number)) fail(`${path}.end`);
      return segment;
    });
    unique(segments, `${path}.segments`);
    if (!visitIDs.has(recording.visitID)) fail(`${path}.visitID`);
    return recording;
  });
  unique(recordings, 'recordings');
  return value as AppSnapshot;
}
