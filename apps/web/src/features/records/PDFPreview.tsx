// Purpose: Show original PDF pages within the application under its existing security policy.
// Inputs: Original PDF bytes, title and an optional evidence page.
// Outputs: Accessible page controls, rendered source pages and explicit preview failures.
// Side effects: Cancels obsolete rendering on navigation, replacement or dismissal.
import { useEffect, useRef, useState } from 'react';
import { renderPDFPage } from './renderPDFPage';

// MARK: - Original page navigation and stale-render protection
export function PDFPreview({ blob, title, page = 1 }: { blob: Blob; title: string; page?: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [requested, setRequested] = useState(page);
  const [position, setPosition] = useState({ pageNumber: 1, pageCount: 0 });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    setRequested(page);
  }, [blob, page]);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError('');
    void renderPDFPage(blob, requested, controller.signal)
      .then((result) => {
        if (controller.signal.aborted || !canvas.current) return;
        const target = canvas.current;
        target.width = result.canvas.width;
        target.height = result.canvas.height;
        const context = target.getContext('2d');
        if (!context) throw new Error('Canvas rendering is unavailable.');
        context.drawImage(result.canvas, 0, 0);
        setPosition({ pageNumber: result.pageNumber, pageCount: result.pageCount });
        setLoading(false);
      })
      .catch(() => {
        if (controller.signal.aborted) return;
        setError('This PDF could not be previewed. Download the original to open it.');
        setLoading(false);
      });
    return () => controller.abort();
  }, [blob, requested]);
  return (
    <div className="stack pdf-preview">
      {loading && <p role="status">Rendering original PDF…</p>}
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
      <canvas
        ref={canvas}
        hidden={loading || !!error}
        role="img"
        aria-label={`Original PDF page ${position.pageNumber} of ${position.pageCount}: ${title}`}
      />
      {position.pageCount > 0 && (
        <div className="pdf-page-controls" aria-label="PDF page navigation">
          <button
            type="button"
            className="button button-secondary"
            disabled={loading || position.pageNumber <= 1}
            onClick={() => setRequested(position.pageNumber - 1)}
          >
            Previous page
          </button>
          <span aria-live="polite">
            Page {position.pageNumber} of {position.pageCount}
          </span>
          <button
            type="button"
            className="button button-secondary"
            disabled={loading || position.pageNumber >= position.pageCount}
            onClick={() => setRequested(position.pageNumber + 1)}
          >
            Next page
          </button>
        </div>
      )}
    </div>
  );
}
