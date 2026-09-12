// Purpose: Supply fictional fixtures and deterministic injectable boundaries for core tests.
// Inputs: Checked-in synthetic demo JSON and test-controlled responses.
// Outputs: Isolated snapshots, repositories, transports, a fake Storage, a test user and deferred promises.
// Side effects: None outside test memory; never contacts a provider or writes real workspace data.
import seedJSON from '../../../public/demo/seed.json';
import sampleJSON from '../../../public/demo/sample-transcript.json';
import type { AppSnapshot, ProviderStatus, VisitRecording } from '../models.ts';
import type { SnapshotRepository, StoredSnapshot } from '../repository.ts';
import { LocalConflictError } from '../repository.ts';
import { APIError } from '../api.ts';
import type { AuthTransport } from '../auth.ts';
import type { SessionUser, StorageLike } from '../session.ts';
import type { APITransport } from '../store.ts';

// MARK: - Every caller receives a fresh fictional snapshot.
export const seed = (): AppSnapshot => structuredClone(seedJSON);
export const sample = (): VisitRecording => structuredClone(sampleJSON);
export const capabilities: ProviderStatus = {
  gemini: { configured: true, model: 'mock-gemini' },
  transcription: { configured: true, model: 'mock-whisper' },
};
export function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

// MARK: - Durable publication and optimistic checks have a controllable test boundary.
export class MemoryRepository implements SnapshotRepository {
  saved: StoredSnapshot | null = { snapshot: seed(), revision: 1 };
  attachments = new Map<string, Blob>();
  failure: Error | null = null;
  async load() {
    if (this.failure) throw this.failure;
    return structuredClone(this.saved);
  }
  async seed() {
    return seed();
  }
  async commit(
    snapshot: AppSnapshot,
    expectedRevision: number,
    attachments: ReadonlyMap<string, Blob> = new Map(),
  ) {
    if (this.failure) throw this.failure;
    if ((this.saved?.revision ?? 0) !== expectedRevision) throw new LocalConflictError();
    const saved = { snapshot: structuredClone(snapshot), revision: expectedRevision + 1 };
    attachments.forEach((blob, name) => this.attachments.set(name, blob));
    this.saved = saved;
    return structuredClone(saved);
  }
  async reset(snapshot: AppSnapshot) {
    this.failure = null;
    return this.commit(snapshot, this.saved?.revision ?? 0);
  }
  async saveAttachment(filename: string, blob: Blob) {
    this.attachments.set(filename, blob);
  }
  async getAttachment(filename: string) {
    return this.attachments.get(filename) ?? new Blob(['synthetic original'], { type: 'application/pdf' });
  }
  destroyed = false;
  async destroy() {
    this.saved = null;
    this.attachments.clear();
    this.destroyed = true;
  }
}

// MARK: - Account-mode boundaries: an in-memory Storage and an auth transport that fails closed.
export function fakeStorage(
  entries: Record<string, string> = {},
): StorageLike & { data: Map<string, string> } {
  const data = new Map(Object.entries(entries));
  return {
    data,
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, String(value)),
    removeItem: (key) => void data.delete(key),
  };
}
export const testUser: SessionUser = {
  id: 'u_0123456789abcdef01234567',
  email: 'synthetic.person@example.test',
  name: 'Synthetic Person',
  createdAt: '2026-09-12T10:00:00Z',
};
export function authTransport(overrides: Partial<AuthTransport> = {}): AuthTransport {
  const unavailable = async (): Promise<never> => {
    throw new Error('Unexpected auth operation in test.');
  };
  return {
    signup: unavailable,
    login: unavailable,
    session: unavailable,
    logout: async () => {},
    logoutAll: async () => {},
    changePassword: async () => {},
    deleteAccount: async () => {},
    ...overrides,
  };
}

// MARK: - Unspecified provider operations fail closed so a test cannot make a hidden live request.
export function transport(overrides: Partial<APITransport> = {}): APITransport {
  const unavailable = async (): Promise<never> => {
    throw new Error('Unexpected provider operation in test.');
  };
  return {
    health: async () => 'Connected · local',
    providers: async () => structuredClone(capabilities),
    pull: async () => {
      throw new APIError(404, 0);
    },
    push: async (_snapshot, revision) => revision + 1,
    uploadAttachment: async () => {},
    attachment: async () => new Blob(['synthetic remote original']),
    summarize: unavailable,
    prepare: unavailable,
    transcribe: unavailable,
    ...overrides,
  };
}
