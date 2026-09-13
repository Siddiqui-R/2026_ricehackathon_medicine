// Purpose: Let a presenter choose among independent demo people from the avatar area.
// Inputs: Current demo URL and whether a connected operation is busy.
// Outputs: A named switch control and an accessible person-selection dialog.
// Side effects: Navigates to a whitelisted demo URL; existing databases and originals are retained.
import { useState } from 'react';
import { Check, UsersRound } from 'lucide-react';
import { Modal } from '../../components/ui';
import { demoPeople, demoPersonURL, selectedDemoPerson } from '../../core/demoProfiles';

// MARK: - A full navigation starts a new store bound only to the selected person's database
export function DemoSwitcher({
  disabled,
  className = '',
  label = 'Switch account',
}: {
  disabled: boolean;
  className?: string;
  label?: string;
}) {
  const [open, setOpen] = useState(false);
  const selected = selectedDemoPerson();
  return (
    <>
      <button
        className={`demo-switch ${className}`}
        type="button"
        disabled={disabled}
        aria-label={label}
        title={label}
        onClick={() => setOpen(true)}
      >
        <UsersRound size={17} />
        <span className="demo-switch-label">{label}</span>
      </button>
      {open && (
        <Modal title="Switch account" onClose={() => setOpen(false)}>
          <p className="muted">Choose an account. Each account keeps its own saved changes.</p>
          <div className="demo-people">
            {demoPeople.map((person) => (
              <button
                type="button"
                className="demo-person"
                key={person.id}
                disabled={disabled || selected === person.id}
                aria-pressed={selected === person.id}
                onClick={() => location.assign(demoPersonURL(person.id, location.href))}
              >
                <span className="avatar">{person.initials}</span>
                <span>
                  <strong>{person.name}</strong>
                  <small>{person.description}</small>
                </span>
                {selected === person.id && <Check size={18} aria-label="Current account" />}
              </button>
            ))}
          </div>
        </Modal>
      )}
    </>
  );
}
