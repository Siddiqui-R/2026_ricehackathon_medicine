// Purpose: Remember which server revision an account's local copy last matched, per user.
// Inputs: The account owner ID, the server revision and local revision after a successful push or pull.
// Outputs: The last known in-sync pair, or null when unknown, malformed or for another user.
// Side effects: One small localStorage entry per user, every access wrapped in try/catch; no secrets.
import { browserStorage, type StorageLike } from './session.ts';

// MARK: - Marker shape: two non-negative safe integers keyed by owner
export interface SyncMarker {
  serverRevision: number;
  localRevision: number;
}
export const syncMarkerKey = (userID: string): string => `reva.sync.v1.${userID}`;
function revision(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

// MARK: - Read, write and clear never throw; an unreadable marker means "unknown"
export function readSyncMarker(
  userID: string,
  storage: StorageLike | null = browserStorage(),
): SyncMarker | null {
  try {
    const raw = storage?.getItem(syncMarkerKey(userID));
    if (!raw) return null;
    const value = JSON.parse(raw) as Record<string, unknown> | null;
    if (!value || typeof value !== 'object') return null;
    if (!revision(value.serverRevision) || !revision(value.localRevision)) return null;
    return { serverRevision: value.serverRevision, localRevision: value.localRevision };
  } catch {
    return null;
  }
}
export function writeSyncMarker(
  userID: string,
  marker: SyncMarker,
  storage: StorageLike | null = browserStorage(),
): void {
  try {
    if (!revision(marker.serverRevision) || !revision(marker.localRevision)) return;
    storage?.setItem(syncMarkerKey(userID), JSON.stringify(marker));
  } catch {
    /* Chunk: The IndexedDB baseline still merges offline edits; an unknown baseline preserves both copies. */
  }
}
export function clearSyncMarker(userID: string, storage: StorageLike | null = browserStorage()): void {
  try {
    storage?.removeItem(syncMarkerKey(userID));
  } catch {
    /* Chunk: A stale marker only affects the in-sync heuristic; it never authorizes a data change. */
  }
}
