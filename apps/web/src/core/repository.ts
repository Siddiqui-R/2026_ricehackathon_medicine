// Purpose: Durably store one browser snapshot and its original files with atomic local revisions.
// Inputs: Validated snapshots, safe leaf filenames, original Blobs, expected local revisions and a
//         database name (the shared demo database, or one private database per signed-in account).
// Outputs: Restored state, preserved originals or explicit corruption/quota/concurrent-tab errors.
// Side effects: IndexedDB transactions, whole-database deletion on request, and same-origin reads of
//               explicitly bundled demo assets.
import type { AppSnapshot, ServerState } from './models.ts';
import { demoDatabaseName, demoSnapshot, selectedDemoPerson, type DemoPersonID } from './demoProfiles';
import { safeFilename, validateSnapshot } from './validation.ts';
import { boundedBytes, MAX_ATTACHMENT_BYTES, MAX_SNAPSHOT_BYTES } from './api.ts';

// MARK: - Injectable persistence contract keeps React independent of browser storage internals.
export interface StoredSnapshot {
  snapshot: AppSnapshot;
  revision: number;
}
export interface SnapshotRepository {
  load(): Promise<StoredSnapshot | null>;
  commit(
    snapshot: AppSnapshot,
    expectedRevision: number,
    attachments?: ReadonlyMap<string, Blob>,
  ): Promise<StoredSnapshot>;
  reset(snapshot: AppSnapshot): Promise<StoredSnapshot>;
  seed(): Promise<AppSnapshot>;
  saveAttachment(filename: string, blob: Blob): Promise<void>;
  getAttachment(filename: string): Promise<Blob>;
  // The last server snapshot lives beside the local copy for durable three-way reconciliation.
  loadSyncBase?(): Promise<ServerState | null>;
  saveSyncBase?(state: ServerState): Promise<void>;
  // Optional: remove this database entirely (account deletion). Absent for repositories that cannot.
  destroy?(): Promise<void>;
}
export class LocalConflictError extends Error {
  constructor() {
    super(
      'This browser workspace changed in another tab. Your saved data was kept. Reload this tab before saving again.',
    );
    this.name = 'LocalConflictError';
  }
}
function checkedBlob(filename: string, blob: unknown): asserts blob is Blob {
  if (!safeFilename(filename)) throw new Error('The original filename is invalid.');
  if (!(blob instanceof Blob) || !blob.size || blob.size > MAX_ATTACHMENT_BYTES)
    throw new Error('This original is invalid, empty or larger than 16 MiB. Your existing files were kept.');
}
function checkedStored(value: unknown): StoredSnapshot {
  if (
    !value ||
    typeof value !== 'object' ||
    !('revision' in value) ||
    !Number.isSafeInteger(value.revision) ||
    (value.revision as number) < 1 ||
    !('snapshot' in value)
  )
    throw new Error(
      'The saved browser workspace is corrupt. Existing data was kept; restore a backup or explicitly reset the demo.',
    );
  return { revision: value.revision as number, snapshot: validateSnapshot(value.snapshot) };
}

// MARK: - Opening is lazy; an unavailable or blocked database never creates an in-memory fallback.
export class IndexedDBRepository implements SnapshotRepository {
  private database?: Promise<IDBDatabase>;
  private manifest?: Promise<Array<{ filename: string; sha256: string; bytes: number; mimeType: string }>>;
  constructor(
    private readonly name = 'reva-workspace-v1',
    private readonly factory: IDBFactory | undefined = globalThis.indexedDB,
    private readonly fetcher: typeof fetch = globalThis.fetch.bind(globalThis),
  ) {}
  private open(): Promise<IDBDatabase> {
    if (!this.database)
      this.database = new Promise((resolve, reject) => {
        if (!this.factory) {
          reject(
            new Error(
              'This browser does not provide persistent storage. Enable site storage before adding records.',
            ),
          );
          return;
        }
        const request = this.factory.open(this.name, 1);
        request.onupgradeneeded = () => {
          request.result.createObjectStore('snapshots');
          request.result.createObjectStore('attachments');
        };
        request.onerror = () => reject(request.error ?? new Error('Browser storage could not open.'));
        request.onblocked = () =>
          reject(new Error('Another open Reva tab blocks the storage upgrade. Close it and reload.'));
        request.onsuccess = () => {
          request.result.onversionchange = () => {
            request.result.close();
            this.database = undefined;
          };
          resolve(request.result);
        };
      });
    return this.database;
  }
  async load(): Promise<StoredSnapshot | null> {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('snapshots', 'readonly'),
        request = transaction.objectStore('snapshots').get('current');
      let result: StoredSnapshot | null = null,
        failure: unknown;
      request.onsuccess = () => {
        try {
          result = request.result === undefined ? null : checkedStored(request.result);
        } catch (error) {
          failure = error;
        }
      };
      transaction.oncomplete = () => (failure ? reject(failure) : resolve(result));
      transaction.onabort = () => reject(transaction.error ?? new Error('Saved data could not be read.'));
    });
  }
  async loadSyncBase(): Promise<ServerState | null> {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('snapshots', 'readonly');
      const request = transaction.objectStore('snapshots').get('sync-base');
      let result: ServerState | null = null,
        failure: unknown;
      request.onsuccess = () => {
        try {
          if (request.result !== undefined) result = checkedStored(request.result);
        } catch (error) {
          failure = error;
        }
      };
      transaction.oncomplete = () => (failure ? reject(failure) : resolve(result));
      transaction.onabort = () =>
        reject(transaction.error ?? new Error('The saved synchronization baseline could not be read.'));
    });
  }
  async saveSyncBase(state: ServerState): Promise<void> {
    const value = checkedStored(state);
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('snapshots', 'readwrite');
      const store = transaction.objectStore('snapshots');
      const request = store.get('sync-base');
      request.onsuccess = () => {
        // A slower request from another tab must never move the shared baseline backwards.
        if (!request.result || request.result.revision <= value.revision) store.put(value, 'sync-base');
      };
      transaction.oncomplete = () => resolve();
      transaction.onabort = () =>
        reject(transaction.error ?? new Error('The synchronization baseline could not be saved.'));
    });
  }

  // MARK: - A single read/write transaction checks the revision and publishes all originals with state.
  private async write(
    snapshot: AppSnapshot,
    expectedRevision: number | null,
    attachments: ReadonlyMap<string, Blob> = new Map(),
  ): Promise<StoredSnapshot> {
    const copy = structuredClone(validateSnapshot(snapshot));
    if (new TextEncoder().encode(JSON.stringify(copy)).length > MAX_SNAPSHOT_BYTES)
      throw new Error(
        'The workspace exceeds the 4 MiB snapshot limit. Shorten extracted text before saving.',
      );
    attachments.forEach((blob, filename) => checkedBlob(filename, blob));
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(['snapshots', 'attachments'], 'readwrite'),
        state = transaction.objectStore('snapshots');
      const request = state.get('current');
      let result: StoredSnapshot | undefined, failure: unknown;
      request.onsuccess = () => {
        try {
          const current = request.result;
          const currentRevision =
            current === undefined
              ? 0
              : expectedRevision === null
                ? Number.isSafeInteger(current?.revision) && current.revision >= 0
                  ? current.revision
                  : 0
                : checkedStored(current).revision;
          if (expectedRevision !== null && expectedRevision !== currentRevision)
            throw new LocalConflictError();
          if (!Number.isSafeInteger(currentRevision + 1))
            throw new Error(
              'The local revision limit was reached. Export this workspace before restoring it.',
            );
          result = { snapshot: copy, revision: currentRevision + 1 };
          attachments.forEach((blob, filename) => transaction.objectStore('attachments').put(blob, filename));
          state.put(result, 'current');
        } catch (error) {
          failure = error;
          transaction.abort();
        }
      };
      transaction.oncomplete = () => resolve(result!);
      transaction.onabort = () =>
        reject(
          failure ??
            transaction.error ??
            new Error('Browser storage could not save this change. Your previous data was kept.'),
        );
    });
  }
  commit(
    snapshot: AppSnapshot,
    expectedRevision: number,
    attachments?: ReadonlyMap<string, Blob>,
  ): Promise<StoredSnapshot> {
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0)
      return Promise.reject(new Error('The browser revision is invalid. Reload before saving.'));
    return this.write(snapshot, expectedRevision, attachments);
  }
  reset(snapshot: AppSnapshot): Promise<StoredSnapshot> {
    return this.write(snapshot, null);
  }

  // MARK: - Original lookup distinguishes missing bundled files from corrupt saved bytes.
  async saveAttachment(filename: string, blob: Blob): Promise<void> {
    checkedBlob(filename, blob);
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('attachments', 'readwrite');
      transaction.objectStore('attachments').put(blob, filename);
      transaction.oncomplete = () => resolve();
      transaction.onabort = () => reject(transaction.error ?? new Error('The original could not be saved.'));
    });
  }
  async getAttachment(filename: string): Promise<Blob> {
    if (!safeFilename(filename)) throw new Error('The original filename is invalid.');
    const db = await this.open();
    const stored: unknown = await new Promise((resolve, reject) => {
      const transaction = db.transaction('attachments', 'readonly'),
        request = transaction.objectStore('attachments').get(filename);
      let result: unknown;
      request.onsuccess = () => {
        result = request.result;
      };
      transaction.oncomplete = () => resolve(result);
      transaction.onabort = () => reject(transaction.error ?? new Error('The original could not be read.'));
    });
    if (stored !== undefined) {
      checkedBlob(filename, stored);
      return stored;
    }
    const source = (await this.bundledSources()).find((item) => item.filename === filename);
    if (!source)
      throw new Error(
        `The original “${filename}” is not available in this browser yet. Reconnect to finish downloading your account files.`,
      );
    const response = await this.fetcher(`/demo/${encodeURIComponent(filename)}`, {
      credentials: 'omit',
      redirect: 'error',
      cache: 'no-store',
    });
    if (!response.ok)
      throw new Error(
        `The original “${filename}” is not available in this browser yet. Reconnect to finish downloading your account files.`,
      );
    const bytes = await boundedBytes(response, MAX_ATTACHMENT_BYTES);
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), (byte) =>
      byte.toString(16).padStart(2, '0'),
    ).join('');
    if (source.bytes !== bytes.length || source.sha256 !== hash)
      throw new Error('The bundled original does not match its manifest. No replacement file was used.');
    const blob = new Blob([bytes], { type: source.mimeType });
    checkedBlob(filename, blob);
    return blob;
  }
  private bundledSources(): Promise<
    Array<{ filename: string; sha256: string; bytes: number; mimeType: string }>
  > {
    if (!this.manifest)
      this.manifest = (async () => {
        const response = await this.fetcher('/demo/fixture-manifest.json', {
          credentials: 'omit',
          redirect: 'error',
          cache: 'no-store',
        });
        if (!response.ok) throw new Error('The bundled source manifest is unavailable.');
        const manifest = JSON.parse(
          new TextDecoder('utf-8', { fatal: true }).decode(await boundedBytes(response, 128 * 1024)),
        );
        if (
          !manifest ||
          manifest.synthetic !== true ||
          !Array.isArray(manifest.sources) ||
          manifest.sources.length > 128 ||
          manifest.sources.some(
            (item: Record<string, unknown>) =>
              !item ||
              typeof item.filename !== 'string' ||
              !safeFilename(item.filename) ||
              typeof item.sha256 !== 'string' ||
              !/^[a-f0-9]{64}$/.test(item.sha256) ||
              !Number.isSafeInteger(item.bytes) ||
              (item.bytes as number) < 1 ||
              (item.bytes as number) > MAX_ATTACHMENT_BYTES ||
              typeof item.mimeType !== 'string',
          )
        )
          throw new Error('The bundled source manifest is invalid.');
        return manifest.sources;
      })();
    return this.manifest;
  }
  async seed(): Promise<AppSnapshot> {
    const response = await this.fetcher('/demo/seed.json', {
      credentials: 'omit',
      redirect: 'error',
      cache: 'no-store',
    });
    if (!response.ok) throw new Error('The bundled fictional demo could not be loaded.');
    const result = validateSnapshot(
      JSON.parse(
        new TextDecoder('utf-8', { fatal: true }).decode(await boundedBytes(response, MAX_SNAPSHOT_BYTES)),
      ),
    );
    if (!result.profile.isDemo) throw new Error('The bundled seed is not marked as fictional demo data.');
    return result;
  }
  async close(): Promise<void> {
    (await this.database)?.close();
    this.database = undefined;
  }
  // Deletes the whole database after closing it. A tab that still holds it open blocks the deletion;
  // the browser completes it once that tab closes, so a bounded wait resolves instead of hanging.
  async destroy(): Promise<void> {
    await this.close();
    const factory = this.factory;
    if (!factory) return;
    await new Promise<void>((resolve, reject) => {
      const request = factory.deleteDatabase(this.name);
      const deadline = setTimeout(resolve, 5000);
      request.onsuccess = () => {
        clearTimeout(deadline);
        resolve();
      };
      request.onerror = () => {
        clearTimeout(deadline);
        reject(request.error ?? new Error('The local copy could not be removed.'));
      };
    });
  }
}

// MARK: - Feature imports share a single lazy repository; credentials never enter its stores.
export class DemoRepository extends IndexedDBRepository {
  constructor(
    private readonly person: DemoPersonID = selectedDemoPerson(),
    factory: IDBFactory | undefined = globalThis.indexedDB,
    fetcher: typeof fetch = globalThis.fetch.bind(globalThis),
  ) {
    super(demoDatabaseName(person), factory, fetcher);
  }
  override async seed(): Promise<AppSnapshot> {
    return validateSnapshot(demoSnapshot(await super.seed(), this.person));
  }
}
export const repository = new DemoRepository();
export const saveAttachment = (filename: string, blob: Blob): Promise<void> =>
  repository.saveAttachment(filename, blob);
export const getAttachment = (filename: string): Promise<Blob> => repository.getAttachment(filename);
