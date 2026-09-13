// Purpose: Keep persistent overarching health information together in an editable quick-reference profile.
// Inputs: PatientProfile from the local snapshot and user-authored identity/medical field edits.
// Outputs: Editable health cards with report provenance and automatic update status.
// Side effects: Saves manual corrections through the aggregate mutation boundary; never rewrites documents.

import { useState, type FormEvent } from 'react';
import {
  CalendarDays,
  HeartPulse,
  NotebookPen,
  Pencil,
  Pill,
  ShieldAlert,
  Stethoscope,
  UserRound,
} from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import { useMedicalProfileUpdate } from '../../core/MedicalProfileUpdates';
import { formatDate } from '../../core/domain';
import { demoLabel } from '../../core/presentation';
import type { MedicalProfileField, PatientProfile } from '../../core/models';
import { Button, Card, Field, Modal } from '../../components/ui';
import { localDay } from '../records/recordPresentation';

type ProfileSection =
  'identity' | 'allergies' | 'medications' | 'conditions' | 'surgeriesAndImplants' | 'careNotes';
const sectionTitles: Record<ProfileSection, string> = {
  identity: 'Personal details',
  allergies: 'Allergies',
  medications: 'Medications',
  conditions: 'Conditions',
  surgeriesAndImplants: 'Surgeries & implants',
  careNotes: 'Care notes',
};

// MARK: - Profile cards describe only supplied information, including unspecified fields
export function MedicalProfilePage() {
  const { snapshot } = useReva();
  const update = useMedicalProfileUpdate();
  const [editing, setEditing] = useState<ProfileSection | null>(null);
  const profile = snapshot?.profile;
  if (!profile)
    return (
      <Card>
        <p>Opening your medical profile…</p>
      </Card>
    );
  const sections = [
    { key: 'allergies' as const, title: 'Allergies', icon: ShieldAlert, items: profile.allergies },
    { key: 'medications' as const, title: 'Medications', icon: Pill, items: profile.medications },
    { key: 'conditions' as const, title: 'Conditions', icon: HeartPulse, items: profile.conditions },
    {
      key: 'surgeriesAndImplants' as const,
      title: 'Surgeries & implants',
      icon: Stethoscope,
      items: profile.surgeriesAndImplants ?? [],
    },
  ];
  const sources = (field: MedicalProfileField, text: string) => {
    const fact = profile.aiMedicalHistory?.facts[field].find((item) => item.text === text);
    const reports =
      fact?.recordIDs
        .map((id) => snapshot?.records.find((record) => record.id === id))
        .filter((record) => !!record) ?? [];
    return reports.length ? (
      <span className="small muted" style={{ display: 'block' }}>
        From{' '}
        {reports.map((record, index) => (
          <span key={record.id}>
            {index > 0 && ', '}
            <a href={`#/records/${encodeURIComponent(record.id)}`}>
              {demoLabel(record.title, record.isDemo)}
            </a>
          </span>
        ))}
      </span>
    ) : null;
  };
  return (
    <div className="profile-page stack">
      <header className="profile-heading">
        <h1>Medical profile</h1>
        <div className="profile-header-identity">
          <span className="avatar" aria-hidden="true">
            {profile.initials || <UserRound size={20} />}
          </span>
          <div className="profile-header-person">
            <strong>{demoLabel(profile.name, profile.isDemo)}</strong>
            <span>
              <CalendarDays size={13} aria-hidden="true" />
              {profile.dateOfBirth ? `Born ${formatDate(profile.dateOfBirth)}` : 'Date of birth not provided'}
            </span>
          </div>
          <Button
            variant="ghost"
            className="icon-button profile-edit"
            aria-label="Edit personal details"
            title="Edit personal details"
            onClick={() => setEditing('identity')}
          >
            <Pencil size={16} />
          </Button>
        </div>
      </header>
      <p className="small muted" role="status" aria-live="polite">
        {update.message}
        {profile.aiMedicalHistory?.generatedAt &&
          update.status === 'current' &&
          ` Last updated ${formatDate(profile.aiMedicalHistory.generatedAt)}.`}
      </p>
      <div className="profile-grid">
        {sections.map((section) => (
          <Card key={section.title} className="profile-section stack">
            <div className="profile-section-heading">
              <span className="record-icon">
                <section.icon size={22} />
              </span>
              <h2>{section.title}</h2>
              <Button
                variant="ghost"
                className="icon-button profile-edit"
                aria-label={`Edit ${section.title.toLowerCase()}`}
                title={`Edit ${section.title.toLowerCase()}`}
                onClick={() => setEditing(section.key)}
              >
                <Pencil size={16} />
              </Button>
            </div>
            {section.items.length ? (
              <ul className="profile-items">
                {section.items.map((item, index) => (
                  <li key={`${index}-${item}`} className="prose">
                    {demoLabel(item, profile.isDemo)}
                    {sources(section.key, item)}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="muted">Not provided</p>
            )}
          </Card>
        ))}
      </div>
      <Card className="profile-section stack">
        <div className="profile-section-heading">
          <span className="record-icon">
            <NotebookPen size={22} />
          </span>
          <h2>Care notes</h2>
          <Button
            variant="ghost"
            className="icon-button profile-edit"
            aria-label="Edit care notes"
            title="Edit care notes"
            onClick={() => setEditing('careNotes')}
          >
            <Pencil size={16} />
          </Button>
        </div>
        {profile.careNotes ? (
          profile.careNotes
            .split('\n')
            .filter(Boolean)
            .map((line, index) => (
              <p className="prose" key={index}>
                {demoLabel(line, profile.isDemo)}
                {sources('careNotes', line)}
              </p>
            ))
        ) : (
          <p className="muted">Not provided</p>
        )}
      </Card>
      <p className="small muted">
        AI updates documented medical details when reports are added, edited, or removed. Your own entries and
        corrections are preserved. Review these details against the linked reports; profile edits do not
        change historical documents.
      </p>
      {editing && (
        <ProfileEditor key={editing} section={editing} profile={profile} onClose={() => setEditing(null)} />
      )}
    </div>
  );
}

// MARK: - Line-based editing preserves absent fields and detects concurrent profile changes
function ProfileEditor({
  profile,
  section,
  onClose,
}: {
  profile: PatientProfile;
  section: ProfileSection;
  onClose: () => void;
}) {
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
    section === 'identity'
      ? name !== original.name || birthDate !== original.dateOfBirth
      : { allergies, medications, conditions, surgeriesAndImplants: procedures, careNotes: notes }[
          section
        ] !== (section === 'careNotes' ? (original.careNotes ?? '') : (original[section] ?? []).join('\n'));
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
      if (section === 'identity' && !trimmed)
        throw new Error('Add your name before saving your medical profile.');
      if (
        section === 'identity' &&
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
        const keys: (keyof PatientProfile)[] = section === 'identity' ? ['name', 'dateOfBirth'] : [section];
        if (keys.some((key) => JSON.stringify(draft.profile[key]) !== JSON.stringify(original[key])))
          throw new Error(
            'This section changed while you were editing. Close and reopen it to see the latest details.',
          );
        // Only the selected fields are replaced; concurrent edits to other sections remain intact.
        switch (section) {
          case 'identity':
            Object.assign(draft.profile, { name: trimmed, dateOfBirth: birthDate, initials });
            break;
          case 'allergies':
            draft.profile.allergies = list(allergies);
            break;
          case 'medications':
            draft.profile.medications = list(medications);
            break;
          case 'conditions':
            draft.profile.conditions = list(conditions);
            break;
          case 'surgeriesAndImplants':
            draft.profile.surgeriesAndImplants = surgeries.length ? surgeries : null;
            break;
          case 'careNotes':
            draft.profile.careNotes = notes.trim() || null;
            break;
        }
      });
      notify(`${sectionTitles[section]} saved.`);
      onClose();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'The medical profile could not be saved.');
    } finally {
      setSaving(false);
    }
  };
  return (
    <Modal title={`Edit ${sectionTitles[section].toLowerCase()}`} onClose={close}>
      {discard ? (
        <div className="stack">
          <p>Discard your unsaved changes?</p>
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
            {section === 'identity'
              ? 'Keep your personal details up to date.'
              : section === 'careNotes'
                ? 'Keep any details you want handy at an appointment.'
                : 'Put one item on each line. Leave blank if not provided.'}
          </p>
          <div className={section === 'identity' ? 'form-grid' : 'stack'}>
            {section === 'identity' && (
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
            )}
            {section === 'identity' && (
              <Field label="Date of birth · optional">
                <input
                  type="date"
                  value={birthDate}
                  max={localDay()}
                  onChange={(event) => setBirthDate(event.target.value)}
                  autoComplete="bday"
                />
              </Field>
            )}
            {section === 'allergies' && (
              <Field label="Allergies">
                <textarea
                  autoFocus
                  rows={4}
                  value={demoLabel(allergies, profile.isDemo)}
                  onChange={(event) => setAllergies(event.target.value)}
                  maxLength={12000}
                  placeholder="Substance and reaction, if known"
                />
              </Field>
            )}
            {section === 'medications' && (
              <Field label="Medications">
                <textarea
                  autoFocus
                  rows={4}
                  value={demoLabel(medications, profile.isDemo)}
                  onChange={(event) => setMedications(event.target.value)}
                  maxLength={12000}
                  placeholder="Name, dose, and how you take it"
                />
              </Field>
            )}
            {section === 'conditions' && (
              <Field label="Conditions">
                <textarea
                  autoFocus
                  rows={4}
                  value={demoLabel(conditions, profile.isDemo)}
                  onChange={(event) => setConditions(event.target.value)}
                  maxLength={12000}
                  placeholder="Conditions you want to keep in view"
                />
              </Field>
            )}
            {section === 'surgeriesAndImplants' && (
              <Field label="Surgeries & implants">
                <textarea
                  autoFocus
                  rows={4}
                  value={demoLabel(procedures, profile.isDemo)}
                  onChange={(event) => setProcedures(event.target.value)}
                  maxLength={12000}
                  placeholder="Procedure or implant, location, and date"
                />
              </Field>
            )}
            <div className="field-full">
              {section === 'careNotes' && (
                <Field label="Care notes">
                  <textarea
                    autoFocus
                    rows={4}
                    value={demoLabel(notes, profile.isDemo)}
                    onChange={(event) => setNotes(event.target.value)}
                    maxLength={12000}
                    placeholder="Anything else you want handy at an appointment"
                  />
                </Field>
              )}
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
            <Button type="submit" disabled={saving || (section === 'identity' && !name.trim())}>
              {saving ? 'Saving…' : 'Save changes'}
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
