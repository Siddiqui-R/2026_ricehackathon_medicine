// Purpose: Render original PDF bytes without relying on a browser PDF plug-in.
// Inputs: An original blob, one-based page number and cancellation signal.
// Outputs: A bounded canvas and page coordinates from the actual PDF.
// Side effects: Runs a scoped PDF.js worker and releases it after rendering or cancellation.
import type { PDFDocumentLoadingTask, RenderTask } from 'pdfjs-dist';
import pdfWorkerURL from 'pdfjs-dist/build/pdf.worker.min.mjs?url';

// MARK: - Bounded rendering and worker lifetime
export async function renderPDFPage(blob: Blob, requestedPage: number, signal: AbortSignal) {
  if (!blob.size || blob.size > 16 * 1024 * 1024)
    throw new Error('PDF previews support nonempty files up to 16 MB.');
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(30_000)]);
  deadline.throwIfAborted();
  let loading: PDFDocumentLoadingTask | undefined;
  let rendering: RenderTask | undefined;
  let rejectAbort: (reason: unknown) => void = () => {};
  const aborted = new Promise<never>((_, reject) => {
    rejectAbort = reject;
  });
  const cancel = () => {
    rendering?.cancel();
    rejectAbort(deadline.reason);
  };
  deadline.addEventListener('abort', cancel, { once: true });
  try {
    return await Promise.race([
      aborted,
      (async () => {
        const pdfjs = await import('pdfjs-dist');
        const data = new Uint8Array(await blob.arrayBuffer());
        deadline.throwIfAborted();
        pdfjs.GlobalWorkerOptions.workerSrc = pdfWorkerURL;
        loading = pdfjs.getDocument({
          data,
          stopAtErrors: true,
          useSystemFonts: true,
          maxImageSize: 40_000_000,
          canvasMaxAreaInBytes: 24 * 1024 * 1024,
        });
        const pdf = await loading.promise;
        deadline.throwIfAborted();
        const pageNumber = Math.max(
          1,
          Math.min(pdf.numPages, Number.isFinite(requestedPage) ? Math.trunc(requestedPage) : 1),
        );
        const page = await pdf.getPage(pageNumber);
        deadline.throwIfAborted();
        const original = page.getViewport({ scale: 1 });
        const scale = Math.min(1.5, 2200 / Math.max(original.width, original.height));
        const viewport = page.getViewport({ scale });
        const canvas = document.createElement('canvas');
        canvas.width = Math.ceil(viewport.width);
        canvas.height = Math.ceil(viewport.height);
        rendering = page.render({ canvas, viewport });
        await rendering.promise;
        deadline.throwIfAborted();
        return { canvas, pageNumber, pageCount: pdf.numPages };
      })(),
    ]);
  } finally {
    deadline.removeEventListener('abort', cancel);
    // Destruction also settles document/page loading when cancellation wins the race.
    if (loading) await loading.destroy();
  }
}
