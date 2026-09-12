// Purpose: Supply distinct browser demo people without mixing their saved workspaces or source identities.
// Inputs: A whitelisted URL demo ID and the existing Jordan seed.
// Outputs: Independent demo database names and valid example snapshots.
// Side effects: None; switching is a normal navigation and persistence belongs to the repository.
import type { AppSnapshot, MedicalRecord, PatientProfile, Visit } from './models';
import { localExcerpt } from './domain';

// MARK: - Stable demo identities keep existing Jordan data in its original database
export const demoPeople = [
  { id: 'jordan', name: 'Jordan Avery', initials: 'JA', description: 'Primary care and symptom follow-up' },
  {
    id: 'maya',
    name: 'Maya Patel',
    initials: 'MP',
    description: 'Headache patterns and neurology preparation',
  },
  { id: 'alex', name: 'Alex Chen', initials: 'AC', description: 'Knee recovery and physical therapy' },
] as const;
export type DemoPersonID = (typeof demoPeople)[number]['id'];
export function selectedDemoPerson(search = globalThis.location?.search ?? ''): DemoPersonID {
  const value = new URLSearchParams(search).get('demo');
  return demoPeople.find((person) => person.id === value)?.id ?? 'jordan';
}
export function demoDatabaseName(id: DemoPersonID): string {
  return id === 'jordan' ? 'reva-workspace-v1' : `reva-demo-${id}-v1`;
}
export function demoPersonURL(id: DemoPersonID, current: string): string {
  const url = new URL(current);
  url.searchParams.set('demo', id);
  url.hash = '/summary';
  return url.href;
}

// MARK: - New examples use their own authored notes, never another person's original documents
export function demoSnapshot(base: AppSnapshot, id: DemoPersonID): AppSnapshot {
  if (id === 'jordan') return structuredClone(base);
  const person = demoPeople.find((person) => person.id === id)!;
  const isMaya = id === 'maya';
  const profile: PatientProfile = {
    id: `demo-profile-${id}`,
    name: person.name,
    initials: person.initials,
    dateOfBirth: isMaya ? '1997-03-22' : '1983-11-08',
    isDemo: true,
    allergies: isMaya ? ['No known allergies recorded'] : ['Adhesive tape — skin irritation'],
    medications: [],
    conditions: isMaya ? ['Recurring headaches'] : ['Left knee recovery after ACL reconstruction'],
    surgeriesAndImplants: isMaya ? [] : ['Left ACL reconstruction, July 2026'],
    careNotes: isMaya
      ? 'Discuss headache frequency and its effect on work.'
      : 'Review recovery goals and return to usual activities.',
  };
  const entries = isMaya
    ? ([
        [
          'Headache pattern — September',
          'Symptoms',
          'Headaches occurred on three afternoons this week. Bright office lighting was bothersome. Resting in a quiet room helped. Duration ranged from one to three hours.',
          ['headache', 'neurology', 'symptoms'],
        ],
        [
          'Sleep and daily routine',
          'Notes',
          'Sleep has varied between six and eight hours. Two headache days followed late nights. No consistent food-related pattern has been identified.',
          ['headache', 'sleep', 'routine'],
        ],
        [
          'Previous headache appointment',
          'Visit',
          'A prior primary-care visit discussed recurring headaches. The patient was asked to bring a record of timing, duration and associated symptoms to the next appointment.',
          ['headache', 'primary care', 'follow-up'],
        ],
      ] as const)
    : ([
        [
          'Knee recovery notes',
          'Notes',
          'Left ACL reconstruction was completed in July 2026. The next orthopedic visit will review recovery progress and questions about returning to usual activities.',
          ['knee', 'surgery', 'orthopedics'],
        ],
        [
          'Physical therapy update',
          'Visit',
          'Physical therapy sessions have focused on mobility and strength. The patient reports that stairs are becoming easier, with stiffness after long periods sitting.',
          ['knee', 'physical therapy', 'mobility'],
        ],
        [
          'Activity and symptoms',
          'Symptoms',
          'The left knee feels stiff in the morning and after sitting. The patient wants to discuss walking distance and the recovery timeline at the next visit.',
          ['knee', 'stiffness', 'symptoms'],
        ],
      ] as const);
  const records: MedicalRecord[] = entries.map(([title, kind, text, tags], index) => ({
    id: `demo-${id}-record-${index + 1}`,
    title,
    kind: kind === 'Symptoms' ? 'Notes' : kind,
    provider:
      index === 2 && isMaya
        ? 'Dr. Leah Brooks'
        : index === 1 && !isMaya
          ? 'Cedar Physical Therapy'
          : 'Personal health notes',
    date: `2026-09-0${9 - index}`,
    uploadedAt: '2026-09-12T12:00:00Z',
    tags: [...tags],
    text,
    summary: localExcerpt(text, true),
    pageCount: 1,
    status: 'ready',
    notes: '',
    isDemo: true,
    version: 1,
  }));
  const visit: Visit = {
    id: `demo-${id}-visit`,
    title: isMaya ? 'Headache follow-up' : 'Knee recovery follow-up',
    type: isMaya ? 'Neurology' : 'Orthopedics',
    provider: isMaya ? 'Dr. Leah Brooks' : 'Dr. Evan Park',
    clinic: isMaya ? 'Maple Neurology' : 'Cedar Orthopedics',
    date: '2026-09-17T10:00:00-05:00',
    timeZone: 'America/Chicago',
    concern: isMaya ? 'Recurring headaches affecting work' : 'Knee stiffness during recovery',
    goal: isMaya
      ? 'Understand headache patterns and discuss next steps'
      : 'Review recovery progress and activity goals',
    questions: isMaya
      ? [
          'What details should I track about my headaches?',
          'What should we discuss about their effect on work?',
        ]
      : ['How is my recovery progressing?', 'What should I discuss with my physical therapist next?'],
    pinnedRecordIDs: [records[0].id],
    notes: '',
    status: 'upcoming',
  };
  return {
    schemaVersion: base.schemaVersion,
    profile,
    records,
    visits: [visit],
    bookings: [],
    recordings: [],
  };
}
