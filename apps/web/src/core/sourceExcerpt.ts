// Purpose: Keep bounded previews as exact, complete source lines with separate omission notices.
// Inputs: Original wording, explicit fixture provenance and an optional selected line index.
// Outputs: An unchanged source span and preview completeness metadata.
// Side effects: None; no storage, network calls or source rewriting.

// MARK: - Retain source offsets so whitespace and line separators remain exact.
export function sourceLines(text: string) {
  return Array.from(text.matchAll(/[^\r\n\v\f\u0085\u2028\u2029]+/gu))
    .filter((match) => match[0].trim())
    .map((match) => ({ text: match[0], start: match.index, end: match.index + match[0].length }));
}

export function sourceText(text: string, isDemo = false): string {
  const lines = sourceLines(text);
  if (!isDemo || lines[0]?.text.trim() !== 'SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD') return text;
  let start = 0;
  for (const line of lines.slice(0, 10)) {
    if (/^(Source date:|Week ending:)/u.test(line.text.trim())) start = line.end;
  }
  let end = text.length;
  for (const line of lines) {
    if (line.text.startsWith('Invented for Reva software demonstration.')) end = line.start;
  }
  return start < end ? text.slice(start, end).trim() : text;
}

// MARK: - Bound by complete lines, never by a partial dose, unit or negation.
function fitsPreview(text: string): boolean {
  const characters =
    typeof Intl.Segmenter === 'function'
      ? new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)
      : text;
  let count = 0;
  for (const _character of characters) if (++count > 1800) return false;
  return true;
}

export function sourcePassage(source: string, startLine = 0) {
  const lines = sourceLines(source);
  if (!lines.length) return { text: '', omitted: false };
  const start = Math.min(Math.max(0, startLine), lines.length - 1);
  const lower = lines[start].start;
  let upper = lower;
  for (const line of lines.slice(start, start + 24)) {
    if (!fitsPreview(source.slice(lower, line.end))) break;
    upper = line.end;
  }
  return { text: source.slice(lower, upper), omitted: start > 0 || upper !== lines[lines.length - 1].end };
}

export function passageNotice(passage: ReturnType<typeof sourcePassage>): string | undefined {
  if (!passage.omitted) return undefined;
  return passage.text
    ? 'This is a selected passage. Open the original or full source text for the omitted content.'
    : 'No complete source line fits this preview. Open the original or full source text to review it.';
}
