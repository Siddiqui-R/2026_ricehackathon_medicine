# Browser client implementation contract

Requested September 12: wrap Reva for browser use and fully adapt the layout for desktop, with MyChart-inspired organization and the current heart-red Reva palette (user confirmed during browser implementation). SwiftUI remains the native interface; React/TypeScript renders browser screens against the existing Swift/Vapor API. No production deployment or provider activation is part of local implementation.

## Shared modules and ownership

- Core contributor owns `apps/web/src/core/**` and domain/API tests. Mirror current Swift Codable JSON exactly. Export types from `core/models.ts`, helpers from `core/domain.ts`, provider API from `core/api.ts`, persistence from `core/repository.ts`, and React context from `core/RevaContext.tsx`.
- Records contributor owns `features/records/**` and `features/profile/**`, including imports/OCR and structured symptom editing. Exports `RecordsPage`, `RecordDetail`, `ImportDialog`, `SymptomDialog`, `MedicalProfilePage` from their named files.
- Visits contributor owns `features/visits/**`, including visit editing, reports, booking, recording/transcript/memory. Exports `VisitsPage` and `VisitDetail` from their named files.
- Integration owns project setup, shared components, shell/navigation, dashboard, settings, CSS, browser QA, documentation and Git checkpoints. Contributors do not edit these files.

## UI contract

`useReva()` supplies:

```
snapshot: AppSnapshot | null; loading: boolean; error: string | null;
notice: string | null; busy: boolean;
mutate(change: (draft: AppSnapshot) => void): Promise<void>;
notify(message: string): void; reportError(error: unknown): void; clearFeedback(): void;
resetDemo(): Promise<void>;
saveRecord(record: MedicalRecord, expectedVersion?: number): Promise<void>;
deleteRecord(id: string): Promise<void>;
saveVisit(visit: Visit): Promise<void>;
summarizeRecord(id: string): Promise<void>;
prepareVisit(id: string): Promise<void>;
saveMemory(recordingID: string): Promise<void>;
transcribeRecording(id: string): Promise<void>;
startCall(request: BookingRequest): Promise<void>;
refreshCall(requestID: string): Promise<void>;
providers: ProviderStatus | null;
connectedAI: boolean; setConnectedAI(value: boolean): void;
token: string; setToken(value: string): void;
serverRevision: number | null;
checkServer(): Promise<void>; pushToServer(): Promise<void>; pullFromServer(): Promise<void>;
```

API uses same-origin `/v1` and `/health`; Vite development and the provided production launcher proxy only these paths to an explicitly configured loopback Swift server. Credentials stay in memory. No arbitrary destination proxy, wildcard CORS or browser provider secrets. `checkServer` discovers capabilities and owner revision without replacing local data. Push requires known revision; conflicts preserve local state. Pull is explicit and obtains originals before publishing the snapshot. Local persistence uses IndexedDB and atomic snapshot writes, with errors surfaced and no silent reset of corrupt data.

`repository.ts`: `saveAttachment(filename: string, blob: Blob): Promise<void>`, `getAttachment(filename: string): Promise<Blob>` (IndexedDB first, then `/demo/<encoded safe name>` for bundled originals). Original file naming remains compatible with native safe leaf names; server IDs are SHA256 of filename. Keep uploads <=16MiB.

`domain.ts`: exports `uid()`, `nowISO()`, `formatDate(text, withTime?, zone?)`, `durationLabel(seconds)`, `localExcerpt(text)`, `makeSymptomRecord(entry, existing?)`, `reportIsStale(visit, records): Promise<boolean>`, `generateReport(visit, records): Promise<VisitReport>`, `validateSnapshot(value): AppSnapshot`. Preserve original quotes, source/page/version identity, local date-only display and questions/notes authority. Use native-compatible signatures where possible and explicitly document any cross-client differences.

`components/ui.tsx` supplies `Button` (variant primary/secondary/ghost/danger), `Card` (className, children), `Badge` (tone neutral/review/accent), `Modal` (title, onClose, children, wide?), `EmptyState` (title, children), `Field` (label, children, hint?), `PageHeading` (eyebrow?, title, description?, actions?), `Icon` through lucide-react imports directly. All accept ordinary React content. Native dialog handles keyboard focus/Escape, scroll containment and labeled heading. CSS classes: `form-grid`, `field-full`, `form-actions`, `stack`, `row`, `muted`, `small`, `text-link`, `section-heading`, `record-list`, `record-row`, `record-icon`, `record-main`, `record-meta`, `detail-grid`, `prose`, `divider`, `chip-list`, `inline-error`, `visits-grid`. Root will style these and contributor-specific classes after integration.

Routing uses hashes and links: `#/summary`, `#/records`, `#/records/<id>`, `#/visits`, `#/visits/<id>`, `#/profile`, `#/settings`. Detail pages receive `{id: string}`. `RecordsPage` accepts optional `{initialAction?: 'import' | 'symptom'}`; shell may route `#/records?add=import` or `?add=symptom`. Shared dialogs accept `{onClose: () => void}`; SymptomDialog optionally `{record?: MedicalRecord}`. All user strings and record contents render as text, never unsanitized HTML.

## Required behavior and bounds

Every new source file has Purpose/Inputs/Outputs/Side effects plus named logical-block comments. Responsive desktop sidebar, tablet compact layout and phone navigation; no horizontal page overflow at 375px. Exact blush ivory #FBF7F5 canvas, white #FFFFFF outlined cards, heart red #B84250 actions, deep red #8C2F3B small accent text, petal #FAE6E5 fills, and linen #DBCBC9 borders. No invented messages, bills or provider capabilities. Medical profile is persistent quick-reference data; symptom records participate in preparation.

Document intake retains originals and supports text, PDF page extraction, and reviewed browser OCR for scans/images. Load OCR resources locally from bundled assets; never send content to a third party for local extraction. Bound files/pages/text/workers and permit cancellation. Failed/uncertain extraction remains reviewable. Microphone uses browser capability checks and consent; stop tracks on cleanup and pause on page hiding. Preserve new captured audio separately from fictional transcripts. Print/save-to-PDF exports only the report, with citations and stale-report guard.

All connected operations call existing Swift endpoints and require explicit configuration/user actions. Local simulation never makes calls. Live call UI requires final reviewed consent; durable request identity and unknown-outcome handling match native behavior. No provider smoke with real credentials or actual clinic calls.
