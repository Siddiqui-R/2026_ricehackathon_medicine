// Purpose: Keep record icons, dates, and source ordering consistent across Records screens.
// Inputs: Native-compatible MedicalRecord values and browser-local calendar dates.
// Outputs: Pure presentation helpers and an accessible decorative source icon.
// Side effects: None.

import { FileText, FlaskConical, Image, NotebookPen, ScanLine, Stethoscope, AudioLines } from 'lucide-react';
import type { MedicalRecord } from '../../core/models';

// MARK: - Source categories and stable occurrence ordering
export function RecordSymbol({ record, size = 22 }: { record: MedicalRecord; size?: number }) {
  const icons: Record<string, typeof FileText> = {
    Labs: FlaskConical,
    Imaging: Image,
    Procedure: Stethoscope,
    Recording: AudioLines,
    Scan: ScanLine,
  };
  const Symbol = record.symptomEntry ? NotebookPen : (icons[record.kind] ?? FileText);
  return <Symbol size={size} aria-hidden="true" />;
}
export function newestRecords(records: MedicalRecord[]) {
  return [...records].sort(
    (a, b) =>
      b.date.localeCompare(a.date) ||
      (b.symptomEntry?.observedAt ?? b.uploadedAt).localeCompare(
        a.symptomEntry?.observedAt ?? a.uploadedAt,
      ) ||
      a.id.localeCompare(b.id),
  );
}
export function localDay(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
export function queryParameter(name: string) {
  return new URLSearchParams(location.hash.split('?')[1] ?? '').get(name);
}
