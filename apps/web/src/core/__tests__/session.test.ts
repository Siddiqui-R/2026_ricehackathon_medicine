// Purpose: Verify the stored session survives a round trip and that anything stale or broken reads as absent.
// Inputs: A fake in-memory Storage, a throwing Storage and synthetic session envelopes.
// Outputs: Assertions for read/write/clear, expiry handling, shape checks and storage failures.
// Side effects: Test memory only; no real localStorage and no HTTP.
import { describe, expect, it } from 'vitest';
import {
  clearSession,
  readSession,
  SESSION_KEY,
  sessionIsLive,
  writeSession,
  type StoredSession,
} from '../session.ts';
import { fakeStorage, testUser } from './fixtures.ts';

// MARK: - Fixtures: one live and one expired session around a fixed "now".
const now = Date.parse('2026-09-12T12:00:00Z');
const live = (): StoredSession => ({
  token: 'synthetic-session-token',
  expiresAt: '2026-10-12T12:00:00Z',
  user: { ...testUser },
});
const expired = (): StoredSession => ({ ...live(), expiresAt: '2026-09-12T11:59:59Z' });
function throwingStorage() {
  const fail = () => {
    throw new Error('Storage is blocked in this context.');
  };
  return { getItem: fail, setItem: fail, removeItem: fail };
}

// MARK: - A written session reads back unchanged and clears completely.
describe('session storage round trip', () => {
  it('writes the checked envelope under the versioned key and reads it back', () => {
    const storage = fakeStorage();
    expect(writeSession(live(), storage)).toBe(true);
    expect(JSON.parse(storage.data.get(SESSION_KEY)!)).toEqual(live());
    expect(readSession(storage, now)).toEqual(live());
  });
  it('drops unknown fields so nothing beyond token, expiry and user is stored', () => {
    const storage = fakeStorage();
    const extra = { ...live(), refreshToken: 'never', user: { ...testUser, role: 'admin' } };
    expect(writeSession(extra as StoredSession, storage)).toBe(true);
    expect(JSON.parse(storage.data.get(SESSION_KEY)!)).toEqual(live());
  });
  it('clears the key and then reads as absent', () => {
    const storage = fakeStorage();
    writeSession(live(), storage);
    clearSession(storage);
    expect(storage.data.has(SESSION_KEY)).toBe(false);
    expect(readSession(storage, now)).toBeNull();
  });
  it('reports liveness against the supplied clock', () => {
    expect(sessionIsLive(live(), now)).toBe(true);
    expect(sessionIsLive(expired(), now)).toBe(false);
    expect(sessionIsLive(live(), Date.parse('2026-10-12T12:00:00Z'))).toBe(false);
  });
});

// MARK: - Expired or malformed entries are removed rather than trusted.
describe('stale and malformed sessions', () => {
  it('treats an expired session as absent and removes it', () => {
    const storage = fakeStorage({ [SESSION_KEY]: JSON.stringify(expired()) });
    expect(readSession(storage, now)).toBeNull();
    expect(storage.data.has(SESSION_KEY)).toBe(false);
  });
  it('refuses to write an already-expired session', () => {
    const storage = fakeStorage();
    expect(writeSession(expired(), storage)).toBe(false);
    expect(storage.data.has(SESSION_KEY)).toBe(false);
  });
  it.each([
    ['not JSON', '{token'],
    ['an array', '[]'],
    ['a missing token', JSON.stringify({ ...live(), token: '' })],
    ['a token with a line break', JSON.stringify({ ...live(), token: 'a\nb' })],
    ['an unparsable expiry', JSON.stringify({ ...live(), expiresAt: 'someday' })],
    ['a user without an email', JSON.stringify({ ...live(), user: { ...testUser, email: '' } })],
    ['a non-object user', JSON.stringify({ ...live(), user: 'synthetic' })],
  ])('reads %s as absent and removes it', (_label, raw) => {
    const storage = fakeStorage({ [SESSION_KEY]: raw });
    expect(readSession(storage, now)).toBeNull();
    expect(storage.data.has(SESSION_KEY)).toBe(false);
  });
  it('never writes a malformed envelope', () => {
    const storage = fakeStorage();
    expect(writeSession({ ...live(), user: { ...testUser, id: '' } }, storage)).toBe(false);
    expect(storage.data.size).toBe(0);
  });
});

// MARK: - Blocked storage cannot break the page: reads are null, writes report failure, clears are silent.
describe('unavailable storage', () => {
  it('reads null and writes false when every storage call throws', () => {
    const storage = throwingStorage();
    expect(readSession(storage, now)).toBeNull();
    expect(writeSession(live(), storage)).toBe(false);
    expect(() => clearSession(storage)).not.toThrow();
  });
  it('treats a missing storage object as absent and unwritable', () => {
    expect(readSession(null, now)).toBeNull();
    expect(writeSession(live(), null)).toBe(false);
    expect(() => clearSession(null)).not.toThrow();
  });
});
