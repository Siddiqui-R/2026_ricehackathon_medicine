// Purpose: Build bounded, source-bound pre-visit briefs without persisting appointments.
// Inputs: Patient-entered visit details, the current medical context, and a structured provider result.
// Outputs: Validated transient brief content and a signature for detecting changed source context.
// Side effects: Generates request IDs and timestamps; does not persist data or call providers.

// MARK: - Transient brief contracts and source preparation
// A brief is a transient, source-bound API result. It never creates an appointment.
import type { AIPreparation, AppSnapshot, MedicalRecord, PatientProfile, Visit } from './models';
import { nowISO, uid } from './domain';
import { defaultTimeZone } from './dates';

export const BRIEF_MODEL = 'gemini-flash-lite-latest';
export interface VisitBriefInput {
  type: string;
  concern: string;
  questions: string[];
}
export interface ClinicalBrief {
  patient: Pick<PatientProfile, 'name' | 'dateOfBirth' | 'isDemo'>;
  visitType: string;
  createdAt: string;
  overview: string;
  questions: string[];
  sources: { id: string; title: string; date: string }[];
  model: string;
  sourceSignature: string;
  example?: boolean;
  overviewSourceIDs?: string[];
}
export function briefContextSignature(snapshot: AppSnapshot): string {
  return JSON.stringify([snapshot.profile, snapshot.records]);
}
export function briefVisit(input: VisitBriefInput): Visit {
  if (!input.type.trim() || input.type.length > 80)
    throw new Error('Enter a visit type (up to 80 characters).');
  if (
    input.concern.length > 2000 ||
    input.questions.length > 3 ||
    input.questions.some((q) => q.length > 300)
  )
    throw new Error('Keep the concern under 2,000 characters and add up to three short questions.');
  return {
    id: uid(),
    title: input.type.trim(),
    type: input.type.trim(),
    concern: input.concern.trim(),
    goal: 'Prepare me for this upcoming appointment using my relevant history and questions.',
    questions: input.questions,
    provider: '',
    clinic: '',
    date: nowISO(),
    timeZone: defaultTimeZone,
    pinnedRecordIDs: [],
    notes: '',
    status: 'upcoming',
  };
}
// The profile is context, never presented as an original clinician's record.
export function briefSources(snapshot: AppSnapshot): MedicalRecord[] {
  const profile = snapshot.profile;
  const context: MedicalRecord = {
    id: uid(),
    title: 'Medical profile',
    kind: 'Profile',
    provider: '',
    date: nowISO(),
    uploadedAt: nowISO(),
    tags: [],
    summary: '',
    pageCount: 0,
    status: 'ready',
    notes: '',
    isDemo: profile.isDemo,
    version: 1,
    text: JSON.stringify({
      source:
        'Current medical profile containing patient-entered details and report-derived AI facts, dated when supplied for this request. Review report-derived facts against their linked original records. Empty lists mean not documented, not confirmed absent.',
      allergies: profile.allergies,
      medications: profile.medications,
      conditions: profile.conditions,
      surgeriesAndImplants: profile.surgeriesAndImplants ?? [],
      careNotes: profile.careNotes ?? '',
    }),
  };
  // Original text is authoritative; an old AI summary cannot replace it.
  const records = snapshot.records
    .filter((record) => record.text.trim())
    .map((record) => ({ ...record, summary: '' }));
  if (records.length > 99)
    throw new Error('This workspace has too many sources for one brief request (maximum 99 records).');
  return [...records, context];
}
export function validateBriefText(result: Pick<AIPreparation, 'overview' | 'questions'>): void {
  if (
    !result.overview.trim() ||
    result.overview.length > 2400 ||
    result.overview.trim().split(/\s+/u).length > 180 ||
    result.overview.split('\n').length > 12 ||
    result.questions.length > 3 ||
    result.questions.some((q) => !q.trim() || q.length > 140)
  )
    throw new Error('The response was too long for a one-page brief. Generate it again.');
}
export function clinicalBrief(
  snapshot: AppSnapshot,
  visit: Visit,
  sources: MedicalRecord[],
  result: AIPreparation,
): ClinicalBrief {
  validateBriefText(result);
  if (
    typeof result.model !== 'string' ||
    !result.model.trim() ||
    result.model.length > 100 ||
    result.model.includes('\0')
  )
    throw new Error(
      'The brief is missing valid provider model information. Update the server and try again.',
    );
  if (
    result.selectedRecordIDs.length > 6 ||
    new Set(result.selectedRecordIDs).size !== result.selectedRecordIDs.length ||
    result.selectedRecordIDs.some((id) => !sources.some((source) => source.id === id))
  )
    throw new Error('The response contains invalid sources. Generate it again.');
  return {
    patient: {
      name: snapshot.profile.name,
      dateOfBirth: snapshot.profile.dateOfBirth,
      isDemo: snapshot.profile.isDemo,
    },
    visitType: visit.type,
    createdAt: nowISO(),
    overview: result.overview,
    questions: result.questions,
    sources: result.selectedRecordIDs.map((id) => {
      const source = sources.find((record) => record.id === id)!;
      return { id, title: source.title, date: source.date };
    }),
    model: result.model,
    sourceSignature: briefContextSignature(snapshot),
  };
}
