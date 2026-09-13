// Purpose: Give sourced statements a compact, accessible path back to their evidence.
// Inputs: Explicit source titles and destinations, or an action that reveals an original in place.
// Outputs: A blue chain icon and, when needed, a list of available source links.
// Side effects: Opens a source picker or delegates source navigation; never infers clinical provenance.

import { useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowUpRight, Link2 } from 'lucide-react';
import { Modal } from './ui';
import '../styles/source-links.css';

export interface SourceTarget {
  label: string;
  href: string;
}

// MARK: - One icon represents only known sources, with full names available to assistive technology
export function SourceLink({
  sources = [],
  label,
  onOpen,
}: {
  sources?: readonly SourceTarget[];
  label?: string;
  onOpen?: () => void;
}) {
  const [open, setOpen] = useState(false);
  const unique = sources.filter(
    (source, index) => sources.findIndex((other) => other.href === source.href) === index,
  );
  if (!unique.length && !onOpen) return null;
  const description =
    label ?? (unique.length === 1 ? `View source: ${unique[0].label}` : `View ${unique.length} sources`);
  if (unique.length === 1 && !onOpen)
    return (
      <a className="source-link" href={unique[0].href} aria-label={description} title={description}>
        <Link2 size={15} aria-hidden="true" />
      </a>
    );
  return (
    <>
      <button
        type="button"
        className="source-link"
        aria-label={description}
        title={description}
        aria-haspopup={onOpen ? undefined : 'dialog'}
        onClick={onOpen ?? (() => setOpen(true))}
      >
        <Link2 size={15} aria-hidden="true" />
      </button>
      {open &&
        createPortal(
          <Modal title="Sources" onClose={() => setOpen(false)}>
            <ul className="source-link-list">
              {unique.map((source) => (
                <li key={source.href}>
                  <a href={source.href} onClick={() => setOpen(false)}>
                    <Link2 size={17} aria-hidden="true" />
                    <span>{source.label}</span>
                    <ArrowUpRight size={16} aria-hidden="true" />
                  </a>
                </li>
              ))}
            </ul>
          </Modal>,
          document.body,
        )}
    </>
  );
}
