// Purpose: Keep fixture labels out of the interface without changing saved identity or provider inputs.
// Inputs: Display text and explicit demo provenance.
// Outputs: Display wording; real account and imported source content is left untouched.
// Side effects: None. Internal IDs and stored originals retain their provenance.

export function demoLabel(text: string, isDemo = false): string {
  if (!isDemo) return text;
  return text
    .replace(/[ \t]*\((?:synthetic|fictional)\)/gi, '')
    .replace(/\bSample (Grove|Harbor|Maple)\b/g, '$1')
    .replace('Patient-authored sample', 'Patient-authored notes')
    .replace('Synthetic sample transcript - no audio', 'Visit transcript · no audio');
}

// Only the bundled fixtures' editorial phrases are removed; clinical facts and uncertainty remain.
export function demoDescription(text: string, isDemo = false): string {
  if (!isDemo) return text;
  return demoLabel(text, true)
    .replace(/\bDemo summary:\s*/gi, '')
    .replace('Synthetic sample memory: ', '')
    .replace(/\s*\[demo-segment-\d+(?:, demo-segment-\d+)*\]/g, '')
    .replace('Synthetic upcoming visit. ', '')
    .replace('Completed synthetic visit associated with', 'Completed visit associated with')
    .replace('optional text-only sample transcript', 'text-only transcript')
    .replace('Synthetic scan with', 'Scan with')
    .replace(/Synthetic (?:plain-text )?source and authored demo summary\./g, 'Source and prepared summary.')
    .replace('Values are synthetic and do not establish', 'Values do not establish')
    .replace('part of the fictional history.', 'part of the history.')
    .replace('Fictional sample transcript.', 'Visit transcript.')
    .replace('This unrelated past episode is included to demonstrate relevance filtering.', '')
    .replace(
      'Seed text is an authored reference transcription, not an OCR success claim.',
      'The source text was transcribed manually.',
    )
    .trim();
}

export function demoSourceText(text: string, isDemo = false): string {
  if (!isDemo) return text;
  return demoDescription(text, true)
    .replace(/^\s*SYNTHETIC DEMO - FICTIONAL (?:MEDICAL RECORD|PATIENT PREPARATION NOTE)\s*$/gm, '')
    .replaceAll('REVA / SYNTHETIC SOURCE LIBRARY', 'REVA / HEALTH RECORDS')
    .replace(
      /^\s*Invented for Reva software demonstration\. Not a real patient record or medical advice\.\s*$/gm,
      '',
    )
    .replace(/^Synthetic source ID: demo-record-[a-z0-9-]+\s*$/gm, '')
    .replace('SYNTHETIC SCAN | 1 page | no real patient data', 'SCAN | 1 page')
    .replace('DEMONSTRATION PURPOSE', 'SOURCE CONTEXT')
    .replace(/\bfictional (health history|patient|clinician|episode|operative record|source)/g, '$1')
    .replace(/\bsynthetic (scan|written report)/g, '$1')
    .replace('are intentionally not supplied in this synthetic dataset.', 'are not supplied in this record.')
    .replace(/These invented numbers are included to test faithful transcription of values and units\./g, '')
    .replace(
      'These are invented historical details for testing source retrieval across dates and PDF pages. ',
      '',
    )
    .replace('demo document does not add', 'document does not add')
    .replace('this sample conversation.', 'this conversation.')
    .replace(
      'This is a fictional Reva demonstration transcript. No real patient conversation or recorded audio is represented.',
      '',
    )
    .replace(
      'End of synthetic sample. Preparation items and unresolved questions come from the dialogue above. This text is not a treatment plan or a transcript of newly captured microphone audio.',
      '',
    )
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
