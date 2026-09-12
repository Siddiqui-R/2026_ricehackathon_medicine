// Purpose: Mirror native source selection, signatures, faithful excerpts and brief assembly.
// Inputs: Versioned medical records, visit intent and user-authored questions/notes.
// Outputs: Deterministic source selections and asynchronous SHA256-stamped reports.
// Side effects: Generates UUIDs/timestamps and uses browser Web Crypto; no HTTP or persistence.
import type { MedicalRecord, Visit, VisitReport } from './models';
import { sourceLines, sourcePassage, sourceText, passageNotice } from './sourceExcerpt';
export { validateSnapshot, safeFilename } from './validation';
export { makeSymptomRecord, validateSymptomEntry } from './symptoms';
export { createMemoryRecord, reconcileMemory, validateBooking, confirmBooking } from './mutations';

// MARK: - Shared display and identity conventions.
export const uid = (): string => crypto.randomUUID();
export const nowISO = (): string => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
export function validZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}
export function formatDate(text: string, withTime = false, zone?: string): string {
  // Hiding the clock must not move an instant to its UTC calendar day.
  const calendarDay = /^\d{4}-\d{2}-\d{2}$/.test(text);
  const value = new Date(calendarDay ? `${text}T12:00:00Z` : text);
  if (!Number.isFinite(value.getTime())) return 'Invalid date';
  const options: Intl.DateTimeFormatOptions = {
    dateStyle: 'medium',
    ...(withTime ? { timeStyle: 'short' as const } : {}),
  };
  options.timeZone = calendarDay ? 'UTC' : zone && validZone(zone) ? zone : undefined;
  return new Intl.DateTimeFormat(undefined, options).format(value);
}
export function durationLabel(seconds: number): string {
  const value = Number.isFinite(seconds) ? Math.max(0, Math.trunc(seconds)) : 0;
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
}
export function prefixCharacters(text: string, limit: number): string {
  if (typeof Intl.Segmenter === 'function')
    return Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text))
      .slice(0, limit)
      .map((value) => value.segment)
      .join('');
  return Array.from(text).slice(0, limit).join('');
}

// MARK: - Faithful excerpts without fixture wrapper metadata.
function contentLines(text: string): string[] {
  return sourceLines(text).map((line) => line.text);
}
export function localExcerpt(text: string, isDemo = false): string {
  return sourcePassage(sourceText(text, isDemo)).text;
}
export function excerptNotice(text: string, isDemo = false): string | undefined {
  return passageNotice(sourcePassage(sourceText(text, isDemo)));
}
const words = (text: string): Set<string> =>
  new Set(
    text
      .toLowerCase()
      .split(/[^\p{L}]+/u)
      .filter(Boolean),
  );
const intersection = (left: Set<string>, right: Set<string>): number =>
  [...left].filter((value) => right.has(value)).length;

// MARK: - Native-compatible hash input, including the entire candidate pool.
export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}
export async function reportSignature(visit: Visit, records: MedicalRecord[]): Promise<string> {
  const seconds = Date.parse(visit.date) / 1000;
  if (!Number.isFinite(seconds))
    throw new Error('The visit date is invalid. Correct it before preparing a brief.');
  const epoch = Number.isInteger(seconds) ? `${seconds}.0` : String(seconds);
  // Existing briefs must be regenerated after source-preservation/relevance rules change.
  const inputs = [
    'source-rules-v2',
    visit.type,
    visit.concern,
    visit.goal,
    epoch,
    [...visit.pinnedRecordIDs].sort().join(','),
  ];
  for (const record of [...records].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))) {
    inputs.push(
      `${record.id}|${record.version}|${record.title}|${record.date}|${record.text}|${record.summary}|${record.tags.join(',')}|${record.status}`,
    );
  }
  return sha256(inputs.join('\u001e'));
}
export async function reportIsStale(visit: Visit, records: MedicalRecord[]): Promise<boolean> {
  return !!visit.report && visit.report.sourceSignature !== (await reportSignature(visit, records));
}

// MARK: - Match native relevance groups, context inclusion and explicit pins.
const groups = [
  [
    'orthopedic',
    'orthopedics',
    'fracture',
    'broken',
    'fibula',
    'tibia',
    'implant',
    'leg',
    'hardware',
    'nail',
  ],
  ['nausea', 'palpitation', 'palpitations', 'heart', 'cardiology', 'ecg', 'dizziness', 'asthma', 'breathing'],
  ['ear', 'otitis', 'infection'],
  ['lab', 'labs', 'blood', 'thyroid', 'electrolyte'],
];
const stopWords = new Set(
  'want visit review follow followup help need past prior history medical about with this that from have what which would could should count bring report records question questions understand discuss since relevant concern clarify confirm care primary appointment safe safely timing time changes manage when before after including current symptom symptoms entry entries user recent next right left source record details together information recent ongoing routine explain planning plan patient reported documents existing organize unresolved'.split(
    ' ',
  ),
);
export function selectedRecords(visit: Visit, records: MedicalRecord[]): MedicalRecord[] {
  const focus = words(`${visit.type} ${visit.concern} ${visit.goal}`);
  const terms = new Set([...focus].filter((word) => word.length > 3 && !stopWords.has(word)));
  for (const group of groups)
    if (group.some((word) => focus.has(word))) group.forEach((word) => terms.add(word));
  if (terms.has('nausea') || terms.has('palpitations')) groups[3].forEach((word) => terms.add(word));
  return records
    .map((record) => {
      if (visit.pinnedRecordIDs.includes(record.id)) return { record, score: 1000 };
      const index = words(
        `${record.title} ${record.tags.join(' ')} ${record.summary} ${sourceText(record.text, record.isDemo)}`,
      );
      const context = record.tags.some((tag) =>
        ['context', 'medications', 'allergies', 'medical-history', 'medical history'].includes(
          tag.toLowerCase(),
        ),
      );
      const count = intersection(terms, index);
      return { record, score: count || context ? count * 10 + (context ? 50 : 0) : -1 };
    })
    .filter((item) => item.score >= 0)
    .sort(
      (a, b) =>
        b.score - a.score || (a.record.date > b.record.date ? -1 : a.record.date < b.record.date ? 1 : 0),
    )
    .map((item) => item.record);
}

// MARK: - Keep contiguous quotations and real page/version identities.
function relevantExcerpt(text: string, focus: Set<string>) {
  const opening = sourcePassage(text),
    score = (value: string) => intersection(focus, words(value));
  if (score(opening.text) > 0) return opening;
  const lines = contentLines(text);
  let best = -1,
    maximum = 0;
  lines.forEach((line, index) => {
    const value = score(line);
    if (value > maximum) {
      maximum = value;
      best = index;
    }
  });
  return best < 0 ? opening : sourcePassage(text, Math.max(0, best - 2));
}
export async function generateReport(visit: Visit, records: MedicalRecord[]): Promise<VisitReport> {
  const selected = selectedRecords(visit, records);
  const sections: VisitReport['sections'] = [
    { id: uid(), title: 'Your focus', body: `${visit.concern}\n\nGoal: ${visit.goal}`, sources: [] },
  ];
  const focus = new Set([...words(`${visit.concern} ${visit.goal}`)].filter((word) => word.length > 3));
  for (const record of selected) {
    const pages = record.pageTexts ?? [record.text];
    let pageIndex = 0,
      maximum = -1;
    pages.forEach((page, index) => {
      const content = sourceText(page, record.isDemo).toLowerCase();
      let score = intersection(focus, words(content));
      if (focus.has('implant') || focus.has('hardware')) {
        if (content.includes('implant location:')) score += 20;
        if (content.includes('device identification')) score += 5;
      }
      if (score >= maximum) {
        maximum = score;
        pageIndex = index;
      }
    });
    const passage = relevantExcerpt(sourceText(pages[pageIndex] ?? record.text, record.isDemo), focus);
    const excerpt = passage.text;
    sections.push({
      id: uid(),
      title: record.title,
      body:
        (record.status === 'needsReview'
          ? 'Needs review: verify this extraction against the original.\n\n'
          : '') +
        (passageNotice(passage) ? passageNotice(passage) + '\n\n' : '') +
        excerpt,
      sources: [
        {
          recordID: record.id,
          page: record.pageTexts?.length ? pageIndex + 1 : 0,
          excerpt,
          sourceVersion: record.version,
        },
      ],
    });
  }
  sections.push({
    id: uid(),
    title: 'Information to confirm',
    sources: [],
    body: selected.length
      ? 'Confirm current medications, allergies, symptom timing, and any changes since these records were written. This brief contains selected source excerpts; it is not a clinical assessment.'
      : 'No matching records were found. Add records or pin documents you want to discuss. Missing records do not establish that a condition is absent.',
  });
  const suggested = [
    'Which parts of my history matter most for this concern?',
    'What should I track before our next visit?',
    'What are the next steps, and when should I follow up?',
  ];
  return {
    id: uid(),
    visitID: visit.id,
    createdAt: nowISO(),
    sourceSignature: await reportSignature(visit, records),
    sections,
    questions: !visit.questions.length && !visit.report ? suggested : [...visit.questions],
    notes: visit.notes,
    selectedRecordIDs: selected.map((record) => record.id),
    isDemo: true,
  };
}
