// Purpose: Exchange bounded native-compatible payloads with the same-origin Swift API.
// Inputs: A session-only owner token, reviewed snapshots, sources and call requests.
// Outputs: Validated responses or explicit HTTP, empty-state and conflict failures.
// Side effects: Same-origin HTTP only; never stores credentials or resolves a conflict automatically.
import type {
  AISummary,
  AIPreparation,
  AppSnapshot,
  AudioTranscription,
  LiveCallInput,
  LiveCallResult,
  MedicalRecord,
  ProviderStatus,
  ServerState,
  Visit,
} from './models.ts';
import { safeFilename, sha256, validateSnapshot } from './domain.ts';

// MARK: - Shared transfer limits, attachment identity and portable metadata.
export const MAX_ATTACHMENT_BYTES = 16 * 1024 * 1024;
export const MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024;
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
export class APIError extends Error {
  readonly status: number;
  readonly revision: number | null;
  constructor(status: number, revision: number | null = null) {
    super(
      status === 409
        ? 'The server changed. Your browser copy was kept. Pull and review its latest copy before pushing again.'
        : status === 404
          ? 'This server identity has no saved state or the requested item is unavailable.'
          : status === 401
            ? 'The server did not accept this workspace token.'
            : status === 503
              ? 'This connected service is not configured or is unavailable. Your saved data was kept.'
              : `The server returned HTTP ${status}. Your saved data was kept.`,
    );
    this.name = 'APIError';
    this.status = status;
    this.revision = revision;
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
export class RevaAPI {
  private readonly token: string;
  private readonly fetcher: typeof fetch;
  constructor(token: string, fetcher: typeof fetch = globalThis.fetch.bind(globalThis)) {
    if (!token.trim() || /[\r\n]/.test(token)) throw new Error('Enter a nonempty workspace token.');
    this.token = token;
    this.fetcher = fetcher;
  }
  private async send(
    path: string,
    method = 'GET',
    body?: BodyInit,
    headers: Record<string, string> = {},
    limit = MAX_SNAPSHOT_BYTES,
    timeout = 25_000,
  ) {
    const controller = new AbortController(),
      timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await this.fetcher(path, {
        method,
        body,
        headers: { Authorization: `Bearer ${this.token}`, ...headers },
        signal: controller.signal,
        credentials: 'omit',
        cache: 'no-store',
        redirect: 'error',
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new APIError(response.status, headerRevision(response.headers.get('X-State-Revision')));
      }
      return { bytes: await boundedBytes(response, limit), headers: response.headers };
    } catch (error) {
      if (controller.signal.aborted)
        throw new Error(
          'The server request timed out. Saved data was kept; a live call may still be running. Check its existing request before trying again.',
        );
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }
  private async json(
    path: string,
    method = 'GET',
    value?: unknown,
    timeout?: number,
  ): Promise<Record<string, unknown>> {
    const body = value === undefined ? undefined : JSON.stringify(value);
    if (body && new TextEncoder().encode(body).byteLength > MAX_SNAPSHOT_BYTES)
      throw new Error('The snapshot exceeds the server’s 4 MiB limit.');
    const { bytes } = await this.send(
      path,
      method,
      body,
      { 'Content-Type': 'application/json' },
      MAX_SNAPSHOT_BYTES,
      timeout,
    );
    return object(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)));
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
    for (const key of ['gemini', 'transcription', 'booking']) {
      const item = object(result[key]);
      if (typeof item.configured !== 'boolean') throw new Error('Provider availability was unreadable.');
      string(item.model);
    }
    if (typeof result.liveCallsEnabled !== 'boolean') throw new Error('Call availability was unreadable.');
    return result as unknown as ProviderStatus;
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
  async uploadAttachment(filename: string, blob: Blob): Promise<void> {
    if (!safeFilename(filename) || !blob.size || blob.size > MAX_ATTACHMENT_BYTES)
      throw new Error('Choose a safe original filename and a nonempty file no larger than 16 MiB.');
    await this.send(`/v1/attachments/${await attachmentID(filename)}`, 'PUT', blob, {
      'Content-Type': uploadContentType(blob.type),
      'X-Filename': attachmentMetadataName(filename),
    });
  }
  async attachment(filename: string): Promise<Blob> {
    if (!safeFilename(filename)) throw new Error('Invalid original filename.');
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
  async summarize(record: MedicalRecord): Promise<AISummary> {
    const result = await this.json(
      '/v1/ai/summarize',
      'POST',
      { recordID: record.id, title: record.title, text: record.text },
      80_000,
    );
    return { summary: string(result.summary), model: string(result.model) };
  }
  async prepare(visit: Visit, records: MedicalRecord[]): Promise<AIPreparation> {
    const result = await this.json(
      '/v1/ai/prepare',
      'POST',
      {
        visit: {
          id: visit.id,
          type: visit.type,
          concern: visit.concern,
          goal: visit.goal,
          questions: visit.questions,
        },
        records: records.map(({ id, title, date, text, summary, version }) => ({
          id,
          title,
          date,
          text,
          summary,
          version,
        })),
      },
      80_000,
    );
    return {
      overview: string(result.overview),
      questions: strings(result.questions),
      selectedRecordIDs: strings(result.selectedRecordIDs),
      model: string(result.model),
    };
  }
  async transcribe(filename: string, audio: Blob): Promise<AudioTranscription> {
    if (!safeFilename(filename) || !audio.size || audio.size > MAX_ATTACHMENT_BYTES)
      throw new Error('Saved audio must be nonempty and no larger than 16 MiB.');
    const { bytes } = await this.send(
      '/v1/audio/transcribe',
      'POST',
      audio,
      { 'Content-Type': audio.type.split(';')[0], 'X-Filename': attachmentMetadataName(filename) },
      MAX_SNAPSHOT_BYTES,
      110_000,
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
  private callResult(result: Record<string, unknown>): LiveCallResult {
    return {
      conversationID: string(result.conversationID),
      status: string(result.status),
      provider: string(result.provider),
      transcript: result.transcript == null ? undefined : string(result.transcript),
    };
  }
  async startCall(request: LiveCallInput): Promise<LiveCallResult> {
    return this.callResult(await this.json('/v1/booking/call', 'POST', request, 110_000));
  }
  async callStatus(requestID: string): Promise<LiveCallResult> {
    if (!requestID || requestID.length > 128) throw new Error('Invalid saved call request identity.');
    return this.callResult(
      await this.json(`/v1/booking/call/${encodeURIComponent(requestID)}`, 'GET', undefined, 110_000),
    );
  }
}
