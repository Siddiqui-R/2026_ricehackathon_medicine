// Purpose: Keep persistent overarching health information together in an editable quick-reference profile.
// Inputs: PatientProfile from the local snapshot and user-authored identity/medical field edits.
// Outputs: Readable health cards and a validated profile update independent of historical source records.
// Side effects: Saves through the aggregate mutation boundary; never rewrites documents or invokes providers.

import { useState, type FormEvent } from 'react';
import {
  CalendarDays,
  HeartPulse,
  NotebookPen,
  Pencil,
  Pill,
  Settings,
  ShieldAlert,
  Stethoscope,
  UserRound,
} from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { formatDate } from '../../core/domain';
import { demoLabel } from '../../core/presentation';
import type { PatientProfile } from '../../core/models';
import { Button, Card, Field, Modal, PageHeading } from '../../components/ui';
import { localDay } from '../records/recordPresentation';

// MARK: - Profile cards describe only supplied information, including unspecified fields
export function MedicalProfilePage() {
  const { snapshot } = useReva();
  const [editing, setEditing] = useState(false);
  const profile = snapshot?.profile;
  if (!profile)
    return (
      <Card>
        <p>Opening your medical profile…</p>
      </Card>
    );
  const sections = [
    { title: 'Allergies', icon: ShieldAlert, items: profile.allergies },
    { title: 'Medications', icon: Pill, items: profile.medications },
    { title: 'Conditions', icon: HeartPulse, items: profile.conditions },
    { title: 'Surgeries & implants', icon: Stethoscope, items: profile.surgeriesAndImplants ?? [] },
  ];
  return (
    <div className="stack">
      <PageHeading
        title="Medical profile"
        actions={
          <>
            <Button
              variant="secondary"
              onClick={() => {
                location.hash = '/settings';
              }}
            >
              <Settings size={18} /> Settings
            </Button>
            <Button onClick={() => setEditing(true)}>
              <Pencil size={18} /> Edit profile
            </Button>
          </>
        }
      />
      <Card className="profile-identity">
        <div className="profile-avatar" aria-hidden="true">
          {profile.initials || <UserRound size={26} />}
        </div>
        <div className="record-main">
          <h2>{demoLabel(profile.name, profile.isDemo)}</h2>
          <p className="row muted">
            <CalendarDays size={17} />
            {profile.dateOfBirth ? `Born ${formatDate(profile.dateOfBirth)}` : 'Date of birth not provided'}
          </p>
        </div>
      </Card>
      <div className="profile-grid">
        {sections.map((section) => (
          <Card key={section.title} className="stack">
            <div className="row">
              <span className="record-icon">
                <section.icon size={22} />
              </span>
              <h2>{section.title}</h2>
            </div>
            {section.items.length ? (
              <ul className="profile-items">
                {section.items.map((item, index) => (
                  <li key={`${index}-${item}`} className="prose">
                    {demoLabel(item, profile.isDemo)}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="muted">Not provided</p>
            )}
          </Card>
        ))}
      </div>
      <Card className="stack">
        <div className="row">
          <span className="record-icon">
            <NotebookPen size={22} />
          </span>
          <h2>Care notes</h2>
        </div>
        <p className={profile.careNotes ? 'prose' : 'muted'}>
          {demoLabel(profile.careNotes || '', profile.isDemo) || 'Not provided'}
        </p>
      </Card>
      <p className="small muted">
        Keep these details up to date. This profile is for quick reference; visit preparation currently uses
        your Records. Profile edits do not change historical documents.
      </p>
      {editing && <ProfileEditor profile={profile} onClose={() => setEditing(false)} />}
    </div>
  );
}

// MARK: - Line-based editing preserves absent fields and detects concurrent profile changes
function ProfileEditor({ profile, onClose }: { profile: PatientProfile; onClose: () => void }) {
  const { mutate, notify } = useReva();
  const [original] = useState(() => structuredClone(profile));
  const [name, setName] = useState(profile.name);
  const [birthDate, setBirthDate] = useState(profile.dateOfBirth);
  const [allergies, setAllergies] = useState(profile.allergies.join('\n'));
  const [medications, setMedications] = useState(profile.medications.join('\n'));
  const [conditions, setConditions] = useState(profile.conditions.join('\n'));
  const [procedures, setProcedures] = useState((profile.surgeriesAndImplants ?? []).join('\n'));
  const [notes, setNotes] = useState(profile.careNotes ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [discard, setDiscard] = useState(false);
  const dirty =
    name !== original.name ||
    birthDate !== original.dateOfBirth ||
    allergies !== original.allergies.join('\n') ||
    medications !== original.medications.join('\n') ||
    conditions !== original.conditions.join('\n') ||
    procedures !== (original.surgeriesAndImplants ?? []).join('\n') ||
    notes !== (original.careNotes ?? '');
  const close = () => {
    if (!saving) {
      if (dirty) setDiscard(true);
      else onClose();
    }
  };
  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError('');
    try {
      const trimmed = name.trim();
      if (!trimmed) throw new Error('Add your name before saving your medical profile.');
      if (
        birthDate &&
        (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate) ||
          Number.isNaN(new Date(`${birthDate}T00:00:00Z`).getTime()) ||
          new Date(`${birthDate}T00:00:00Z`).toISOString().slice(0, 10) !== birthDate ||
          birthDate > localDay())
      )
        throw new Error('Enter a valid date of birth, or leave it blank.');
      const list = (value: string) =>
        value
          .split(/\r?\n/)
          .map((item) => item.trim())
          .filter(Boolean);
      const words = trimmed.split(/\s+/).filter((word) => /^\p{L}/u.test(word) && !word.endsWith(')'));
      const initials = [
        Array.from(words[0] ?? '')[0],
        words.length > 1 ? Array.from(words.at(-1) ?? '')[0] : '',
      ]
        .filter(Boolean)
        .join('')
        .toUpperCase();
      const surgeries = list(procedures);
      await mutate((draft) => {
        if (JSON.stringify(draft.profile) !== JSON.stringify(original))
          throw new Error(
            'Your profile changed while this editor was open. Close and reopen it to see the latest details.',
          );
        draft.profile = {
          ...original,
          name: trimmed,
          dateOfBirth: birthDate,
          initials,
          allergies: list(allergies),
          medications: list(medications),
          conditions: list(conditions),
          surgeriesAndImplants: surgeries.length ? surgeries : null,
          careNotes: notes.trim() || null,
        };
      });
      notify('Medical profile saved.');
      onClose();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'The medical profile could not be saved.');
    } finally {
      setSaving(false);
    }
  };
  return (
    <Modal title="Edit medical profile" onClose={close} wide>
      {discard ? (
        <div className="stack">
          <p>Discard your unsaved profile changes?</p>
          <div className="form-actions">
            <Button variant="secondary" onClick={() => setDiscard(false)}>
              Keep editing
            </Button>
            <Button variant="danger" onClick={onClose}>
              Discard changes
            </Button>
          </div>
        </div>
      ) : (
        <form className="stack" onSubmit={(event) => void save(event)}>
          <p className="muted">
            Add what you know. Empty medical fields stay “Not provided.” Put one item on each line.
          </p>
          <div className="form-grid">
            <Field label="Name">
              <input
                autoFocus
                required
                value={demoLabel(name, profile.isDemo)}
                onChange={(event) => setName(event.target.value)}
                maxLength={240}
                autoComplete="name"
              />
            </Field>
            <Field label="Date of birth · optional">
              <input
                type="date"
                value={birthDate}
                max={localDay()}
                onChange={(event) => setBirthDate(event.target.value)}
                autoComplete="bday"
              />
            </Field>
            <Field label="Allergies">
              <textarea
                rows={4}
                value={demoLabel(allergies, profile.isDemo)}
                onChange={(event) => setAllergies(event.target.value)}
                maxLength={12000}
                placeholder="Substance and reaction, if known"
              />
            </Field>
            <Field label="Medications">
              <textarea
                rows={4}
                value={demoLabel(medications, profile.isDemo)}
                onChange={(event) => setMedications(event.target.value)}
                maxLength={12000}
                placeholder="Name, dose, and how you take it"
              />
            </Field>
            <Field label="Conditions">
              <textarea
                rows={4}
                value={demoLabel(conditions, profile.isDemo)}
                onChange={(event) => setConditions(event.target.value)}
                maxLength={12000}
                placeholder="Conditions you want to keep in view"
              />
            </Field>
            <Field label="Surgeries & implants">
              <textarea
                rows={4}
                value={demoLabel(procedures, profile.isDemo)}
                onChange={(event) => setProcedures(event.target.value)}
                maxLength={12000}
                placeholder="Procedure or implant, location, and date"
              />
            </Field>
            <div className="field-full">
              <Field label="Care notes">
                <textarea
                  rows={4}
                  value={demoLabel(notes, profile.isDemo)}
                  onChange={(event) => setNotes(event.target.value)}
                  maxLength={12000}
                  placeholder="Anything else you want handy at an appointment"
                />
              </Field>
            </div>
          </div>
          {error && (
            <p className="inline-error" role="alert">
              {error}
            </p>
          )}
          <div className="form-actions">
            <Button variant="secondary" onClick={close} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !name.trim()}>
              {saving ? 'Saving…' : 'Save profile'}
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
