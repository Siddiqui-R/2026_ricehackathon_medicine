// Purpose: Exchange bounded native-compatible payloads with the Swift API at one configured origin.
// Inputs: A bearer token (static workspace or account session), reviewed snapshots, sources and appointment audio.
// Outputs: Validated responses or explicit HTTP, empty-state and conflict failures with the server's reason.
// Side effects: HTTP to the same origin or VITE_REVA_API_ORIGIN only; never stores credentials or merges.
import type {
  AISummary,
  AIPreparation,
  AppSnapshot,
  AudioTranscription,
  MedicalRecord,
  ProviderStatus,
  ServerState,
  Visit,
} from './models.ts';
import { safeFilename, sha256, validateSnapshot } from './domain.ts';
import { validateProfileResult, validateProfileSources, type ProfileSource } from './medicalProfileAI';
import { retryGemini, type GeminiRequestOptions } from './geminiRetry';
import { recordDateContext } from './recordDates';

// MARK: - One API origin: same-origin by default, or a validated VITE_REVA_API_ORIGIN.
// Only https:// or a loopback http:// origin is accepted, so a bearer token can never leak over
// plain HTTP to a remote host. An invalid value fails at startup rather than at the first request.
const LOOPBACK_HOSTS = ['localhost', '127.0.0.1', '[::1]'];
export function resolveAPIOrigin(value: string | undefined | null): string {
  const trimmed = value?.trim() ?? '';
  if (!trimmed) return '';
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw new Error('VITE_REVA_API_ORIGIN must be an absolute https:// origin or a loopback http:// origin.');
  }
  const loopback = url.protocol === 'http:' && LOOPBACK_HOSTS.includes(url.hostname);
  if (
    (url.protocol !== 'https:' && !loopback) ||
    url.username ||
    url.password ||
    url.pathname !== '/' ||
    url.search ||
    url.hash
  )
    throw new Error('VITE_REVA_API_ORIGIN must be an absolute https:// origin or a loopback http:// origin.');
  return url.origin;
}
export const API_ORIGIN = resolveAPIOrigin(import.meta.env.VITE_REVA_API_ORIGIN);
export function apiURL(path: string, origin: string = API_ORIGIN): string {
  if (!path.startsWith('/') || path.startsWith('//')) throw new Error('API paths must be origin-relative.');
  return origin + path;
}

// MARK: - Shared transfer limits, attachment identity and portable metadata.
export const MAX_ATTACHMENT_BYTES = 16 * 1024 * 1024;
export const MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024;
export const MAX_ERROR_BODY_BYTES = 4 * 1024;
export const attachmentID = sha256;
export function attachmentMetadataName(filename: string): string {
  const name = Array.from(filename, (scalar) => (/^[a-zA-Z0-9 ._()\-]$/.test(scalar) ? scalar : '_'))
    .slice(0, 170)
    .join('')
    .trim();
  return !name || name.startsWith('.') ? 'document' : name;
}
export function uploadContentType(type?: string | null): string {
  const normalized = type?.split(';')[0].toLowerCase() ?? 'application/octet-stream';
  return [
    'application/pdf',
    'text/plain',
    'image/png',
    'image/jpeg',
    'image/heic',
    'image/heif',
    'audio/mp4',
    'audio/m4a',
    'audio/x-m4a',
    'audio/mpeg',
    'audio/wav',
    'audio/x-wav',
    'audio/webm',
    'audio/ogg',
    'application/octet-stream',
  ].includes(normalized)
    ? normalized
    : 'application/octet-stream';
}
// A server `reason` (from the `{ error, reason }` body) replaces the generic text when present;
// the status-based fallbacks stay for bodies the server did not or could not describe.
export function defaultReason(status: number, retryAfter: number | null = null): string {
  switch (status) {
    case 400:
      return 'The server rejected this request. Check the entered values and try again.';
    case 401:
      return 'The server did not accept this workspace token.';
    case 403:
      return 'This action is not allowed on this server.';
    case 404:
      return 'This server identity has no saved state or the requested item is unavailable.';
    case 409:
      return 'The server changed during this save. Your browser copy was kept for synchronization.';
    case 422:
      return 'The AI response could not be used. Your original file and saved details are unchanged.';
    case 424:
      return 'The AI service needs its server configuration checked. Your original file and saved details are unchanged.';
    case 429:
      return retryAfter
        ? `Too many attempts. Try again in about ${Math.ceil(retryAfter / 60)} minute${retryAfter > 60 ? 's' : ''}.`
        : 'Too many attempts. Wait a few minutes before trying again.';
    case 503:
      return 'This connected service is not configured or is unavailable. Your saved data was kept.';
    default:
      return `The server returned HTTP ${status}. Your saved data was kept.`;
  }
}
export class APIError extends Error {
  readonly status: number;
  readonly revision: number | null;
  readonly retryAfter: number | null;
  readonly geminiFallback: boolean;
  constructor(
    status: number,
    revision: number | null = null,
    reason: string | null = null,
    retryAfter: number | null = null,
    geminiFallback = false,
  ) {
    super(reason?.trim() || defaultReason(status, retryAfter));
    this.name = 'APIError';
    this.status = status;
    this.revision = revision;
    this.retryAfter = retryAfter;
    this.geminiFallback = geminiFallback;
  }
}
export function headerRetryAfter(value: string | null): number | null {
  return value !== null && /^\d{1,6}$/.test(value.trim()) ? Number(value.trim()) : null;
}
// Reads a bounded JSON error body and returns its `reason` text when the shape matches SafeErrors.
export async function errorReason(response: Response): Promise<string | null> {
  try {
    if (!/^application\/json\b/i.test(response.headers.get('Content-Type') ?? '')) {
      await response.body?.cancel();
      return null;
    }
    const bytes = await boundedBytes(response, MAX_ERROR_BODY_BYTES);
    const body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) as unknown;
    if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
    const reason = (body as Record<string, unknown>).reason;
    return typeof reason === 'string' && reason.trim() && reason.length <= 500 && !/[\r\n]/.test(reason)
      ? reason.trim()
      : null;
  } catch {
    return null;
  }
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('The server response was unreadable.');
  return value as Record<string, unknown>;
}
function string(value: unknown): string {
  if (typeof value !== 'string') throw new Error('The server response contained invalid text.');
  return value;
}
function strings(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 5000)
    throw new Error('The server response contained an invalid list.');
  return value.map(string);
}
function revision(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0)
    throw new Error('The server did not supply a valid revision.');
  return value as number;
}
function headerRevision(value: string | null): number | null {
  return value !== null && /^\d+$/.test(value) && Number.isSafeInteger(Number(value)) ? Number(value) : null;
}

// MARK: - Streaming response bounds prevent a remote payload exhausting browser memory.
export async function boundedBytes(response: Response, limit: number): Promise<Uint8Array<ArrayBuffer>> {
  const declared = Number(response.headers.get('Content-Length'));
  if (declared > limit) {
    await response.body?.cancel();
    throw new Error('The response exceeds the supported size limit.');
  }
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel();
        throw new Error('The response exceeds the supported size limit.');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

// MARK: - One authenticated request boundary with timeouts and no credential redirects.
// Every path goes through apiURL, so a configured remote origin applies to state, originals and providers.
export class RevaAPI {
  private readonly token: string;
  private readonly fetcher: typeof fetch;
  private readonly chunkedTransfers: boolean;
  constructor(
    token: string,
    fetcher: typeof fetch = globalThis.fetch.bind(globalThis),
    chunkedTransfers = import.meta.env.VITE_REVA_VERCEL === 'true',
  ) {
    if (!token.trim() || /[\r\n]/.test(token)) throw new Error('Enter a nonempty workspace token.');
    this.token = token;
    this.fetcher = fetcher;
    this.chunkedTransfers = chunkedTransfers;
  }
  private async send(
    path: string,
    method = 'GET',
    body?: BodyInit,
    headers: Record<string, string> = {},
    limit = MAX_SNAPSHOT_BYTES,
    timeout = 25_000,
    signal?: AbortSignal,
  ) {
    const controller = new AbortController(),
      timer = setTimeout(() => controller.abort(), timeout);
    const cancel = () => controller.abort();
    signal?.addEventListener('abort', cancel, { once: true });
    try {
      if (signal?.aborted) throw new DOMException('The request was canceled.', 'AbortError');
      const response = await this.fetcher(apiURL(path), {
        method,
        body,
        headers: { Authorization: `Bearer ${this.token}`, ...headers },
        signal: controller.signal,
        credentials: 'omit',
        cache: 'no-store',
        redirect: 'error',
      });
      if (!response.ok)
        throw new APIError(
          response.status,
          headerRevision(response.headers.get('X-State-Revision')),
          await errorReason(response),
          headerRetryAfter(response.headers.get('Retry-After')),
          response.headers.get('X-Reva-Gemini-Fallback') === 'true',
        );
      return { bytes: await boundedBytes(response, limit), headers: response.headers };
    } catch (error) {
      if (signal?.aborted)
        throw new DOMException('The request was canceled. Your saved audio was kept.', 'AbortError');
      if (controller.signal.aborted)
        throw new APIError(
          504,
          null,
          'The server request timed out. Your saved data and original audio were kept.',
        );
      throw error;
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', cancel);
    }
  }
  private async json(
    path: string,
    method = 'GET',
    value?: unknown,
    timeout?: number,
    signal?: AbortSignal,
    headers: Record<string, string> = {},
  ): Promise<Record<string, unknown>> {
    const body = value === undefined ? undefined : JSON.stringify(value);
    if (body && new TextEncoder().encode(body).byteLength > MAX_SNAPSHOT_BYTES)
      throw new Error('The snapshot exceeds the server’s 4 MiB limit.');
    const { bytes } = await this.send(
      path,
      method,
      body,
      { 'Content-Type': 'application/json', ...headers },
      MAX_SNAPSHOT_BYTES,
      timeout,
      signal,
    );
    return object(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)));
  }

  private async gemini(path: string, value: unknown, signal?: AbortSignal, options?: GeminiRequestOptions) {
    return retryGemini(
      (fallbackOnly) =>
        this.json(
          path,
          'POST',
          value,
          80_000,
          signal,
          fallbackOnly ? { 'X-Reva-Gemini-Fallback': 'true' } : {},
        ),
      signal,
      options?.onRetry,
    );
  }

  // MARK: - Revision-bearing state and configuration discovery.
  async health(): Promise<string> {
    const result = await this.json('/health');
    if (result.status !== 'ok' || !['local', 'postgres'].includes(String(result.storage)))
      throw new Error('The server did not report healthy supported storage.');
    return `Connected · ${result.storage}`;
  }
  async providers(): Promise<ProviderStatus> {
    const result = await this.json('/v1/providers');
    const capabilities = {} as ProviderStatus;
    for (const key of ['gemini', 'transcription'] as const) {
      const item = object(result[key]);
      if (typeof item.configured !== 'boolean') throw new Error('Provider availability was unreadable.');
      capabilities[key] = { configured: item.configured, model: string(item.model) };
    }
    if (result.realtimeTranscription !== undefined) {
      const live = object(result.realtimeTranscription);
      if (typeof live.configured !== 'boolean')
        throw new Error('Live transcription availability was unreadable.');
      capabilities.realtimeTranscription = { configured: live.configured, model: string(live.model) };
    }
    return capabilities;
  }
  async realtimeTranscriptionToken(signal?: AbortSignal): Promise<string> {
    const result = await this.json('/v1/audio/realtime-token', 'POST', undefined, 15_000, signal);
    if (typeof result.token !== 'string' || !/^[!-~]{1,8192}$/.test(result.token))
      throw new Error('The live transcription session could not be opened.');
    return result.token;
  }
  async pull(): Promise<ServerState> {
    const result = await this.json('/v1/state');
    return { revision: revision(result.revision), snapshot: validateSnapshot(result.snapshot) };
  }
  async push(snapshot: AppSnapshot, baseRevision: number): Promise<number> {
    return revision(
      (
        await this.json('/v1/state', 'PUT', {
          baseRevision: revision(baseRevision),
          snapshot: validateSnapshot(snapshot),
        })
      ).revision,
    );
  }
  async deleteState(): Promise<number> {
    return revision((await this.json('/v1/state', 'DELETE')).revision);
  }

  // MARK: - Original bytes use the same SHA256 filename IDs as the native client.
  // Vercel requests are bounded; staging chunks keeps the existing 16 MiB original limit.
  private async stageLargeBlob(blob: Blob, signal?: AbortSignal): Promise<string | undefined> {
    if (!this.chunkedTransfers || blob.size <= 3 * 1024 * 1024) return undefined;
    const id = crypto.randomUUID();
    for (let offset = 0; offset < blob.size; offset += 3 * 1024 * 1024) {
      await this.send(
        `/v1/transfers/${id}?offset=${offset}&total=${blob.size}`,
        'PUT',
        blob.slice(offset, offset + 3 * 1024 * 1024),
        { 'Content-Type': 'application/octet-stream' },
        MAX_SNAPSHOT_BYTES,
        25_000,
        signal,
      );
    }
    return id;
  }
  async uploadAttachment(filename: string, blob: Blob): Promise<void> {
    if (!safeFilename(filename) || !blob.size || blob.size > MAX_ATTACHMENT_BYTES)
      throw new Error('Choose a safe original filename and a nonempty file no larger than 16 MiB.');
    const upload = await this.stageLargeBlob(blob);
    await this.send(`/v1/attachments/${await attachmentID(filename)}`, 'PUT', upload ? undefined : blob, {
      ...(upload ? { 'X-Reva-Upload': upload } : {}),
      'Content-Type': uploadContentType(blob.type),
      'X-Filename': attachmentMetadataName(filename),
    });
  }
  async attachment(filename: string): Promise<Blob> {
    if (!safeFilename(filename)) throw new Error('Invalid original filename.');
    if (this.chunkedTransfers) {
      const path = `/v1/attachments/${await attachmentID(filename)}`;
      const chunks: Uint8Array<ArrayBuffer>[] = [];
      let etag = '';
      let offset = 0,
        total = 0,
        type = 'application/octet-stream';
      do {
        const response = await this.send(
          path,
          'GET',
          undefined,
          { Range: `bytes=${offset}-${offset + 3 * 1024 * 1024 - 1}`, ...(etag ? { 'If-Match': etag } : {}) },
          3 * 1024 * 1024,
        );
        const range = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('Content-Range') ?? '');
        if (
          !range ||
          Number(range[1]) !== offset ||
          Number(range[2]) - offset + 1 !== response.bytes.length ||
          Number(range[3]) > MAX_ATTACHMENT_BYTES ||
          (total && Number(range[3]) !== total)
        )
          throw new Error('Original download changed or returned an invalid byte range.');
        total = Number(range[3]);
        const nextTag = response.headers.get('ETag');
        if (!nextTag || (etag && nextTag !== etag))
          throw new Error('Original changed during download. Please retry.');
        etag = nextTag;
        offset += response.bytes.length;
        chunks.push(response.bytes);
        type = response.headers.get('Content-Type') || type;
      } while (offset < total);
      return new Blob(chunks, { type });
    }
    const { bytes, headers } = await this.send(
      `/v1/attachments/${await attachmentID(filename)}`,
      'GET',
      undefined,
      {},
      MAX_ATTACHMENT_BYTES,
    );
    if (!bytes.byteLength) throw new Error('The server returned an empty original.');
    return new Blob([bytes], { type: headers.get('Content-Type') ?? 'application/octet-stream' });
  }
  async deleteAttachment(filename: string): Promise<void> {
    if (!safeFilename(filename)) throw new Error('Invalid original filename.');
    await this.send(`/v1/attachments/${await attachmentID(filename)}`, 'DELETE');
  }

  // MARK: - Provider DTOs contain only reviewed inputs and validated returned fields.
  async summarize(
    record: MedicalRecord,
    signal?: AbortSignal,
    options?: GeminiRequestOptions,
  ): Promise<AISummary> {
    const result = await this.gemini(
      '/v1/ai/summarize',
      {
        recordID: record.id,
        title: record.title,
        text: record.text,
        date: options?.date ?? recordDateContext(record),
        ...(options?.generateTitle ? { generateTitle: true } : {}),
      },
      signal,
      options,
    );
    const title = result.title === undefined ? undefined : string(result.title).trim();
    if (
      options?.generateTitle &&
      (!title || new TextEncoder().encode(title).byteLength > 120 || /[\r\n\u2013\u2014]/u.test(title))
    )
      throw new Error('The generated session title was invalid. Your original recording was kept.');
    return { summary: string(result.summary), model: string(result.model), ...(title ? { title } : {}) };
  }
  async medicalProfile(records: ProfileSource[], signal?: AbortSignal) {
    validateProfileSources(records);
    return validateProfileResult(await this.gemini('/v1/ai/profile', { records }, signal), records);
  }
  async prepare(visit: Visit, records: MedicalRecord[], signal?: AbortSignal): Promise<AIPreparation> {
    const result = await this.gemini(
      '/v1/ai/prepare',
      {
        visit: {
          id: visit.id,
          type: visit.type,
          concern: visit.concern,
          goal: visit.goal,
          questions: visit.questions,
        },
        records: records.map((record) => ({
          id: record.id,
          title: record.title,
          date: recordDateContext(record),
          text: record.text,
          summary: record.summary,
          version: record.version,
        })),
      },
      signal,
    );
    return {
      overview: string(result.overview),
      questions: strings(result.questions),
      selectedRecordIDs: strings(result.selectedRecordIDs),
      model: string(result.model),
    };
  }
  async transcribe(filename: string, audio: Blob, signal?: AbortSignal): Promise<AudioTranscription> {
    if (!safeFilename(filename) || !audio.size || audio.size > MAX_ATTACHMENT_BYTES)
      throw new Error('Saved audio must be nonempty and no larger than 16 MiB.');
    const upload = await this.stageLargeBlob(audio, signal);
    const { bytes } = await this.send(
      '/v1/audio/transcribe',
      'POST',
      upload ? undefined : audio,
      {
        'Content-Type': audio.type.split(';')[0],
        'X-Filename': attachmentMetadataName(filename),
        ...(upload ? { 'X-Reva-Upload': upload } : {}),
      },
      MAX_SNAPSHOT_BYTES,
      110_000,
      signal,
    );
    const result = object(JSON.parse(new TextDecoder().decode(bytes)));
    if (!Array.isArray(result.segments) || result.segments.length > 5000)
      throw new Error('The transcript contained an invalid segment list.');
    const segments = result.segments.map((raw) => {
      const segment = object(raw);
      if (
        typeof segment.start !== 'number' ||
        typeof segment.end !== 'number' ||
        !Number.isFinite(segment.start) ||
        !Number.isFinite(segment.end) ||
        segment.start < 0 ||
        segment.end < segment.start
      )
        throw new Error('The transcript contained invalid timestamps.');
      return {
        id: string(segment.id),
        speaker: string(segment.speaker),
        text: string(segment.text),
        start: segment.start,
        end: segment.end,
      };
    });
    return { text: string(result.text), segments, model: string(result.model) };
  }
}
