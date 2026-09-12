// Purpose: Keep the signed-in session (bearer token, expiry and user) in browser storage safely.
// Inputs: An auth envelope from the server, an optional injectable storage, and the current time.
// Outputs: A live session or null; expired or malformed entries read as absent.
// Side effects: localStorage reads/writes under one key, every access wrapped in try/catch; no HTTP.

// MARK: - Storage key, wire shape and an injectable storage boundary for tests
export const SESSION_KEY = 'reva.session.v1';
export interface SessionUser {
  id: string;
  email: string;
  name: string;
  createdAt: string;
}
export interface StoredSession {
  token: string;
  expiresAt: string;
  user: SessionUser;
}
export type StorageLike = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
// Reading `localStorage` itself can throw (blocked storage, sandboxed frames), so resolve it lazily.
export function browserStorage(): StorageLike | null {
  try {
    return globalThis.localStorage ?? null;
  } catch {
    return null;
  }
}

// MARK: - Shape checks reject anything that could not have come from the auth API
function text(value: unknown, maximum = 512): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= maximum && !/[\r\n]/.test(value);
}
export function sessionUser(value: unknown): SessionUser | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const user = value as Record<string, unknown>;
  if (!text(user.id, 80) || !text(user.email, 254) || !text(user.name, 80) || !text(user.createdAt, 64))
    return null;
  return { id: user.id, email: user.email, name: user.name, createdAt: user.createdAt };
}
export function checkedSession(value: unknown): StoredSession | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const entry = value as Record<string, unknown>;
  const user = sessionUser(entry.user);
  if (!text(entry.token) || !text(entry.expiresAt, 64) || !user) return null;
  if (!Number.isFinite(Date.parse(entry.expiresAt))) return null;
  return { token: entry.token, expiresAt: entry.expiresAt, user };
}
export function sessionIsLive(session: StoredSession, now: number = Date.now()): boolean {
  return Date.parse(session.expiresAt) > now;
}

// MARK: - Read, write and clear; an expired or malformed entry is removed and reported as absent
function parsed(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
export function readSession(
  storage: StorageLike | null = browserStorage(),
  now: number = Date.now(),
): StoredSession | null {
  try {
    const raw = storage?.getItem(SESSION_KEY);
    if (!raw) return null;
    const session = checkedSession(parsed(raw));
    if (session && sessionIsLive(session, now)) return session;
    storage?.removeItem(SESSION_KEY);
    return null;
  } catch {
    return null;
  }
}
export function writeSession(
  session: StoredSession,
  storage: StorageLike | null = browserStorage(),
): boolean {
  try {
    const checked = checkedSession(session);
    if (!checked || !sessionIsLive(checked)) return false;
    storage?.setItem(SESSION_KEY, JSON.stringify(checked));
    return storage !== null;
  } catch {
    return false;
  }
}
export function clearSession(storage: StorageLike | null = browserStorage()): void {
  try {
    storage?.removeItem(SESSION_KEY);
  } catch {
    /* Chunk: Storage that cannot be cleared here is still unusable for a bearer token that expires. */
  }
}
