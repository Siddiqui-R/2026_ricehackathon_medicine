// Bundled display copies keep fixture labels out of the viewer without rewriting stored originals.
import manifest from '../../../assets/source-previews/manifest.json';
import type { MedicalRecord } from '../../core/models';

interface PreviewSource {
  recordID: string;
  mimeType: string;
  bytes: number;
  sha256: string;
}
export function demoSourcePreview(record: MedicalRecord): PreviewSource | undefined {
  if (!record.isDemo || !record.sourceFilename) return undefined;
  const source = (manifest as Record<string, PreviewSource>)[record.sourceFilename];
  return source?.recordID === record.id && source.mimeType === record.mimeType ? source : undefined;
}
export async function loadDemoSourcePreview(filename: string, source: PreviewSource): Promise<Blob> {
  const response = await fetch(`/source-previews/${encodeURIComponent(filename)}`, { credentials: 'omit' });
  if (!response.ok) throw new Error('The source document could not be loaded. Please try again.');
  const bytes = await response.arrayBuffer();
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
  if (bytes.byteLength !== source.bytes || hash !== source.sha256)
    throw new Error('The source document could not be verified. Refresh the page and try again.');
  return new Blob([bytes], { type: source.mimeType });
}
