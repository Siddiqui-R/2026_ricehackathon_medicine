// Purpose: Keep demo-only labels out of presentation without changing saved identity or source wording.
// Inputs: A display label and its explicit demo provenance.
// Outputs: The same label with only known demo markers removed.
// Side effects: None; never use this helper to rewrite source text or provider inputs.

// MARK: - Display-only labels leave source and account data untouched
export function demoLabel(text: string, isDemo = false): string {
  return isDemo ? text.replace(/[ \t]*\((?:synthetic|fictional)\)/gi, '') : text;
}

// These exact phrases belong to the bundled demo's authored metadata, not its original documents.
export function demoDescription(text: string, isDemo = false): string {
  if (!isDemo) return text;
  return demoLabel(text, true)
    .replace('Synthetic upcoming visit. ', '')
    .replace('Completed synthetic visit associated with', 'Completed visit associated with')
    .replace('Synthetic scan with', 'Scan with')
    .replace('Synthetic plain-text source and authored demo summary.', 'Authored demo summary.')
    .replace('Synthetic source and authored demo summary.', 'Authored demo summary.')
    .replace('Values are synthetic and do not establish', 'Values do not establish')
    .replace('part of the fictional history.', 'part of the history.')
    .replace('Fictional sample transcript.', 'Sample transcript.');
}
