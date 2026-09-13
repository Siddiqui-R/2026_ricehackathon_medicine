// Purpose: Merge patient-authored profile edits separately from replaceable AI-generated history.
// Inputs: Shared, local and remote profiles plus the general three-way field merger.
// Outputs: One coherent generated evidence bundle and merged manual details and corrections.
// Side effects: None; changed report context is refreshed later by the profile observer.
import type { AIMedicalHistory, PatientProfile } from './models';
import {
  applyMedicalProfile,
  emptyProfileFacts,
  medicalProfileFields,
  profileFactKey,
} from './medicalProfileAI';

// MARK: - Detach generated entries before a string-list merge can mistake them for manual history.
function manualProfile(profile: PatientProfile): PatientProfile {
  const manual = structuredClone(profile);
  for (const field of medicalProfileFields) {
    const generated = new Set(
      profile.aiMedicalHistory?.facts[field].map((fact) => profileFactKey(fact.text)) ?? [],
    );
    const entries = field === 'careNotes' ? (profile.careNotes ?? '').split('\n') : (profile[field] ?? []);
    const retained = entries.filter((text) => !generated.has(profileFactKey(text)));
    if (field === 'careNotes') manual.careNotes = retained.join('\n') || null;
    else manual[field] = retained;
  }
  delete manual.aiMedicalHistory;
  return manual;
}
function suppressedFacts(
  profile: PatientProfile,
): Pick<AIMedicalHistory, 'suppressed' | 'suppressedRecordIDs'> {
  const suppressed = structuredClone(profile.aiMedicalHistory?.suppressed ?? {});
  const suppressedRecordIDs = structuredClone(profile.aiMedicalHistory?.suppressedRecordIDs ?? {});
  for (const field of medicalProfileFields) {
    const current = field === 'careNotes' ? (profile.careNotes ?? '').split('\n') : (profile[field] ?? []);
    const retained = new Set(current.map(profileFactKey));
    const removed =
      profile.aiMedicalHistory?.facts[field].filter((fact) => !retained.has(profileFactKey(fact.text))) ?? [];
    suppressed[field] = [
      ...new Set([...(suppressed[field] ?? []), ...removed.map((fact) => profileFactKey(fact.text))]),
    ];
    suppressedRecordIDs[field] = [
      ...new Set([...(suppressedRecordIDs[field] ?? []), ...removed.flatMap((fact) => fact.recordIDs)]),
    ];
  }
  return { suppressed, suppressedRecordIDs };
}

// MARK: - Keep facts and signature together, including manual removals made on either device.
export function mergeMedicalProfiles(
  base: PatientProfile | undefined,
  local: PatientProfile,
  remote: PatientProfile,
  merge: (base: PatientProfile | undefined, local: PatientProfile, remote: PatientProfile) => PatientProfile,
  equal: (left: unknown, right: unknown) => boolean,
): PatientProfile {
  if (!local.aiMedicalHistory && !remote.aiMedicalHistory && !base?.aiMedicalHistory)
    return merge(base, local, remote);
  const manual = merge(base ? manualProfile(base) : undefined, manualProfile(local), manualProfile(remote));
  const history = !remote.aiMedicalHistory
    ? local.aiMedicalHistory
    : !local.aiMedicalHistory
      ? remote.aiMedicalHistory
      : equal(base?.aiMedicalHistory, remote.aiMedicalHistory)
        ? local.aiMedicalHistory
        : remote.aiMedicalHistory;
  if (!history) return manual;
  const left = suppressedFacts(local),
    right = suppressedFacts(remote);
  const suppressed = Object.fromEntries(
    medicalProfileFields.map((field) => [
      field,
      [...new Set([...(left.suppressed?.[field] ?? []), ...(right.suppressed?.[field] ?? [])])],
    ]),
  );
  const suppressedRecordIDs = Object.fromEntries(
    medicalProfileFields.map((field) => [
      field,
      [
        ...new Set([
          ...(left.suppressedRecordIDs?.[field] ?? []),
          ...(right.suppressedRecordIDs?.[field] ?? []),
        ]),
      ],
    ]),
  );
  manual.aiMedicalHistory = { ...history, facts: emptyProfileFacts(), suppressed, suppressedRecordIDs };
  return applyMedicalProfile(
    manual,
    { ...history.facts, model: history.model },
    history.sourceSignature,
    history.generatedAt,
  );
}
