// Purpose: Derive an account's private local database name and its first, empty personal snapshot.
// Inputs: The signed-in user's ID and display name.
// Outputs: A per-user IndexedDB name separate from the demo database, and a validated empty snapshot.
// Side effects: None; SHA-256 runs through Web Crypto and nothing is stored here.
import type { AppSnapshot } from './models.ts';
import { sha256, validateSnapshot } from './domain.ts';

// MARK: - Database identity: the demo keeps reva-workspace-v1; each account gets a hashed name
export const DEMO_DATABASE = 'reva-workspace-v1';
export async function accountDatabaseName(userID: string): Promise<string> {
  if (!userID.trim()) throw new Error('A signed-in account is required to open a personal workspace.');
  return `reva-account-${(await sha256(userID)).slice(0, 16)}-v1`;
}

// MARK: - Initials follow the profile editor: first letter of the first and last name-like words
export function initialsFor(name: string): string {
  const words = name
    .trim()
    .split(/\s+/)
    .filter((word) => /^\p{L}/u.test(word) && !word.endsWith(')'));
  const initials = [Array.from(words[0] ?? '')[0], words.length > 1 ? Array.from(words.at(-1) ?? '')[0] : '']
    .filter(Boolean)
    .join('')
    .toUpperCase();
  return initials || Array.from(name.trim())[0]?.toUpperCase() || '';
}

// MARK: - The empty personal snapshot carries only identity; every clinical list starts empty
export function emptyPersonalSnapshot(user: { id: string; name: string }): AppSnapshot {
  const name = user.name.trim() || 'You';
  return validateSnapshot({
    schemaVersion: 1,
    profile: {
      id: user.id,
      name,
      dateOfBirth: '',
      initials: initialsFor(name),
      allergies: [],
      medications: [],
      conditions: [],
      isDemo: false,
      surgeriesAndImplants: null,
      careNotes: null,
    },
    records: [],
    visits: [],
    bookings: [],
    recordings: [],
  });
}
