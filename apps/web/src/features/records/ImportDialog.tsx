// Purpose: Guide document intake from original file through local extraction, review, and durable saving.
// Inputs: User-selected text/PDF/image bytes, source metadata, and explicit extraction review.
// Outputs: A versioned MedicalRecord plus its unchanged original attachment in the local repository.
// Side effects: Reads locally, manages cancellable workers/object URLs, and optionally requests a configured summary after save.

import { useEffect, useRef, useState, type ChangeEvent } from 'react';
import { Camera, Check, FileText, LoaderCircle, Upload } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { uid, nowISO, localExcerpt } from '../../core/domain';
import type { MedicalRecord } from '../../core/models';
import { Badge, Button, Card, Field, Modal } from '../../components/ui';
import {
  extractDocument,
  MAX_FILE_BYTES,
  MAX_TEXT_BYTES,
  sourceType,
  textByteCount,
  type ExtractionResult,
} from './extractDocument';
import { localDay } from './recordPresentation';

// MARK: - Cancellable reading and unchanged original ownership
export function ImportDialog({ onClose }: { onClose: () => void }) {
  const { saveRecord, summarizeRecord, connectedAI, notify, reportError } = useReva();
  const [file, setFile] = useState<File | null>(null);
  const [previewURL, setPreviewURL] = useState('');
  const [extraction, setExtraction] = useState<ExtractionResult | null>(null);
  const [title, setTitle] = useState('');
  const [provider, setProvider] = useState('');
  const [date, setDate] = useState(localDay());
  const [text, setText] = useState('');
  const [reviewed, setReviewed] = useState(false);
  const [reading, setReading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [progress, setProgress] = useState('');
  const [error, setError] = useState('');
  const input = useRef<HTMLInputElement>(null);
  const camera = useRef<HTMLInputElement>(null);
  const operation = useRef<AbortController | null>(null);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      operation.current?.abort();
    };
  }, []);
  useEffect(() => {
    if (!file) {
      setPreviewURL('');
      return;
    }
    const url = URL.createObjectURL(file);
    setPreviewURL(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);
  const choose = async (chosen: File) => {
    if (!chosen.size || chosen.size > MAX_FILE_BYTES) {
      setError('Choose a nonempty document or image of up to 16 MB.');
      return;
    }
    operation.current?.abort();
    const controller = new AbortController();
    operation.current = controller;
    setFile(chosen);
    setTitle(chosen.name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' '));
    setProvider('');
    setText('');
    setReviewed(false);
    setError('');
    setExtraction(null);
    setReading(true);
    setProgress('Reading on this device…');
    try {
      const result = await extractDocument(chosen, controller.signal, (message) => {
        if (alive.current && operation.current === controller) setProgress(message);
      });
      if (alive.current && operation.current === controller) {
        setExtraction(result);
        setText(result.text);
      }
    } catch (reason) {
      if (alive.current && operation.current === controller) {
        setExtraction({
          text: '',
          pageTexts: [],
          pageCount: 1,
          incomplete: true,
          usedOCR: false,
          warnings: [
            controller.signal.aborted
              ? 'Reading was stopped. The original can still be saved for later review.'
              : reason instanceof Error
                ? reason.message
                : 'The source could not be read.',
          ],
        });
      }
    } finally {
      if (alive.current && operation.current === controller) setReading(false);
    }
  };
  const changed = (event: ChangeEvent<HTMLInputElement>) => {
    const selected = event.target.files?.[0];
    event.target.value = '';
    if (selected) void choose(selected);
  };
  const close = () => {
    if (saving) return;
    operation.current?.abort();
    onClose();
  };

  // MARK: - Save original bytes and the reviewable record in one transaction
  const save = async () => {
    if (!file || !extraction || reading || saving) return;
    if (!title.trim() || !date || textByteCount(text) > MAX_TEXT_BYTES) {
      setError('Add a title and source date, and keep extracted text within 120 KB.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const filename = `${uid()}-${file.name.replace(/[^A-Za-z0-9 ._()-]/g, '_').slice(-120)}`;
      const type = sourceType(file);
      const record: MedicalRecord = {
        id: uid(),
        title: title.trim(),
        kind: type.startsWith('image/') ? 'Scan' : 'Notes',
        provider: provider.trim() || 'Manually added',
        date,
        uploadedAt: nowISO(),
        tags: [],
        text,
        summary: localExcerpt(text),
        sourceFilename: filename,
        mimeType: type,
        pageCount: extraction.pageCount,
        pageTexts: text === extraction.text && extraction.pageTexts.length ? extraction.pageTexts : null,
        status: reviewed && text.trim() && !extraction.incomplete ? 'ready' : 'needsReview',
        notes: extraction.warnings.join('\n'),
        isDemo: false,
        version: 1,
      };
      await saveRecord(record, undefined, file);
      notify('Record saved with its original file and a local excerpt.');
      if (connectedAI && text.trim()) void summarizeRecord(record.id).catch(reportError);
      onClose();
      location.hash = `/records/${encodeURIComponent(record.id)}`;
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : 'The record could not be saved. Your selected file is still available here.',
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={file ? 'Review your document' : 'Add a record'} onClose={close} wide={Boolean(file)}>
      <div className="stack">
        <input
          ref={input}
          hidden
          type="file"
          accept=".pdf,.txt,.md,.png,.jpg,.jpeg,.webp,.heic,application/pdf,text/plain,image/*"
          onChange={changed}
        />
        <input ref={camera} hidden type="file" accept="image/*" capture="environment" onChange={changed} />
        {!file ? (
          <>
            <p className="muted">
              Bring a medical document into your history. Text is read in this browser, and you can review it
              before saving.
            </p>
            <button
              type="button"
              className="upload-dropzone"
              onClick={() => input.current?.click()}
              onDragOver={(event) => event.preventDefault()}
              onDrop={(event) => {
                event.preventDefault();
                const dropped = event.dataTransfer.files[0];
                if (dropped) void choose(dropped);
              }}
            >
              <Upload size={34} aria-hidden="true" />
              <strong>Choose a document or drag it here</strong>
              <span>PDF, text, or image · up to 16 MB</span>
            </button>
            <Button variant="secondary" onClick={() => camera.current?.click()}>
              <Camera size={18} /> Use camera or choose a photo
            </Button>
            <p className="small muted">
              Scans use local English text recognition. Reading is limited to 24 PDF pages and 120 KB of text;
              the complete original is kept.
            </p>
          </>
        ) : (
          <>
            <div className="row">
              <FileText size={22} />
              <div className="record-main">
                <strong>{file.name}</strong>
                <p className="small muted">
                  {(file.size / 1024 / 1024).toFixed(2)} MB · original file retained unchanged
                </p>
              </div>
              <Badge tone="accent">Local reading</Badge>
            </div>
            {reading ? (
              <Card>
                <div className="stack">
                  <div className="row" role="status">
                    <LoaderCircle size={22} className="spin" />
                    <strong>{progress}</strong>
                  </div>
                  <p className="muted small">This stays on your device. Scanned pages may take a moment.</p>
                  <Button variant="secondary" onClick={() => operation.current?.abort()}>
                    Stop reading
                  </Button>
                </div>
              </Card>
            ) : (
              extraction && (
                <>
                  <div className="form-grid">
                    <Field label="Record title">
                      <input
                        value={title}
                        onChange={(event) => setTitle(event.target.value)}
                        maxLength={240}
                      />
                    </Field>
                    <Field label="Source date" hint="Choose the date shown on the document.">
                      <input type="date" value={date} onChange={(event) => setDate(event.target.value)} />
                    </Field>
                    <div className="field-full">
                      <Field label="Clinic or provider · optional">
                        <input
                          value={provider}
                          onChange={(event) => setProvider(event.target.value)}
                          maxLength={240}
                          placeholder="For example, your clinic or laboratory"
                        />
                      </Field>
                    </div>
                  </div>
                  <details className="source-disclosure">
                    <summary>Compare with the original</summary>
                    <div className="source-preview-wrap">
                      {sourceType(file) === 'application/pdf' ? (
                        <iframe className="source-preview" src={previewURL} title="Original uploaded PDF" />
                      ) : sourceType(file).startsWith('image/') ? (
                        <img
                          className="source-preview-image"
                          src={previewURL}
                          alt="Original uploaded document"
                        />
                      ) : (
                        <pre className="prose">
                          {extraction.text || 'The original file is available below.'}
                        </pre>
                      )}
                      <a className="text-link" href={previewURL} download={file.name}>
                        Download original
                      </a>
                    </div>
                  </details>
                  {extraction.warnings.length > 0 && (
                    <div className="extraction-notices" role="status">
                      <strong>Review these details</strong>
                      <ul>
                        {extraction.warnings.map((warning) => (
                          <li key={warning}>{warning}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                  <Field
                    label="Extracted text"
                    hint={`${textByteCount(text).toLocaleString()} / 120,000 UTF-8 bytes. Keep original names, dates, doses, values, and uncertainty.`}
                  >
                    <textarea
                      rows={11}
                      value={text}
                      onChange={(event) => {
                        setText(event.target.value);
                        setReviewed(false);
                      }}
                      placeholder="Add a transcription if the text could not be read."
                    />
                  </Field>
                  <label className="checkbox-field">
                    <input
                      type="checkbox"
                      checked={reviewed}
                      onChange={(event) => setReviewed(event.target.checked)}
                      disabled={!text.trim() || extraction.incomplete}
                    />
                    <span>
                      I reviewed the text against the original
                      {extraction.incomplete ? ' · partial reading remains marked for review' : ''}
                    </span>
                  </label>
                  <details>
                    <summary>Preview the local excerpt</summary>
                    <p className="prose">
                      {localExcerpt(text) || 'A readable excerpt will appear after text is added.'}
                    </p>
                  </details>
                </>
              )
            )}
          </>
        )}
        {error && (
          <p className="inline-error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <Button variant="secondary" onClick={close} disabled={saving}>
            Cancel
          </Button>
          {file && !reading && (
            <Button variant="ghost" onClick={() => input.current?.click()} disabled={saving}>
              Choose another file
            </Button>
          )}
          {file && (
            <Button
              onClick={() => void save()}
              disabled={
                reading || saving || !extraction || !title.trim() || textByteCount(text) > MAX_TEXT_BYTES
              }
            >
              <Check size={18} />
              {saving ? 'Saving…' : 'Save to Records'}
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
}
