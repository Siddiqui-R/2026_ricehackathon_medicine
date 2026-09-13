// Purpose: Render a concise, readable pre-visit handout on one letter-size PDF page.
// Inputs: Validated brief content, verified source URLs, and an optional embedded Unicode font.
// Outputs: PDF bytes with clickable source titles, or an error for unsupported characters/page overflow.
// Side effects: Loads the bundled font when needed and builds the document in memory.

// MARK: - Measured text wrapping and bounded PDF composition
// One letter-size medical handout. Overflow is an error, never clipped text or a second page.
import { PDFDocument, PDFString, rgb, type PDFFont } from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';
import type { ClinicalBrief } from '../../core/visitBrief';
import { validateBriefText } from '../../core/visitBrief';
import { formatDate } from '../../core/dates';

export function wrapText(text: string, font: PDFFont, size: number, width: number): string[] {
  const lines: string[] = [];
  for (const paragraph of text.split(/\r?\n/u)) {
    let line = '';
    for (const word of paragraph.trim().split(/\s+/u).filter(Boolean)) {
      if (font.widthOfTextAtSize(word, size) > width)
        throw new Error('A word in the brief is too long to fit. Shorten it and generate again.');
      const next = line ? `${line} ${word}` : word;
      if (font.widthOfTextAtSize(next, size) > width) {
        lines.push(line);
        line = word;
      } else line = next;
    }
    lines.push(line);
  }
  return lines;
}
export async function createBriefPDF(
  brief: ClinicalBrief,
  fontBytes?: Uint8Array,
  sourceURLs: Readonly<Record<string, string>> = {},
): Promise<Uint8Array> {
  validateBriefText(brief);
  if (!fontBytes) {
    const response = await fetch('/fonts/NotoSans.ttf');
    if (!response.ok) throw new Error('The PDF font could not load. Please try again.');
    fontBytes = new Uint8Array(await response.arrayBuffer());
  }
  const document = await PDFDocument.create();
  document.registerFontkit(fontkit);
  const font = await document.embedFont(fontBytes, { subset: true });
  const supported = new Set(font.getCharacterSet());
  const page = document.addPage([612, 792]);
  const ink = rgb(0.1, 0.12, 0.14),
    gray = rgb(0.35, 0.38, 0.4);
  const left = 48,
    width = 516;
  let y = 740;
  function write(text: string, size = 11, gap = 5, color = ink, sourceURL?: string) {
    for (const character of text.replace(/[\r\n]/gu, '')) {
      if (!supported.has(character.codePointAt(0)!))
        throw new Error(
          'The PDF font cannot display a character in this brief. Edit that character and try again.',
        );
    }
    const lines = wrapText(text, font, size, width);
    for (const line of lines) {
      if (y < 84) throw new Error('This brief exceeds one page. Generate a shorter brief.');
      page.drawText(line, { x: left, y, size, font, color });
      if (sourceURL) {
        const annotation = document.context.obj({
          Type: 'Annot',
          Subtype: 'Link',
          Rect: [left, y - 2, left + font.widthOfTextAtSize(line, size), y + size],
          Border: [0, 0, 0],
          A: { Type: 'Action', S: 'URI', URI: PDFString.of(sourceURL) },
        });
        page.node.addAnnot(document.context.register(annotation));
      }
      y -= size * 1.42;
    }
    y -= gap;
  }
  document.setTitle('Pre-visit brief');
  document.setAuthor('Reva');
  document.setSubject('Patient-provided visit preparation');
  write('PRE-VISIT BRIEF', 19, 10);
  write(brief.patient.name, 12, 2);
  if (brief.patient.dateOfBirth) write(`DOB: ${formatDate(brief.patient.dateOfBirth)}`, 10, 3);
  write(`${brief.visitType}  |  Prepared ${formatDate(brief.createdAt)}`, 10, 10, gray);
  page.drawLine({
    start: { x: left, y: y + 2 },
    end: { x: left + width, y: y + 2 },
    thickness: 0.6,
    color: gray,
  });
  y -= 16;
  write(brief.overview, 11, 14);
  if (brief.questions.length) {
    write('QUESTIONS TO ASK', 10, 5);
    brief.questions.forEach((question, index) => write(`${index + 1}. ${question}`, 11, 3));
    y -= 10;
  }
  if (brief.sources.length) {
    write('SOURCES', 8.5, 4, gray);
    brief.sources.forEach((source, index) => {
      const suppliedURL = sourceURLs[source.id];
      let sourceURL: string | undefined;
      if (suppliedURL) {
        const url = new URL(suppliedURL);
        if (url.protocol !== 'https:' && url.protocol !== 'http:')
          throw new Error('A source link has an unsupported address. Generate the brief again.');
        sourceURL = url.href;
      }
      write(
        `${index + 1}. ${source.title}${source.date ? ` · ${formatDate(source.date)}` : ''}`,
        8.5,
        2,
        sourceURL ? rgb(0.14, 0.42, 0.82) : gray,
        sourceURL,
      );
    });
  }
  page.drawLine({ start: { x: left, y: 61 }, end: { x: left + width, y: 61 }, thickness: 0.4, color: gray });
  page.drawText(
    `${brief.patient.isDemo ? 'FICTIONAL DEMO · ' : ''}Patient-prepared · AI-assisted · Review for accuracy`,
    { x: left, y: 45, font, size: 8, color: gray },
  );
  page.drawText('1 / 1', { x: 544, y: 45, font, size: 8, color: gray });
  return document.save();
}
