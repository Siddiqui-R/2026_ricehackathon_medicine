// Purpose: Extract reviewable source text locally while retaining the original upload unchanged.
// Inputs: One bounded File, an abort signal, and a progress callback; OCR assets come from this app.
// Outputs: Text, page mapping, and explicit incomplete/uncertain extraction warnings.
// Side effects: Runs one PDF worker and at most one local OCR worker; releases them when finished/cancelled.

import type { PDFDocumentLoadingTask, RenderTask } from 'pdfjs-dist';
import pdfWorkerURL from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import type { Worker as OCRWorker } from 'tesseract.js';

// MARK: - Shared resource limits and UTF-8-safe excerpt bounds
export const MAX_FILE_BYTES = 16 * 1024 * 1024;
export const MAX_TEXT_BYTES = 120_000;
const MAX_PAGES = 24;
const MAX_OCR_PAGES = 10;
const MAX_CANVAS_SIDE = 2200;
const encoder = new TextEncoder();

export interface ExtractionResult {
  text: string;
  pageTexts: string[];
  pageCount: number;
  warnings: string[];
  incomplete: boolean;
  usedOCR: boolean;
}
export function textByteCount(text: string) {
  return encoder.encode(text).length;
}
export function boundedText(text: string, maximum = MAX_TEXT_BYTES) {
  const bytes = encoder.encode(text);
  if (bytes.length <= maximum) return text;
  let end = maximum;
  while (end > 0 && (bytes[end] & 0xc0) === 0x80) end--;
  return new TextDecoder().decode(bytes.slice(0, end));
}
function mergeRecognizedText(embedded: string, recognized: string): string {
  if (!embedded) return recognized;
  const normalized = (line: string) => line.trim().replace(/\s+/g, ' ');
  const known = new Set(embedded.split(/\r?\n/).map(normalized));
  const additional = recognized
    .split(/\r?\n/)
    .filter((line) => !known.has(normalized(line)))
    .join('\n')
    .trim();
  return additional ? `${embedded}\n${additional}` : embedded;
}
function checkAbort(signal: AbortSignal) {
  if (signal.aborted) throw new DOMException('Extraction cancelled.', 'AbortError');
}
// Worker termination does not reject Tesseract's pending job promise, so race it explicitly.
function localWork<T>(work: Promise<T>, signal: AbortSignal, milliseconds: number): Promise<T> {
  checkAbort(signal);
  return new Promise((resolve, reject) => {
    const cancel = () => {
      cleanup();
      reject(new DOMException('Extraction cancelled.', 'AbortError'));
    };
    const timer = window.setTimeout(
      () => {
        cleanup();
        reject(new Error('Local reading reached its time limit. The original can be saved for review.'));
      },
      Math.max(1, milliseconds),
    );
    const cleanup = () => {
      window.clearTimeout(timer);
      signal.removeEventListener('abort', cancel);
    };
    signal.addEventListener('abort', cancel, { once: true });
    work.then(
      (value) => {
        cleanup();
        resolve(value);
      },
      (reason) => {
        cleanup();
        reject(reason);
      },
    );
  });
}
export function sourceType(file: File) {
  if (/\.pdf$/i.test(file.name) || file.type === 'application/pdf') return 'application/pdf';
  if (/\.(txt|md)$/i.test(file.name) || file.type.startsWith('text/')) return 'text/plain';
  if (file.type.startsWith('image/')) return file.type;
  const suffix = file.name.split('.').pop()?.toLowerCase();
  return (
    (
      {
        png: 'image/png',
        jpg: 'image/jpeg',
        jpeg: 'image/jpeg',
        webp: 'image/webp',
        heic: 'image/heic',
      } as Record<string, string>
    )[suffix ?? ''] ?? 'application/octet-stream'
  );
}

// MARK: - Browser image decoding with explicit dimension bounds and object-URL cleanup
async function imageCanvas(file: File, signal: AbortSignal) {
  const url = URL.createObjectURL(file);
  const image = new Image();
  try {
    await localWork(
      new Promise<void>((resolve, reject) => {
        const cancel = () => {
          image.src = '';
          reject(new DOMException('Extraction cancelled.', 'AbortError'));
        };
        signal.addEventListener('abort', cancel, { once: true });
        image.onload = () => {
          signal.removeEventListener('abort', cancel);
          resolve();
        };
        image.onerror = () => {
          signal.removeEventListener('abort', cancel);
          reject(new Error('This browser could not read the image. Try a JPEG or PNG copy.'));
        };
        image.src = url;
      }),
      signal,
      30_000,
    );
    checkAbort(signal);
    if (
      !image.naturalWidth ||
      !image.naturalHeight ||
      image.naturalWidth * image.naturalHeight > 40_000_000
    ) {
      throw new Error('This image is too large to read locally. Use a smaller copy of up to 40 megapixels.');
    }
    const scale = Math.min(1, MAX_CANVAS_SIDE / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(image.naturalWidth * scale);
    canvas.height = Math.ceil(image.naturalHeight * scale);
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Image reading is unavailable in this browser.');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas;
  } finally {
    URL.revokeObjectURL(url);
    image.src = '';
  }
}

// MARK: - Sequential extraction and a single locally configured OCR worker
export async function extractDocument(
  file: File,
  signal: AbortSignal,
  progress: (message: string) => void,
): Promise<ExtractionResult> {
  if (!file.size || file.size > MAX_FILE_BYTES) throw new Error('Choose a nonempty file of up to 16 MB.');
  const result: ExtractionResult = {
    text: '',
    pageTexts: [],
    pageCount: 1,
    warnings: [],
    incomplete: false,
    usedOCR: false,
  };
  let worker: OCRWorker | undefined;
  let loading: PDFDocumentLoadingTask | undefined;
  let rendering: RenderTask | undefined;
  let pageLabel = '';
  let textLimitReached = false;
  let closed = false;
  let ocrFailure: Error | undefined;
  let ocrPages = 0;
  const deadline = Date.now() + 180_000;
  const remainingTime = (limit: number) => Math.min(limit, Math.max(1, deadline - Date.now()));
  const cancel = () => {
    rendering?.cancel();
    void loading?.destroy().catch(() => {});
    void worker?.terminate().catch(() => {});
  };
  signal.addEventListener('abort', cancel, { once: true });
  const readImage = async (canvas: HTMLCanvasElement) => {
    checkAbort(signal);
    result.usedOCR = true;
    if (ocrFailure) throw ocrFailure;
    if (!worker) {
      progress('Preparing local text recognition…');
      const { createWorker } = await localWork(import('tesseract.js'), signal, remainingTime(30_000));
      checkAbort(signal);
      const ready = createWorker('eng', 1, {
        workerPath: new URL('/ocr/worker.min.js', location.origin).href,
        langPath: new URL('/ocr', location.origin).href,
        corePath: new URL('/ocr/core', location.origin).href,
        gzip: true,
        workerBlobURL: false,
        cacheMethod: 'none',
        logger: (message) => {
          if (!signal.aborted && message.status === 'recognizing text')
            progress(`${pageLabel}Reading scanned text · ${Math.round(message.progress * 100)}%`);
        },
        errorHandler: () => {},
      });
      // Initialization is asynchronous: if cancelled before ready, terminate as soon as its handle arrives.
      void ready
        .then((created) => {
          if (closed || signal.aborted) void created.terminate();
        })
        .catch(() => {});
      try {
        worker = await localWork(ready, signal, remainingTime(60_000));
      } catch (reason) {
        ocrFailure = reason instanceof Error ? reason : new Error('Local text recognition could not start.');
        throw ocrFailure;
      }
    }
    checkAbort(signal);
    let read;
    try {
      read = await localWork(worker.recognize(canvas, { rotateAuto: true }), signal, remainingTime(45_000));
    } catch (reason) {
      await worker.terminate().catch(() => {});
      worker = undefined;
      ocrFailure = reason instanceof Error ? reason : new Error('Local text recognition could not finish.');
      throw ocrFailure;
    }
    checkAbort(signal);
    if (read.data.confidence < 80)
      result.warnings.push(
        `${pageLabel || 'Image: '}Some words were uncertain. Compare names, dates, doses, and values with the original.`,
      );
    return read.data.text.trim();
  };
  const appendPage = (text: string) => {
    const used = textByteCount(result.pageTexts.join('\n\n'));
    const separator = result.pageTexts.length ? 2 : 0;
    const remaining = MAX_TEXT_BYTES - used - separator;
    const accepted = boundedText(text, Math.max(0, remaining));
    if (remaining >= 0) result.pageTexts.push(accepted);
    textLimitReached =
      remaining < 0 || accepted !== text || used + separator + textByteCount(accepted) >= MAX_TEXT_BYTES;
    if (remaining < 0 || accepted !== text) {
      result.incomplete = true;
      result.warnings.push(
        'Local reading stopped at 120 KB of text. The complete original is retained; this record needs review.',
      );
    }
  };
  try {
    checkAbort(signal);
    const type = sourceType(file);
    if (type === 'text/plain') {
      progress('Reading text on this device…');
      const text = new TextDecoder('utf-8', { fatal: true }).decode(
        await localWork(file.arrayBuffer(), signal, remainingTime(30_000)),
      );
      checkAbort(signal);
      appendPage(text.trim());
    } else if (type === 'application/pdf') {
      progress('Opening PDF on this device…');
      const { getDocument, GlobalWorkerOptions, OPS } = await localWork(
        import('pdfjs-dist'),
        signal,
        remainingTime(30_000),
      );
      GlobalWorkerOptions.workerSrc = pdfWorkerURL;
      checkAbort(signal);
      loading = getDocument({
        data: new Uint8Array(await localWork(file.arrayBuffer(), signal, remainingTime(30_000))),
        stopAtErrors: true,
        maxImageSize: 40_000_000,
        canvasMaxAreaInBytes: 24 * 1024 * 1024,
        useSystemFonts: true,
      });
      const pdf = await localWork(loading.promise, signal, remainingTime(30_000));
      checkAbort(signal);
      result.pageCount = pdf.numPages;
      if (pdf.numPages > MAX_PAGES) {
        result.incomplete = true;
        result.warnings.push(
          `This PDF has ${pdf.numPages} pages. Local reading covers its first ${MAX_PAGES}; the complete original is retained.`,
        );
      }
      for (let number = 1; number <= Math.min(pdf.numPages, MAX_PAGES); number++) {
        checkAbort(signal);
        if (Date.now() >= deadline) {
          result.incomplete = true;
          result.warnings.push('Local reading reached its three-minute limit. The original is retained.');
          break;
        }
        pageLabel = `Page ${number}: `;
        progress(`Reading PDF page ${number} of ${Math.min(pdf.numPages, MAX_PAGES)}…`);
        const page = await localWork(pdf.getPage(number), signal, remainingTime(15_000));
        try {
          let text = '';
          try {
            const content = await localWork(page.getTextContent(), signal, remainingTime(15_000));
            text = content.items
              .map((item) => ('str' in item ? item.str + (item.hasEOL ? '\n' : ' ') : ''))
              .join('')
              .trim();
          } catch {
            result.warnings.push(
              `Page ${number}: Embedded text could not be read; local image recognition was attempted.`,
            );
          }
          let rasterOrUnknown = true;
          try {
            const operations = await localWork(page.getOperatorList(), signal, remainingTime(15_000));
            const imageOperations = new Set([
              OPS.paintImageXObject,
              OPS.paintInlineImageXObject,
              OPS.paintImageMaskXObject,
              OPS.paintImageXObjectRepeat,
              OPS.paintInlineImageXObjectGroup,
              OPS.paintImageMaskXObjectGroup,
              OPS.paintImageMaskXObjectRepeat,
              OPS.paintSolidColorImageMask,
            ]);
            rasterOrUnknown = operations.fnArray.some((operation) => imageOperations.has(operation));
          } catch {
            checkAbort(signal);
            result.incomplete = true;
            result.warnings.push(
              `Page ${number}: Graphic content could not be inspected; review the original for missing text.`,
            );
          }
          if (text.replace(/\s/g, '').length < 35 || rasterOrUnknown) {
            if (ocrPages >= MAX_OCR_PAGES) {
              result.incomplete = true;
              result.warnings.push(
                `Page ${number}: Needs OCR beyond the ${MAX_OCR_PAGES}-page OCR limit. Review this page or import a smaller PDF.`,
              );
              appendPage(text);
              continue;
            }
            ocrPages += 1;
            const base = page.getViewport({ scale: 1 });
            const viewport = page.getViewport({
              scale: Math.min(2, MAX_CANVAS_SIDE / Math.max(base.width, base.height)),
            });
            const canvas = document.createElement('canvas');
            canvas.width = Math.ceil(viewport.width);
            canvas.height = Math.ceil(viewport.height);
            try {
              rendering = page.render({ canvas, viewport });
              await localWork(rendering.promise, signal, remainingTime(30_000));
              rendering = undefined;
              const recognized = await readImage(canvas);
              if (text && rasterOrUnknown)
                result.warnings.push(
                  `Page ${number}: Embedded text and graphics were read together. OCR text follows embedded text and may repeat it; review the complete original page.`,
                );
              if (!recognized && rasterOrUnknown) {
                result.incomplete = true;
                result.warnings.push(
                  `Page ${number}: No raster text was recognized. Review the original for missing text.`,
                );
              }
              text = mergeRecognizedText(text, recognized);
            } catch (error) {
              rendering?.cancel();
              rendering = undefined;
              checkAbort(signal);
              result.incomplete = true;
              result.warnings.push(
                `Page ${number}: Text recognition did not complete. Embedded text was retained; review the original for missing text. ${error instanceof Error ? error.message : ''}`,
              );
            } finally {
              canvas.width = 1;
              canvas.height = 1;
            }
          }
          appendPage(text);
          if (!text) {
            result.incomplete = true;
            result.warnings.push(`Page ${number}: No readable text was found.`);
          }
        } catch (error) {
          rendering?.cancel();
          rendering = undefined;
          checkAbort(signal);
          appendPage('');
          result.incomplete = true;
          result.warnings.push(
            `Page ${number}: ${error instanceof Error ? error.message : 'Text could not be extracted.'}`,
          );
        } finally {
          page.cleanup();
        }
        if (textLimitReached) {
          if (number < pdf.numPages) {
            result.incomplete = true;
            result.warnings.push(
              'Later pages were not read because the 120 KB text limit was reached. The complete original is retained.',
            );
          }
          break;
        }
      }
    } else if (type.startsWith('image/')) {
      const canvas = await imageCanvas(file, signal);
      try {
        appendPage(await readImage(canvas));
      } finally {
        canvas.width = 1;
        canvas.height = 1;
      }
    } else {
      throw new Error(
        'Automatic reading supports PDF, text, and images. You can retain this original and enter its text manually.',
      );
    }
  } catch (error) {
    checkAbort(signal);
    result.incomplete = true;
    result.warnings.push(
      error instanceof Error
        ? error.message
        : 'The source could not be read. Enter text or save the original for later review.',
    );
  } finally {
    closed = true;
    signal.removeEventListener('abort', cancel);
    await worker?.terminate().catch(() => {});
    await loading?.destroy().catch(() => {});
  }
  result.text = result.pageTexts.join('\n\n');
  if (!result.text.trim()) {
    result.incomplete = true;
    result.warnings.push(
      'No readable text yet. You can add a transcription or save the original for later review.',
    );
  }
  if (result.usedOCR)
    result.warnings.push(
      'Text recognition ran locally in English. Review it against the original; handwriting and obscured text may be inaccurate.',
    );
  result.warnings = [...new Set(result.warnings)];
  return result;
}
