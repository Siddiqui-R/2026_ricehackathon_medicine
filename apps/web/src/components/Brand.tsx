// Purpose: Render Reva's wordmark and a compact symbol at consistent sizes.
// Inputs: Optional compact display mode and CSS class.
// Outputs: Decorative vector mark plus an accessible brand label.
// Side effects: None.

// MARK: - Four connected leaves suggest a complete, connected medical history
export function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <span className="brand" aria-label="Reva">
      <svg className="brand-symbol" viewBox="0 0 40 40" aria-hidden="true">
        <path d="M19 18H9a7 7 0 0 1 0-14h3a7 7 0 0 1 7 7Z" fill="currentColor" />
        <path d="M22 19V9a7 7 0 0 1 14 0v3a7 7 0 0 1-7 7Z" fill="currentColor" opacity=".65" />
        <path d="M21 22h10a7 7 0 0 1 0 14h-3a7 7 0 0 1-7-7Z" fill="currentColor" />
        <path d="M18 21v10a7 7 0 0 1-14 0v-3a7 7 0 0 1 7-7Z" fill="currentColor" opacity=".65" />
      </svg>
      {!compact && (
        <span className="brand-name">
          reva<span className="brand-period">.</span>
        </span>
      )}
    </span>
  );
}
