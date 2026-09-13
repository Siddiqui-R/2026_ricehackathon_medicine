// Purpose: Resolve profile fact citations without deriving provenance from matching medical keywords.
// Inputs: A profile field and exact fact text, known records, and persisted AI source IDs.
// Outputs: Existing source destinations, plus conservative citations for unchanged authored demo facts.
// Side effects: None; never mutates profile history or labels a manual entry as AI-generated.

import type { MedicalProfileField, MedicalRecord, PatientProfile } from '../../core/models';
import { demoLabel } from '../../core/presentation';
import type { SourceTarget } from '../../components/SourceLink';

// MARK: - The sample's facts were authored from these specific documents
const demoFacts: Record<string, Partial<Record<MedicalProfileField, Record<string, string[]>>>> = {
  'demo-profile-jordan-avery': {
    allergies: {
      'Penicillin - childhood rash reported (synthetic)': ['demo-record-history'],
    },
    medications: {
      'Albuterol inhaler, 90 mcg/actuation - existing as-needed use documented (synthetic)': [
        'demo-record-history',
        'demo-record-asthma',
      ],
      'Cetirizine, 10 mg - seasonal use reported (synthetic)': ['demo-record-history', 'demo-record-asthma'],
    },
    conditions: {
      'Intermittent asthma (synthetic)': ['demo-record-history', 'demo-record-asthma'],
      'Right distal fibula fracture, August 2026 (synthetic)': [
        'demo-record-fibula-injury',
        'demo-record-history',
      ],
      'Prior right tibial fixation with retained hardware, 2019 (synthetic)': [
        'demo-record-tibia-procedure',
        'demo-record-leg-imaging',
      ],
    },
  },
  'demo-profile-maya': {
    conditions: { 'Recurring headaches': ['demo-maya-record-3'] },
  },
  'demo-profile-alex': {
    conditions: { 'Left knee recovery after ACL reconstruction': ['demo-alex-record-1'] },
    surgeriesAndImplants: { 'Left ACL reconstruction, July 2026': ['demo-alex-record-1'] },
  },
};

export function profileSources(
  profile: PatientProfile,
  records: readonly MedicalRecord[],
  field: MedicalProfileField,
  text: string,
): SourceTarget[] {
  const fact = profile.aiMedicalHistory?.facts[field].find((item) => item.text === text);
  // An existing AI result owns its citations, including a result with no available sources.
  const ids = fact?.recordIDs ?? (profile.isDemo ? (demoFacts[profile.id]?.[field]?.[text] ?? []) : []);
  return [...new Set(ids)].flatMap((id) => {
    const record = records.find((candidate) => candidate.id === id);
    if (!record || (!fact && (!record.isDemo || record.version !== 1))) return [];
    return [
      { href: `#/records/${encodeURIComponent(record.id)}`, label: demoLabel(record.title, record.isDemo) },
    ];
  });
}
