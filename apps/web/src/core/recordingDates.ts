// Purpose: Distinguish recording occurrence from the time audio was added to a workspace.
// Inputs: Optional capture/save provenance and legacy recording creation timestamps.
// Outputs: Central calendar dates, date-only fallback titles and explicit date labels.
// Side effects: None; uploaded audio never acquires an invented capture time.

import type { VisitRecording } from './models';
import { calendarDay, formatDate } from './dates';

// MARK: - Known capture time takes precedence; legacy creation remains backward compatible
export function recordingInstant(recording: VisitRecording): string {
  return recording.capturedAt ?? recording.savedAt ?? recording.createdAt;
}
export function recordingDateTitle(instant = new Date().toISOString()): string {
  return formatDate(calendarDay(new Date(instant)));
}
export function recordingDateLabel(recording: VisitRecording, withTime = false): string {
  const date = formatDate(recordingInstant(recording), withTime);
  return recording.capturedAt ? `Recorded ${date}` : recording.savedAt ? `Added ${date}` : date;
}
