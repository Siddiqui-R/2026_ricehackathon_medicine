// Purpose: Keep a document's known date separate from the day it was added.
// Inputs: Source date/provenance and the original upload instant.
// Outputs: Persistable date metadata and unambiguous UI/provider labels.
// Side effects: None; an unknown event date is never inferred from an upload.
import type { MedicalRecord } from './models';
import { calendarDay, formatDate } from './dates';

// MARK: - Import fallback dates are sortable without claiming a clinical occurrence
export function documentDate(
  sourceDate: string,
  uploadedAt: string,
): Pick<MedicalRecord, 'date' | 'dateSource'> {
  return sourceDate
    ? { date: sourceDate, dateSource: 'document' }
    : { date: calendarDay(new Date(uploadedAt)), dateSource: 'added' };
}
export function recordDateLabel(record: MedicalRecord): string {
  return `${record.dateSource === 'added' ? 'Added ' : ''}${formatDate(record.date)}`;
}
export function recordDateContext(record: MedicalRecord): string {
  if (record.dateSource === 'added') return `Added ${record.date.slice(0, 10)}; event date unknown`;
  return record.dateSource ? record.date : `Date ${record.date.slice(0, 10)}; source unverified`;
}
