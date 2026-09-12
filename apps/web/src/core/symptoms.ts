// Purpose: Project structured self-reported observations into faithful medical records.
// Inputs: Symptom fields and an optional existing symptom record.
// Outputs: Validated fields and a source record retaining identity and creation time.
// Side effects: Generates an ID/time for new records only; version increments belong to saveRecord.
import type { MedicalRecord, SymptomEntry } from './models';
import { nowISO, uid, validZone } from './domain';

// MARK: - Strict observation validation and calendar-day checks.
export function validateSymptomEntry(input: SymptomEntry, now = new Date()): SymptomEntry {
  const entry = {
    ...input,
    symptom: input.symptom.trim(),
    observedAt: input.observedAt.trim(),
    timeZone: input.timeZone.trim(),
    duration: input.duration.trim(),
    details: input.details.trim(),
    triggers: input.triggers.trim(),
    whatHelped: input.whatHelped.trim(),
    severity: input.severity?.trim().toLowerCase() || undefined,
  };
  if (!entry.symptom || Array.from(entry.symptom).length > 120 || /[\r\n\u2028\u2029]/u.test(entry.symptom))
    throw new Error('Enter a symptom under 120 characters on one line.');
  const instant =
    /^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/;
  const day = entry.observedAt.slice(0, 10),
    parsedDay = new Date(`${day}T00:00:00Z`);
  if (
    !instant.test(entry.observedAt) ||
    !Number.isFinite(Date.parse(entry.observedAt)) ||
    !Number.isFinite(parsedDay.getTime()) ||
    parsedDay.toISOString().slice(0, 10) !== day ||
    !validZone(entry.timeZone)
  )
    throw new Error('Choose a valid occurrence date, time, and time zone.');
  if (Date.parse(entry.observedAt) > now.getTime() + 300_000)
    throw new Error('Choose when the symptom occurred, rather than a future time.');
  if (entry.severity && !['mild', 'moderate', 'severe'].includes(entry.severity))
    throw new Error('Choose Mild, Moderate, Severe, or Not specified.');
  if (
    entry.details.length > 12_000 ||
    [entry.duration, entry.triggers, entry.whatHelped].some((value) => value.length > 2000)
  )
    throw new Error('Keep Details under 12000 characters and each extra detail under 2000.');
  return entry;
}

// MARK: - Canonical source wording and native-compatible record projection.
export function makeSymptomRecord(input: SymptomEntry, existing?: MedicalRecord): MedicalRecord {
  const entry = validateSymptomEntry(input);
  if (existing && !existing.symptomEntry)
    throw new Error('This source is not a symptom entry. Create a new entry to keep the original intact.');
  const severity = entry.severity ? entry.severity[0].toUpperCase() + entry.severity.slice(1) : undefined;
  const lines = [
    'User symptom entry',
    'Self-reported by the user.',
    `Symptom: ${entry.symptom}`,
    `Occurred at: ${entry.observedAt} (${entry.timeZone})`,
  ];
  if (severity) lines.push(`Severity: ${severity}`);
  if (entry.duration) lines.push(`Duration: ${entry.duration}`);
  if (entry.details) lines.push('Details:', entry.details);
  if (entry.triggers) lines.push('Possible triggers:', entry.triggers);
  if (entry.whatHelped) lines.push('What helped:', entry.whatHelped);
  const summary = [
    `Symptom: ${entry.symptom}`,
    ...(severity ? [`Severity: ${severity}`] : []),
    ...(entry.duration ? [`Duration: ${entry.duration}`] : []),
  ].join('\n');
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: entry.timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(entry.observedAt));
  const part = (type: string) => parts.find((item) => item.type === type)!.value;
  return {
    ...(existing ?? { id: uid(), uploadedAt: nowISO(), notes: '', version: 1 }),
    title: entry.symptom,
    kind: 'User symptom entry',
    provider: 'Self-reported',
    date: `${part('year')}-${part('month')}-${part('day')}`,
    tags: [...new Set([...(existing?.tags ?? []), 'symptoms', 'self-reported'])].sort(),
    text: lines.join('\n'),
    summary,
    summaryModel: undefined,
    symptomEntry: entry,
    status: 'ready',
    isDemo: false,
    pageTexts: undefined,
    pageCount: 1,
  };
}
