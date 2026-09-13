// Purpose: Present source documents without executing their text as HTML.
// Inputs: A record attachment reference and an optional one-based PDF evidence page.
// Outputs: PDF/image/text previews and downloads; bundled fixtures use verified display copies.
// Side effects: Reads the repository and manages a scoped blob URL that is revoked on dismissal.

import { useEffect, useState } from 'react';
import { Download, LoaderCircle } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import type { MedicalRecord } from '../../core/models';
import { Modal } from '../../components/ui';
import { boundedText, MAX_TEXT_BYTES, textByteCount } from './extractDocument';
import { PDFPreview } from './PDFPreview';
import { demoSourcePreview, loadDemoSourcePreview } from './demoSourcePreview';
import { demoLabel, demoSourceText } from '../../core/presentation';

// MARK: - Read originals with stale-load and URL lifetime protection
export function SourcePreview({
  record,
  page = 1,
  onClose,
}: {
  record: MedicalRecord;
  page?: number;
  onClose: () => void;
}) {
  const { getAttachment } = useReva();
  const [url, setURL] = useState('');
  const [originalBlob, setOriginalBlob] = useState<Blob | null>(null);
  const [text, setText] = useState('');
  const [shortened, setShortened] = useState(false);
  const [error, setError] = useState('');
  const bundledPreview = demoSourcePreview(record);
  const type = record.mimeType || 'application/octet-stream';
  useEffect(() => {
    let active = true;
    let objectURL = '';
    setURL('');
    setOriginalBlob(null);
    setText('');
    setShortened(false);
    setError('');
    void (async () => {
      try {
        if (!record.sourceFilename) throw new Error('This record has no original attachment.');
        const original = bundledPreview
          ? await loadDemoSourcePreview(record.sourceFilename, bundledPreview)
          : await getAttachment(record.sourceFilename);
        if (!active) return;
        const blob = original.type ? original : original.slice(0, original.size, type);
        objectURL = URL.createObjectURL(blob);
        setURL(objectURL);
        setOriginalBlob(blob);
        if (type.startsWith('text/')) {
          const contents = await blob.text();
          if (active) {
            setText(boundedText(contents));
            setShortened(textByteCount(contents) > MAX_TEXT_BYTES);
          }
        }
      } catch (reason) {
        if (active)
          setError(reason instanceof Error ? reason.message : 'The original source could not be opened.');
      }
    })();
    return () => {
      active = false;
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [getAttachment, record.sourceFilename, type, bundledPreview]);
  return (
    <Modal title={bundledPreview ? 'Source document' : 'Original source'} onClose={onClose} wide>
      <div className="stack">
        <div>
          <h3>{demoLabel(record.title, record.isDemo)}</h3>
          <p className="small muted">
            {bundledPreview ? 'Full source document' : 'Original bytes retained with this record'}
          </p>
        </div>
        {error ? (
          <p className="inline-error" role="alert">
            {error}
          </p>
        ) : !url ? (
          <p role="status">
            <LoaderCircle size={20} className="spin" /> Opening the original…
          </p>
        ) : (
          <>
            {type === 'application/pdf' ? (
              originalBlob && (
                <PDFPreview
                  key={url}
                  blob={originalBlob}
                  title={demoLabel(record.title, record.isDemo)}
                  page={page}
                />
              )
            ) : type.startsWith('image/') ? (
              <img
                className="source-preview-image"
                src={url}
                alt={`Original source: ${demoLabel(record.title, record.isDemo)}`}
              />
            ) : type.startsWith('text/') ? (
              <pre className="prose source-text">{demoSourceText(text, record.isDemo)}</pre>
            ) : (
              <p>This file type does not have a browser preview. Download the original to open it.</p>
            )}
            {shortened && (
              <p className="small muted">
                Preview shortened to 120 KB. The download contains the complete original.
              </p>
            )}
            <a
              className="button button-secondary"
              href={url}
              download={
                bundledPreview
                  ? record.sourceFilename?.replace(/^reva-synthetic-/, 'reva-')
                  : record.sourceFilename
              }
            >
              <Download size={18} /> {bundledPreview ? 'Download source' : 'Download original'}
            </a>
          </>
        )}
      </div>
    </Modal>
  );
}
