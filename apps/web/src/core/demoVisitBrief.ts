// Authored examples use only unchanged source records from the selected fictional demo person.
// No provider calls, saved appointments, inferred diagnoses, or cross-person fallback data.
import seed from '../../public/demo/seed.json';
import { demoPeople, demoSnapshot, type DemoPersonID } from './demoProfiles';
import type { AppSnapshot, Visit } from './models';
import { briefVisit, clinicalBrief, type ClinicalBrief, type VisitBriefInput } from './visitBrief';

type ExampleItem = { id: string; text: string };
const examples: Record<string, ExampleItem[]> = {
  jordan: [
    {
      id: 'demo-record-symptom-diary',
      text: 'Symptoms: The diary describes two brief racing-heart episodes, with nausea during the morning episode. That episode lasted about two minutes. The individual entry date is partly obscured; the week-ending date is September 7, 2026.',
    },
    {
      id: 'demo-record-ecg',
      text: 'ECG: The September 7 note documents sinus rhythm at 82 beats/minute. A typical episode did not occur during the examination. The note does not establish the cause of intermittent symptoms.',
    },
    {
      id: 'demo-record-labs',
      text: 'Laboratory results: September 7 potassium was 4.1 mmol/L and TSH was 1.62 mIU/L. Laboratory-specific reference intervals and prior results are not supplied.',
    },
    {
      id: 'demo-record-asthma',
      text: 'Medication context: The May note documents existing as-needed albuterol and seasonal cetirizine use. It does not attribute symptoms to either medicine.',
    },
  ],
  'jordan-orthopedics': [
    {
      id: 'demo-record-fibula-injury',
      text: 'Current injury: The August 22, 2026 encounter documents a right distal fibula fracture, a walking boot, and planned orthopedic follow-up.',
    },
    {
      id: 'demo-record-leg-imaging',
      text: 'Interval imaging: The August 29 report describes unchanged fibula fracture alignment compared with August 22. The right tibial nail and locking screws are described as intact. No radiographic images are attached.',
    },
    {
      id: 'demo-record-tibia-procedure',
      text: 'Surgical history: Right tibial fixation with an intramedullary nail and locking screws was documented on April 18, 2019. This is separate from the 2026 fibula injury. The implant inventory does not provide device identification or establish imaging compatibility.',
    },
  ],
  maya: [
    {
      id: 'demo-maya-record-1',
      text: 'Headache pattern: The September 9 notes describe headaches on three afternoons that week, lasting one to three hours. Bright office lighting was bothersome; resting in a quiet room helped.',
    },
    {
      id: 'demo-maya-record-2',
      text: 'Daily routine: Sleep varied between six and eight hours. Two headache days followed late nights. No consistent food-related pattern was identified.',
    },
    {
      id: 'demo-maya-record-3',
      text: 'Previous visit: Primary care requested a record of headache timing, duration, and associated symptoms for the next appointment.',
    },
  ],
  alex: [
    {
      id: 'demo-alex-record-1',
      text: 'Surgical history: Left ACL reconstruction was completed in July 2026. The planned orthopedic visit will review recovery and return to usual activities.',
    },
    {
      id: 'demo-alex-record-2',
      text: 'Physical therapy: Sessions have focused on mobility and strength. Stairs are becoming easier, according to the patient, with stiffness after prolonged sitting.',
    },
    {
      id: 'demo-alex-record-3',
      text: 'Current concerns: Morning stiffness and stiffness after sitting are reported. The patient wants to discuss walking distance and the recovery timeline.',
    },
  ],
};

function demoContext(snapshot: AppSnapshot): { id: DemoPersonID; original: AppSnapshot } | undefined {
  if (!snapshot.profile.isDemo) return;
  for (const { id } of demoPeople) {
    const original = demoSnapshot(seed, id);
    if (original.profile.id === snapshot.profile.id) return { id, original };
  }
}
export function demoBriefDefaults(snapshot: AppSnapshot): VisitBriefInput | undefined {
  const context = demoContext(snapshot);
  if (!context) return;
  const visit = context.original.visits.find((item) => item.status === 'upcoming')!;
  return { type: visit.type, concern: visit.concern, questions: [...visit.questions] };
}
export function demoClinicalBrief(snapshot: AppSnapshot, input: VisitBriefInput): ClinicalBrief {
  const context = demoContext(snapshot);
  if (!context) throw new Error('No prepared brief is available for this workspace.');
  const visit: Visit = briefVisit(input);
  const key =
    context.id === 'jordan' && /ortho|fibula|tibia/i.test(visit.type + ' ' + visit.concern)
      ? 'jordan-orthopedics'
      : context.id;
  const included = examples[key].flatMap((item) => {
    const original = context.original.records.find((record) => record.id === item.id)!;
    const current = snapshot.records.find((record) => record.id === item.id);
    // A fixture may not describe an edited, removed, or newly imported medical source.
    if (!current?.isDemo || current.text !== original.text || current.date !== original.date) return [];
    return [{ item, current }];
  });
  if (!included.length)
    throw new Error(
      'The source records have changed or been removed. Restore the original records to use this prepared brief.',
    );
  const brief = clinicalBrief(
    snapshot,
    visit,
    included.map(({ current }) => current),
    {
      overview: included.map(({ item }) => item.text).join('\n\n'),
      questions: visit.questions,
      selectedRecordIDs: included.map(({ current }) => current.id),
      model: 'Prepared from saved records',
    },
  );
  return { ...brief, example: true, overviewSourceIDs: included.map(({ current }) => current.id) };
}
