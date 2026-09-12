// Purpose: Exercise mixed PDF extraction with raster evidence despite a substantial embedded header.
// Inputs: Synthetic PDF page adapters and injected local OCR responses under existing extraction limits.
// Outputs: Assertions for retained raster words, exact embedded pages, uncertainty, cancellation, and cleanup.
// Side effects: Stubbed PDF/OCR workers and canvas only; no assets, patient documents, or providers are read.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { extractDocument } from './extractDocument';

const adapters = vi.hoisted(() => ({ getDocument: vi.fn(), createWorker: vi.fn() }));
vi.mock('pdfjs-dist/build/pdf.worker.min.mjs?url', () => ({ default: '/synthetic-pdf-worker.mjs' }));
vi.mock('pdfjs-dist', () => ({
  getDocument: adapters.getDocument,
  GlobalWorkerOptions: {},
  OPS: {
    paintImageXObject: 1,
    paintImageXObjectRepeat: 2,
    paintInlineImageXObject: 3,
    paintInlineImageXObjectGroup: 4,
    paintImageMaskXObject: 5,
    paintImageMaskXObjectGroup: 6,
    paintImageMaskXObjectRepeat: 7,
  },
}));
vi.mock('tesseract.js', () => ({ createWorker: adapters.createWorker }));
const header = 'Fictional regional clinic laboratory report for synthetic patient';
function pdfPage(text: string, raster = false) {
  return {
    getTextContent: vi.fn(async () => ({ items: [{ str: text, hasEOL: true }] })),
    getOperatorList: vi.fn(async () => ({ fnArray: raster ? [1] : [], argsArray: [] })),
    getViewport: vi.fn(({ scale }: { scale: number }) => ({ width: 600 * scale, height: 800 * scale })),
    render: vi.fn(() => ({ promise: Promise.resolve(), cancel: vi.fn() })),
    cleanup: vi.fn(),
  };
}
function source(pages: ReturnType<typeof pdfPage>[], recognized = `${header}\nRASTER-LAB-418 potassium 4.1`) {
  const terminate = vi.fn(async () => {});
  const recognize = vi.fn(async () => ({ data: { text: recognized, confidence: 95 } }));
  adapters.createWorker.mockResolvedValue({ recognize, terminate });
  const destroy = vi.fn(async () => {});
  adapters.getDocument.mockReturnValue({
    promise: Promise.resolve({ numPages: pages.length, getPage: async (page: number) => pages[page - 1] }),
    destroy,
  });
  return { recognize, terminate, destroy };
}
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('window', { setTimeout, clearTimeout });
  vi.stubGlobal('location', { origin: 'http://localhost' });
  vi.stubGlobal('document', { createElement: () => ({ width: 0, height: 0 }) });
});
afterEach(() => vi.unstubAllGlobals());
const file = () => new File(['unchanged synthetic PDF bytes'], 'mixed.pdf', { type: 'application/pdf' });

// MARK: - Text length cannot certify completeness when the same page paints a raster scan
describe('mixed PDF page extraction', () => {
  it('reads a raster body below a long embedded header without duplicating that header', async () => {
    const page = pdfPage(header, true);
    const worker = source([page]);
    const original = file();
    const result = await extractDocument(original, new AbortController().signal, () => {});
    expect(result.pageTexts).toEqual([`${header}\nRASTER-LAB-418 potassium 4.1`]);
    expect(result.text.match(/Fictional regional/g)).toHaveLength(1);
    expect(result.usedOCR).toBe(true);
    expect(result.incomplete).toBe(false);
    expect(page.render).toHaveBeenCalledOnce();
    expect(worker.terminate).toHaveBeenCalledOnce();
    expect(worker.destroy).toHaveBeenCalledOnce();
    expect(page.cleanup).toHaveBeenCalledOnce();
    expect(await original.text()).toBe('unchanged synthetic PDF bytes');
  });

  it('preserves exact text and page mapping for ordinary embedded-text PDFs without OCR', async () => {
    const pages = [
      pdfPage(`${header}\nFirst exact source page.`),
      pdfPage(`${header}\nSecond exact source page.`),
    ];
    const worker = source(pages);
    const result = await extractDocument(file(), new AbortController().signal, () => {});
    expect(result.pageTexts).toEqual([
      `${header}\nFirst exact source page.`,
      `${header}\nSecond exact source page.`,
    ]);
    expect(result.pageCount).toBe(2);
    expect(result.usedOCR).toBe(false);
    expect(result.incomplete).toBe(false);
    expect(result.warnings).toEqual([]);
    expect(adapters.createWorker).not.toHaveBeenCalled();
    expect(worker.destroy).toHaveBeenCalledOnce();
  });

  it('retains embedded evidence and marks the page incomplete when its raster OCR fails', async () => {
    const page = pdfPage(header, true);
    const worker = source([page]);
    worker.recognize.mockRejectedValue(new Error('Synthetic OCR unavailable.'));
    const result = await extractDocument(file(), new AbortController().signal, () => {});
    expect(result.pageTexts).toEqual([header]);
    expect(result.incomplete).toBe(true);
    expect(result.warnings.some((warning) => warning.includes('Page 1: Synthetic OCR unavailable'))).toBe(
      true,
    );
    expect(worker.terminate).toHaveBeenCalledOnce();
  });

  it('marks an unreadable raster as incomplete even when the embedded header is readable', async () => {
    source([pdfPage(header, true)], '');
    const result = await extractDocument(file(), new AbortController().signal, () => {});
    expect(result.pageTexts).toEqual([header]);
    expect(result.incomplete).toBe(true);
    expect(
      result.warnings.some((warning) => warning.includes('Image content yielded no readable text')),
    ).toBe(true);
  });

  it('attempts OCR and discloses uncertainty when image coverage inspection fails', async () => {
    const page = pdfPage(header);
    page.getOperatorList.mockRejectedValue(new Error('Synthetic operator failure.'));
    source([page]);
    const result = await extractDocument(file(), new AbortController().signal, () => {});
    expect(result.text).toContain('RASTER-LAB-418');
    expect(result.incomplete).toBe(true);
    expect(result.warnings.some((warning) => warning.includes('Image coverage could not be checked'))).toBe(
      true,
    );
  });

  it('cancels pending OCR and releases the PDF page without publishing partial text', async () => {
    const page = pdfPage(header, true);
    const worker = source([page]);
    worker.recognize.mockImplementation(() => new Promise(() => {}));
    const controller = new AbortController();
    const reading = extractDocument(file(), controller.signal, () => {});
    const rejected = expect(reading).rejects.toMatchObject({ name: 'AbortError' });
    await vi.waitFor(() => expect(worker.recognize).toHaveBeenCalledOnce());
    controller.abort();
    await rejected;
    expect(worker.terminate).toHaveBeenCalled();
    expect(worker.destroy).toHaveBeenCalled();
    expect(page.cleanup).toHaveBeenCalledOnce();
  });
});
