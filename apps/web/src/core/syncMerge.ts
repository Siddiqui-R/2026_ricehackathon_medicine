// Purpose: Combine concurrent account changes without silently discarding an edited item.
// Inputs: The last shared snapshot (if known), this browser's edits and the latest server snapshot.
// Outputs: A validated snapshot and the count of conflicts preserved as labeled recovered items.
// Side effects: None; deterministic recovery IDs make retries idempotent.
import type { AppSnapshot, MedicalRecord } from './models';
import { validateSnapshot } from './validation';
import { mergeMedicalProfiles } from './medicalProfileMerge';

// MARK: - JSON values merge by field; string lists merge additions and known deletions.
function canonical(value: unknown): string | undefined {
  return JSON.stringify(value, (_key, item) =>
    object(item)
      ? Object.fromEntries(
          Object.keys(item)
            .sort()
            .map((key) => [key, item[key]]),
        )
      : item,
  );
}
export const sameSyncValue = (left: unknown, right: unknown): boolean => canonical(left) === canonical(right);
type ObjectValue = Record<string, unknown>;
const object = (value: unknown): value is ObjectValue =>
  !!value && typeof value === 'object' && !Array.isArray(value);
function combine(base: unknown, local: unknown, remote: unknown, conflict: () => void): unknown {
  if (sameSyncValue(local, remote) || sameSyncValue(base, local)) return remote;
  if (sameSyncValue(base, remote)) return local;
  if (
    Array.isArray(local) &&
    Array.isArray(remote) &&
    [...local, ...remote].every((v) => typeof v === 'string')
  ) {
    const original = Array.isArray(base) ? base : [];
    return [...new Set([...remote, ...local])].filter(
      (value) => !original.includes(value) || (local.includes(value) && remote.includes(value)),
    );
  }
  if (object(local) && object(remote)) {
    const original = object(base) ? base : {};
    return Object.fromEntries(
      [...new Set([...Object.keys(local), ...Object.keys(remote)])]
        .map((key) => [
          key,
          // Generated evidence must remain a coherent bundle; its controller rebuilds after source changes.
          key === 'version' && typeof local[key] === 'number' && typeof remote[key] === 'number'
            ? Math.max(local[key] as number, remote[key] as number)
            : key === 'aiMedicalHistory'
              ? sameSyncValue(original[key], remote[key])
                ? local[key]
                : remote[key]
              : combine(original[key], local[key], remote[key], conflict),
        ])
        .filter(([, value]) => value !== undefined),
    );
  }
  conflict();
  return remote;
}
function fingerprint(value: unknown): string {
  const text = canonical(value)!;
  let first = 2166136261,
    second = 5381;
  for (let index = 0; index < text.length; index++) {
    first = Math.imul(first ^ text.charCodeAt(index), 16777619);
    second = Math.imul(second, 33) ^ text.charCodeAt(index);
  }
  return `${(first >>> 0).toString(16)}${(second >>> 0).toString(16)}`;
}
type Item = { id: string; title?: string; version?: number; report?: unknown };
function collection<T extends Item>(
  base: T[],
  local: T[],
  remote: T[],
  recovered: () => void,
  originalConflicts = new Set<string>(),
): T[] {
  const original = new Map(base.map((item) => [item.id, item]));
  const here = new Map(local.map((item) => [item.id, item]));
  const there = new Map(remote.map((item) => [item.id, item]));
  const result = new Map<string, T>();
  for (const id of new Set([...there.keys(), ...here.keys()])) {
    const before = original.get(id),
      left = here.get(id),
      right = there.get(id);
    if (!left || !right) {
      const remaining = left ?? right!;
      // A deletion wins only when the surviving side did not edit the item.
      if (!before || !sameSyncValue(before, remaining)) result.set(id, structuredClone(remaining));
      continue;
    }
    let conflict = originalConflicts.has(id);
    const merged = conflict
      ? structuredClone(right)
      : (combine(before, left, right, () => {
          conflict = true;
        }) as T);
    if (typeof merged.version === 'number' && !sameSyncValue(merged, right) && !sameSyncValue(merged, left))
      merged.version = Math.max(left.version ?? 0, right.version ?? 0) + 1;
    result.set(id, structuredClone(merged));
    if (!conflict) continue;
    const copy = structuredClone(left);
    copy.id = `sync-copy-${fingerprint([id, left])}`;
    if (copy.title) copy.title += ' (saved on another device)';
    if (object(copy.report)) copy.report = { ...copy.report, visitID: copy.id, id: `${copy.id}-report` };
    if (!here.has(copy.id) && !there.has(copy.id)) recovered();
    result.set(copy.id, copy);
  }
  return [...result.values()];
}

// MARK: - Snapshot relationships and profile conflicts retain source values and usable references.
export function mergeSnapshots(
  base: AppSnapshot | null,
  local: AppSnapshot,
  remote: AppSnapshot,
  originalConflicts?: {
    records: Set<string>;
    recordings: Set<string>;
  },
): {
  snapshot: AppSnapshot;
  recovered: number;
} {
  let recovered = 0,
    profileConflict = false;
  const count = () => {
    recovered += 1;
  };
  const snapshot: AppSnapshot = {
    ...structuredClone(remote),
    profile: mergeMedicalProfiles(
      base?.profile,
      local.profile,
      remote.profile,
      (before, here, there) =>
        combine(before, here, there, () => {
          profileConflict = true;
        }) as AppSnapshot['profile'],
      sameSyncValue,
    ),
    records: collection(
      base?.records ?? [],
      local.records,
      remote.records,
      count,
      originalConflicts?.records,
    ),
    visits: collection(base?.visits ?? [], local.visits, remote.visits, count),
    bookings: collection(base?.bookings ?? [], local.bookings, remote.bookings, count),
    recordings: collection(
      base?.recordings ?? [],
      local.recordings,
      remote.recordings,
      count,
      originalConflicts?.recordings,
    ),
  };
  const copiedID = (item: Item) => `sync-copy-${fingerprint([item.id, item])}`;
  for (const original of local.recordings) {
    const copy = snapshot.recordings.find((item) => item.id === copiedID(original));
    const visit = local.visits.find((item) => item.id === original.visitID);
    if (copy && visit && snapshot.visits.some((item) => item.id === copiedID(visit)))
      copy.visitID = copiedID(visit);
  }
  for (const original of local.records) {
    const copy = snapshot.records.find((item) => item.id === copiedID(original));
    const recording = local.recordings.find((item) => item.id === original.sourceRecordingID);
    if (copy && recording && snapshot.recordings.some((item) => item.id === copiedID(recording)))
      copy.sourceRecordingID = copiedID(recording);
  }
  if (profileConflict) {
    const { aiMedicalHistory: _generated, ...profile } = local.profile;
    const id = `sync-profile-${fingerprint(profile)}`;
    if (!snapshot.records.some((record) => record.id === id)) {
      const date = new Date().toISOString();
      const recovery: MedicalRecord = {
        id,
        title: 'Medical profile saved on another device',
        kind: 'Sync recovery',
        provider: '',
        date,
        uploadedAt: date,
        tags: ['sync recovery'],
        pageCount: 1,
        status: 'needs review',
        text: `Original profile values preserved after simultaneous edits on different devices.\n\n${JSON.stringify(profile, null, 2)}`,
        summary: 'A preserved copy of conflicting profile edits. Review these values before using them.',
        notes: 'This recovery copy is not a medical report or new clinical evidence.',
        isDemo: local.profile.isDemo,
        version: 1,
      };
      snapshot.records.push(recovery);
      count();
    }
  }
  // A new recording or booking can race a visit deletion. Keep the referenced visit so neither is orphaned.
  for (const child of [...snapshot.recordings, ...snapshot.bookings]) {
    if (!child.visitID || snapshot.visits.some((visit) => visit.id === child.visitID)) continue;
    const visit = [...local.visits, ...remote.visits, ...(base?.visits ?? [])].find(
      (item) => item.id === child.visitID,
    );
    if (visit) snapshot.visits.push(structuredClone(visit));
  }
  const recordIDs = new Set(snapshot.records.map((record) => record.id));
  snapshot.visits.forEach((visit) => {
    visit.pinnedRecordIDs = visit.pinnedRecordIDs.filter((id) => recordIDs.has(id));
  });
  return { snapshot: validateSnapshot(snapshot), recovered };
}
