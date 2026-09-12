// Purpose: Mirror native source selection, signatures, faithful excerpts and brief assembly.
// Inputs: Versioned medical records, visit intent and user-authored questions/notes.
// Outputs: Deterministic source selections and asynchronous SHA256-stamped reports.
// Side effects: Generates UUIDs/timestamps and uses browser Web Crypto; no HTTP or persistence.
import type { MedicalRecord, Visit, VisitReport } from './models';
export { validateSnapshot, safeFilename } from './validation';
export { makeSymptomRecord, validateSymptomEntry } from './symptoms';
export { createMemoryRecord, reconcileMemory, validateBooking, confirmBooking } from './mutations';
export { defaultTimeZone, displayTimeZone, formatDate, validZone } from './dates';

// MARK: - Shared display and identity conventions.
export const uid = (): string => crypto.randomUUID();
export const nowISO = (): string => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
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
export interface SourceExcerpt {
  text: string;
  omitted: boolean;
}
export const excerptOmissionNotice =
  'Selected passage; additional source text omitted. Open the original for full context.';
function sourceLines(text: string): { text: string; start: number; end: number }[] {
  return [...text.matchAll(/[^\r\n\v\f\u0085\u2028\u2029]+/gu)]
    .filter((match) => match[0].trim())
    .map((match) => ({ text: match[0], start: match.index, end: match.index + match[0].length }));
}
function sourceContent(text: string, isDemo: boolean): string {
  const lines = sourceLines(text);
  if (!isDemo || lines[0]?.text !== 'SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD') return text;
  let metadata = -1,
    trailer = -1;
  lines.slice(0, 10).forEach((line, index) => {
    if (line.text.startsWith('Source date:') || line.text.startsWith('Week ending:')) metadata = index;
  });
  lines.forEach((line, index) => {
    if (
      line.text === 'Invented for Reva software demonstration. Not a real patient record or medical advice.'
    )
      trailer = index;
  });
  const knownFooter = lines
    .slice(trailer + 1)
    .every(
      (line) =>
        /^Synthetic source ID: demo-record-[a-z0-9-]+$/.test(line.text) ||
        /^Page \d+ of \d+$/.test(line.text) ||
        line.text === 'SYNTHETIC SCAN | 1 page | no real patient data',
    );
  return metadata >= 0 && metadata + 1 < trailer && knownFooter
    ? text.slice(lines[metadata + 1].start, lines[trailer - 1].end)
    : text;
}
function boundedExcerpt(text: string, start = 0): SourceExcerpt {
  const lines = sourceLines(text);
  if (!lines[start]) return { text: '', omitted: false };
  const lower = lines[start].start;
  let upper = lower,
    count = 0;
  for (const line of lines.slice(start, start + 24)) {
    const candidate = text.slice(lower, line.end);
    if (prefixCharacters(candidate, 1800) !== candidate) break;
    upper = line.end;
    count += 1;
  }
  return { text: text.slice(lower, upper), omitted: start > 0 || start + count < lines.length };
}
export function localExcerptDetails(text: string, isDemo = false): SourceExcerpt {
  return boundedExcerpt(sourceContent(text, isDemo));
}
export function localExcerpt(text: string, isDemo = false): string {
  return localExcerptDetails(text, isDemo).text;
}
// Share the display/preparation policy without rewriting persisted source or provider summaries.
export function currentSummary(record: MedicalRecord): string {
  return record.summaryModel != null || hasAuthoredDemoSummary(record)
    ? record.summary
    : localExcerpt(record.text, record.isDemo);
}
// Recognize old generated summaries only for provenance; their unsafe cuts are never displayed.
export function hasAuthoredDemoSummary(record: MedicalRecord): boolean {
  if (!record.isDemo || record.summary === localExcerpt(record.text, true)) return false;
  const lines = record.text
    .split(/\r\n|[\n\r\v\f\u0085\u2028\u2029]/u)
    .map((line) => line.trim())
    .filter(Boolean);
  let start = 0,
    end = lines.length;
  lines.slice(0, 10).forEach((line, index) => {
    if (line.startsWith('Source date:') || line.startsWith('Week ending:')) start = index + 1;
  });
  lines.forEach((line, index) => {
    if (line.startsWith('Invented for Reva software demonstration.')) end = index;
  });
  const legacy = prefixCharacters(
    (start < end ? lines.slice(start, end) : lines).slice(0, 24).join('\n'),
    1800,
  );
  return record.summary !== legacy;
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
  // The rule revision invalidates old selections independently of citation omission metadata.
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
  return (
    !!visit.report &&
    (visit.report.sections.some((section) =>
      section.sources.some((source) => source.excerptOmitted == null),
    ) ||
      visit.report.sourceSignature !== (await reportSignature(visit, records)))
  );
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
  'want visit review follow followup help need past prior history medical about with this that from have what which would could should count bring report records question questions understand discuss since relevant concern clarify confirm care primary appointment safe safely timing time changes manage when before after including current symptom symptoms entry entries user recent next right left source record details together information recent ongoing routine explain planning plan patient reported document documents existing organize unresolved brief'.split(
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
        `${record.title} ${record.tags.join(' ')} ${record.summary} ${(record.pageTexts?.length ? record.pageTexts : [record.text]).map((page) => sourceContent(page, record.isDemo)).join(' ')}`,
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
function relevantExcerpt(text: string, focus: Set<string>, isDemo: boolean): SourceExcerpt {
  const content = sourceContent(text, isDemo),
    opening = boundedExcerpt(content),
    score = (value: string) => intersection(focus, words(value));
  if (score(opening.text) > 0) return opening;
  const lines = sourceLines(content);
  let best = -1,
    maximum = 0;
  lines.forEach((line, index) => {
    const value = score(line.text);
    if (value > maximum) {
      maximum = value;
      best = index;
    }
  });
  return best < 0 ? opening : boundedExcerpt(content, Math.max(0, best - 2));
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
      const content = sourceContent(page, record.isDemo).toLowerCase();
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
    const excerpt = relevantExcerpt(pages[pageIndex] ?? record.text, focus, record.isDemo);
    sections.push({
      id: uid(),
      title: record.title,
      body: excerpt.text,
      sources: [
        {
          recordID: record.id,
          page: record.pageTexts?.length ? pageIndex + 1 : 0,
          excerpt: excerpt.text,
          excerptOmitted: excerpt.omitted,
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
