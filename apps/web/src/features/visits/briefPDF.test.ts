// Purpose: Verify one-page PDF sizing, clinical Unicode text, and overflow handling.
// Inputs: Fictional brief content and the bundled licensed Noto Sans font.
// Outputs: Assertions for a single letter-size page and rejected excess content.
// Side effects: Reads the local font; writes a sample PDF only when REVA_PDF_QA is explicitly enabled.

// MARK: - Fictional handout fixtures and PDF bounds
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { it, expect } from 'vitest';
import { PDFDocument, PDFDict, PDFName, PDFString } from 'pdf-lib';
import { createBriefPDF } from './briefPDF';
import type { ClinicalBrief } from '../../core/visitBrief';
const font = new Uint8Array(await readFile(new URL('../../../public/fonts/NotoSans.ttf', import.meta.url)));
const brief: ClinicalBrief = {
  patient: { name: 'Alex Morgan (fictional)', dateOfBirth: '1988-04-17', isDemo: true },
  visitType: 'Cardiology follow-up',
  createdAt: '2026-09-12T17:00:00Z',
  overview:
    'Reason: Intermittent palpitations for two weeks, per patient.\nRelevant history: Episodes last 2–3 minutes. No syncope reported.\nMedications: Patient reports levothyroxine 50 µg daily.\nAllergies: Penicillin — rash, per patient.\nKey findings: ECG (September 7): sinus rhythm. TSH 2.1 mIU/L. No rhythm tracing during symptoms.',
  questions: [
    'What could explain the episodes?',
    'Is further monitoring needed?',
    'Which changes should prompt follow-up?',
  ],
  sources: [
    { id: 'profile', title: 'Patient-provided medical profile', date: '' },
    { id: 'ecg', title: 'Resting ECG', date: '2026-09-07' },
    { id: 'labs', title: 'Laboratory results', date: '2026-09-07' },
  ],
  model: 'gemini-3.8-flash',
  sourceSignature: '',
};
it('creates one letter-size PDF with Unicode clinical units', async () => {
  const bytes = await createBriefPDF(brief, font);
  const pdf = await PDFDocument.load(bytes);
  expect(pdf.getPageCount()).toBe(1);
  expect(pdf.getPage(0).getSize()).toEqual({ width: 612, height: 792 });
  if (process.env.REVA_PDF_QA) {
    await mkdir('tmp/pdfs', { recursive: true });
    await writeFile('tmp/pdfs/visit-brief.pdf', bytes);
  }
});
it('keeps a bounded 180-word brief, three questions and six sources on one page', async () => {
  const long = {
    ...brief,
    overview: Array(18)
      .fill('Patient reports brief episodes lasting two minutes without reported syncope.')
      .join(' '),
    sources: Array.from({ length: 6 }, (_, i) => ({
      id: `${i}`,
      title: 'Fictional clinic follow-up and laboratory review',
      date: '2026-09-07',
    })),
  };
  const pdf = await PDFDocument.load(await createBriefPDF(long, font));
  expect(pdf.getPageCount()).toBe(1);
});
it('rejects excess content instead of clipping it or creating additional pages', async () => {
  await expect(createBriefPDF({ ...brief, overview: 'word '.repeat(181) }, font)).rejects.toThrow('too long');
  await expect(
    createBriefPDF(
      { ...brief, patient: { ...brief.patient, name: Array(500).fill('Long name').join(' ') } },
      font,
    ).then(() => null),
  ).rejects.toThrow('exceeds one page');
});
it('embeds verified source destinations in exported briefs without inventing missing URLs', async () => {
  const url = 'https://reva.example/app#/records/ecg';
  const pdf = await PDFDocument.load(await createBriefPDF(brief, font, { ecg: url }));
  const annotations = pdf.getPage(0).node.Annots()!;
  expect(annotations.size()).toBe(1);
  const annotation = pdf.context.lookup(annotations.get(0), PDFDict);
  const action = annotation.lookup(PDFName.of('A'), PDFDict);
  expect(action.lookup(PDFName.of('URI'), PDFString).decodeText()).toBe(url);
  await expect(createBriefPDF(brief, font, { ecg: 'javascript:alert(1)' })).rejects.toThrow(
    'unsupported address',
  );
});
