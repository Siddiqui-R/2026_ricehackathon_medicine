// Purpose: Preserve the notes editor's space and reveal subtle directional cues only on overflow.
import { useEffect, useRef, useState } from 'react';
import { ChevronDown, ChevronUp } from 'lucide-react';
import { Field } from '../../components/ui';

export function notesScrollEdges(element: Pick<HTMLElement, 'scrollTop' | 'scrollHeight' | 'clientHeight'>) {
  return {
    above: element.scrollTop > 2,
    below: element.scrollHeight - element.clientHeight - element.scrollTop > 2,
  };
}
export function RecordingNotes({
  value,
  disabled,
  onChange,
}: {
  value: string;
  disabled: boolean;
  onChange(value: string): void;
}) {
  const textarea = useRef<HTMLTextAreaElement>(null);
  const [edges, setEdges] = useState({ above: false, below: false });
  const measure = () => {
    if (!textarea.current) return;
    const next = notesScrollEdges(textarea.current);
    setEdges((old) => (old.above === next.above && old.below === next.below ? old : next));
  };
  useEffect(measure, [value]);
  useEffect(() => {
    const element = textarea.current;
    if (!element) return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return (
    <Field label="Your notes">
      <span className="recording-notes-editor">
        <textarea
          ref={textarea}
          aria-label="Your notes"
          rows={7}
          maxLength={20000}
          disabled={disabled}
          placeholder="Questions, reminders, anything you want to remember…"
          value={value}
          onScroll={measure}
          onChange={(event) => onChange(event.target.value)}
        />
        {edges.above && (
          <span className="recording-notes-scroll is-above" aria-hidden="true">
            <ChevronUp size={13} />
          </span>
        )}
        {edges.below && (
          <span className="recording-notes-scroll is-below" aria-hidden="true">
            <ChevronDown size={13} />
          </span>
        )}
      </span>
    </Field>
  );
}
