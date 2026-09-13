// Purpose: Track report-grounded medical details without overwriting patient-entered information.
// Inputs: Versioned report text, validated AI facts and the latest editable profile.
// Outputs: Bounded source inputs and a profile retaining both provenance and manual corrections.
// Side effects: None; request scheduling and persistence live in profileAutomation.
import type {
  AIProfileFacts,
  AIProfileResult,
  AppSnapshot,
  MedicalProfileField,
  PatientProfile,
} from './models';

// MARK: - Only original readable reports are evidence; recovery copies are never clinical sources.
export const medicalProfileFields: MedicalProfileField[] = [
  'allergies',
  'medications',
  'conditions',
  'surgeriesAndImplants',
  'careNotes',
];
export interface ProfileSource {
  id: string;
  version: number;
  title: string;
  date: string;
  text: string;
}
export const emptyProfileFacts = (): AIProfileFacts => ({
  allergies: [],
  medications: [],
  conditions: [],
  surgeriesAndImplants: [],
  careNotes: [],
});
export function profileSources(snapshot: AppSnapshot): ProfileSource[] {
  return snapshot.records
    .filter((record) => record.kind !== 'Sync recovery' && record.text.trim())
    .map(({ id, version, title, date, text }) => ({ id, version, title, date, text }))
    .sort((a, b) => a.id.localeCompare(b.id));
}
export const profileSourceKey = (snapshot: AppSnapshot): string => JSON.stringify(profileSources(snapshot));
const bytes = (text: string) => new TextEncoder().encode(text).byteLength;
export const profileFactKey = (text: string) => text.trim().replace(/\s+/gu, ' ').toLocaleLowerCase('en-US');
const key = profileFactKey;
export function validateProfileSources(records: ProfileSource[]): void {
  if (
    records.length > 100 ||
    records.some((record) => bytes(record.text) > 100_000) ||
    records.reduce((total, record) => total + bytes(record.text), 0) > 200_000
  )
    throw new Error(
      'Automatic profile updates support up to 100 reports and 200 KB of report text (100 KB per report). Your existing profile is preserved.',
    );
}

// MARK: - Reject unsupported facts and source IDs before any profile change.
export function validateProfileResult(value: unknown, records: ProfileSource[]): AIProfileResult {
  const fail = (): never => {
    throw new Error('The AI medical profile response was invalid. Your existing profile was kept.');
  };
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail();
  const result = value as Record<string, unknown>;
  if (
    Object.keys(result).sort().join() !== [...medicalProfileFields, 'model'].sort().join() ||
    typeof result.model !== 'string' ||
    !result.model.trim() ||
    bytes(result.model) > 200
  )
    return fail();
  const ids = new Set(records.map((record) => record.id));
  for (const field of medicalProfileFields) {
    const facts = result[field];
    if (!Array.isArray(facts) || facts.length > 30) return fail();
    for (const fact of facts) {
      if (
        !fact ||
        typeof fact !== 'object' ||
        Object.keys(fact).sort().join() !== 'recordIDs,text' ||
        typeof fact.text !== 'string' ||
        !fact.text.trim() ||
        bytes(fact.text) > 500 ||
        !Array.isArray(fact.recordIDs) ||
        !fact.recordIDs.length ||
        fact.recordIDs.length > 100 ||
        new Set(fact.recordIDs).size !== fact.recordIDs.length ||
        fact.recordIDs.some((id: unknown) => typeof id !== 'string' || !ids.has(id))
      )
        return fail();
    }
  }
  return result as unknown as AIProfileResult;
}

// MARK: - Replace generated details only; remember removals so AI cannot undo manual corrections.
export function applyMedicalProfile(
  profile: PatientProfile,
  result: AIProfileResult,
  sourceSignature: string,
  generatedAt: string,
): PatientProfile {
  const next = structuredClone(profile);
  const previous = profile.aiMedicalHistory;
  const facts = emptyProfileFacts();
  const suppressed = structuredClone(previous?.suppressed ?? {});
  const suppressedRecordIDs = structuredClone(previous?.suppressedRecordIDs ?? {});
  for (const field of medicalProfileFields) {
    const current =
      field === 'careNotes'
        ? (profile.careNotes ?? '').split('\n').filter((line) => line.trim())
        : (profile[field] ?? []);
    const prior = previous?.facts[field] ?? [];
    const currentKeys = new Set(current.map(key));
    const omitted = new Set([
      ...(suppressed[field] ?? []),
      ...prior.filter((fact) => !currentKeys.has(key(fact.text))).map((fact) => key(fact.text)),
    ]);
    suppressed[field] = [...omitted];
    const removedSources = new Set([
      ...(suppressedRecordIDs[field] ?? []),
      ...prior.filter((fact) => !currentKeys.has(key(fact.text))).flatMap((fact) => fact.recordIDs),
    ]);
    suppressedRecordIDs[field] = [...removedSources];
    const generatedKeys = new Set(prior.map((fact) => key(fact.text)));
    const manual = current.filter((text) => !generatedKeys.has(key(text)));
    const retained = new Set(manual.map(key));
    for (const fact of result[field]) {
      const normalized = key(fact.text);
      // A corrected source must not reintroduce the same finding with different AI wording.
      if (
        omitted.has(normalized) ||
        retained.has(normalized) ||
        fact.recordIDs.some((id) => removedSources.has(id))
      )
        continue;
      retained.add(normalized);
      facts[field].push({ text: fact.text.trim().replace(/\s+/gu, ' '), recordIDs: [...fact.recordIDs] });
    }
    const values = [...manual, ...facts[field].map((fact) => fact.text)];
    if (field === 'careNotes') next.careNotes = values.join('\n') || null;
    else next[field] = values;
  }
  next.aiMedicalHistory = {
    sourceSignature,
    generatedAt,
    model: result.model,
    facts,
    suppressed,
    suppressedRecordIDs,
  };
  return next;
}
