// Purpose: Verify original previews render real PDF content without a browser plug-in.
// Inputs: Fictional scanned and multipage PDFs plus malformed and cancelled requests.
// Outputs: Assertions for visible pixels, actual page bounds and safe failure.
// Side effects: Reads local fixtures and runs PDF.js with a native test canvas; no network.
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { createCanvas } from '@napi-rs/canvas';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

// MARK: - Real PDF.js with a Node-compatible worker and canvas
vi.mock('pdfjs-dist', async () => {
  const actual = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const require = createRequire(import.meta.url);
  actual.GlobalWorkerOptions.workerSrc = pathToFileURL(
    require.resolve('pdfjs-dist/legacy/build/pdf.worker.mjs'),
  ).href;
  return {
    GlobalWorkerOptions: {},
    getDocument: (options: object) => actual.getDocument({ ...options, disableFontFace: true }),
  };
});
import { renderPDFPage } from './renderPDFPage';
beforeEach(() => vi.stubGlobal('document', { createElement: () => createCanvas(1, 1) }));
afterEach(() => vi.unstubAllGlobals());
async function fixture(name: string) {
  return new Blob([await readFile(new URL(`../../../../../demo/sources/${name}`, import.meta.url))], {
    type: 'application/pdf',
  });
}

// MARK: - Scanned content, navigation and failure paths
it('renders visible source pixels from an image-only PDF within the canvas bound', async () => {
  const result = await renderPDFPage(
    await fixture('reva-synthetic-symptom-diary-image-only.pdf'),
    1,
    new AbortController().signal,
  );
  expect(result.pageNumber).toBe(1);
  expect(result.pageCount).toBe(1);
  expect(Math.max(result.canvas.width, result.canvas.height)).toBeLessThanOrEqual(2200);
  const pixels = result.canvas
    .getContext('2d')!
    .getImageData(0, 0, result.canvas.width, result.canvas.height).data;
  expect(pixels.some((value, index) => index % 4 === 0 && value < 100)).toBe(true);
});
it('opens evidence page two and clamps navigation to the actual page count', async () => {
  const blob = await fixture('reva-synthetic-tibia-procedure-2019.pdf');
  const first = await renderPDFPage(blob, 1, new AbortController().signal);
  const second = await renderPDFPage(blob, 999, new AbortController().signal);
  expect(second.pageCount).toBe(2);
  expect(second.pageNumber).toBe(2);
  const pixels = (canvas: HTMLCanvasElement) =>
    canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data;
  expect(pixels(first.canvas)).not.toEqual(pixels(second.canvas));
});
it('rejects malformed PDFs so the UI can offer the original download', async () => {
  await expect(renderPDFPage(new Blob(['not a PDF']), 1, new AbortController().signal)).rejects.toThrow();
});
it('rejects a dismissed preview before reading its bytes', async () => {
  const blob = new Blob(['unused']);
  const read = vi.spyOn(blob, 'arrayBuffer');
  const controller = new AbortController();
  controller.abort();
  await expect(renderPDFPage(blob, 1, controller.signal)).rejects.toThrow();
  expect(read).not.toHaveBeenCalled();
});
it('settles cancellation while original bytes are still loading', async () => {
  const blob = new Blob(['unused']);
  let finish: (buffer: ArrayBuffer) => void = () => {};
  const read = vi.spyOn(blob, 'arrayBuffer').mockImplementation(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  const controller = new AbortController();
  const pending = renderPDFPage(blob, 1, controller.signal);
  const assertion = expect(pending).rejects.toThrow();
  await vi.waitFor(() => expect(read).toHaveBeenCalled());
  controller.abort();
  await assertion;
  finish(new ArrayBuffer(0));
});
