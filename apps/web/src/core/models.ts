// Purpose: Mirror the native Swift Codable persistence and API contracts.
// Inputs: Validated JSON and user-authored domain values.
// Outputs: Shared TypeScript types used by browser features and repositories.
// Side effects: None; credentials and provider keys are never persisted in these values.

// MARK: - Profile and source observations.
export interface PatientProfile {
  id: string;
  name: string;
  dateOfBirth: string;
  initials: string;
  allergies: string[];
  medications: string[];
  conditions: string[];
  isDemo: boolean;
  surgeriesAndImplants?: string[] | null;
  careNotes?: string | null;
}
export interface SymptomEntry {
  observedAt: string;
  timeZone: string;
  symptom: string;
  severity?: string | null;
  duration: string;
  details: string;
  triggers: string;
  whatHelped: string;
}
export interface MedicalRecord {
  id: string;
  title: string;
  kind: string;
  provider: string;
  date: string;
  uploadedAt: string;
  tags: string[];
  text: string;
  summary: string;
  sourceFilename?: string | null;
  mimeType?: string | null;
  pageCount: number;
  status: string;
  notes: string;
  isDemo: boolean;
  version: number;
  pageTexts?: string[] | null;
  sourceRecordingID?: string | null;
  summaryModel?: string | null;
  symptomEntry?: SymptomEntry | null;
}

// MARK: - Appointments and source-grounded briefs.
export interface SourceReference {
  recordID: string;
  page: number;
  excerpt: string;
  sourceVersion?: number | null;
}
export interface ReportSection {
  id: string;
  title: string;
  body: string;
  sources: SourceReference[];
}
export interface VisitReport {
  id: string;
  visitID: string;
  createdAt: string;
  sourceSignature: string;
  sections: ReportSection[];
  questions: string[];
  notes: string;
  selectedRecordIDs: string[];
  isDemo: boolean;
  generationModel?: string | null;
}
export interface Visit {
  id: string;
  title: string;
  type: string;
  provider: string;
  clinic: string;
  date: string;
  timeZone: string;
  concern: string;
  goal: string;
  questions: string[];
  pinnedRecordIDs: string[];
  notes: string;
  status: string;
  report?: VisitReport | null;
}
export interface BookingRequest {
  id: string;
  visitID: string;
  clinic: string;
  phone: string;
  reason: string;
  earliest: string;
  latest: string;
  timeZone: string;
  preferences: string;
  status: string;
  scenario: string;
  createdAt: string;
  confirmedVisitID?: string | null;
  isLive?: boolean | null;
  providerConversationID?: string | null;
  providerTranscript?: string | null;
}

// MARK: - Audio, transcript and aggregate contracts.
export interface TranscriptSegment {
  id: string;
  speaker: string;
  start: number;
  end: number;
  text: string;
}
export interface VisitRecording {
  id: string;
  visitID: string;
  title: string;
  createdAt: string;
  duration: number;
  audioFilename?: string | null;
  segments: TranscriptSegment[];
  summary: string;
  isSample: boolean;
  status: string;
  transcriptionModel?: string | null;
}
export interface AppSnapshot {
  schemaVersion: number;
  profile: PatientProfile;
  records: MedicalRecord[];
  visits: Visit[];
  bookings: BookingRequest[];
  recordings: VisitRecording[];
}
export interface ServerState {
  revision: number;
  snapshot: AppSnapshot;
}

// MARK: - Public provider status and action responses.
export interface ProviderCapability {
  configured: boolean;
  model: string;
}
export interface ProviderStatus {
  gemini: ProviderCapability;
  transcription: ProviderCapability;
  booking: ProviderCapability;
  liveCallsEnabled: boolean;
}
export interface AISummary {
  summary: string;
  model: string;
}
export interface AIPreparation {
  overview: string;
  questions: string[];
  selectedRecordIDs: string[];
  model: string;
}
export interface AudioTranscription {
  text: string;
  segments: TranscriptSegment[];
  model: string;
}
export interface LiveCallResult {
  conversationID: string;
  status: string;
  provider: string;
  transcript?: string | null;
}
export interface LiveCallInput {
  requestID: string;
  clinic: string;
  phone: string;
  reason: string;
  earliest: string;
  latest: string;
  timeZone: string;
  preferences: string;
  patientName: string;
  consent: boolean;
}
