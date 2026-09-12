# Track 04 — Native feature UI and user flows (source review, wave A)

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip` (frozen worktree `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`).
Reviewer: Track 04 worker (Fable 5.1). Read-only source review; no builds, simulators, listeners or live services were used. Runner evidence directory contained no `commands.jsonl` at review time, so every disposition below rests on source tracing, and every native runtime UI journey is marked Unverified.

## 1. Scope and inventory

### 1.1 Files fully read (inventoried), worktree-relative under `apps/ios/Reva/`

| Area | File | Lines |
| --- | --- | --- |
| Preparation | `Features/Preparation/ReportEditorView.swift` | 45 |
| Preparation | `Features/Preparation/ReportView.swift` | 135 |
| Preparation | `Features/Preparation/VisitDetailView.swift` | 172 |
| Preparation | `Features/Preparation/VisitEditorView.swift` | 119 |
| Preparation | `Features/Preparation/VisitsView.swift` | 62 |
| Profile | `Features/Profile/MedicalProfileEditor.swift` | 119 |
| Profile | `Features/Profile/MedicalProfileView.swift` | 113 |
| Records | `Features/Records/AddRecordView.swift` | 291 |
| Records | `Features/Records/RecordDetailView.swift` | 156 |
| Records | `Features/Records/RecordEditorView.swift` | 77 |
| Records | `Features/Records/RecordsView.swift` | 90 |
| Records | `Features/Records/SourcePreview.swift` | 116 |
| Records | `Features/Records/SymptomEntryDetailsView.swift` | 46 |
| Records | `Features/Records/SymptomEntryEditorView.swift` | 140 |
| Shared | `Features/Shared/RecordRow.swift` | 32 |
| Shared | `Features/Shared/RootView.swift` | 71 |
| Shared | `Features/Shared/SettingsView.swift` | 128 |
| Shared | `Features/Shared/SummaryView.swift` | 154 |
| Shared | `Features/Shared/Theme.swift` | 46 |
| Shared | `Features/Shared/ViewComponents.swift` | 133 |
| Shared | `Features/Shared/VisitRow.swift` | 25 |
| Shared | `Features/Shared/WelcomeView.swift` | 36 |
| State | `State/AppStore+AI.swift` | 89 |
| State | `State/AppStore+Profile.swift` | 42 |
| State | `State/AppStore+Records.swift` | 37 |
| State | `State/AppStore+Symptoms.swift` | 42 |
| State | `State/AppStore+Visits.swift` | 33 |
| State (shared core, fully read because every assigned flow routes through it) | `State/AppStore.swift` | 143 |

Total: 28 files, 2,649 lines fully read. Every line cited in this report and in `track-04-findings.json` was re-checked with `sed -n` against the frozen worktree.

### 1.2 Files consulted or sampled only (not reviewed for defects)

- `apps/ios/Reva/Core/Models.swift` (RevaDate, MedicalRecord, Visit, AppSnapshot.validate, safeFilename), `Core/SymptomEntry.swift`, `Core/ReportEngine.swift` (signature/isStale/generate), `Core/LocalRepository.swift` (atomic save, attachment bounds) — read as contracts for the flows above.
- `apps/ios/Reva/Device/ReportPDFRenderer.swift` (lines 100-210 sampled for E05 export content and palette), `Device/DocumentImportService.swift` (lines 12-38, 142-152, 288, 320-372 sampled for kind/MIME, filename bounds and cancellation).
- `apps/ios/Reva/State/AppStore+Sync.swift` and `State/AppStore+Providers.swift` (error-surface lines only), `State/AppStore+LiveCalls.swift`/`+Transcription.swift` (grep for `errorMessage` only), `RevaApp.swift` (tint and color scheme), `Resources/seed.json` (visit dates), `Package.swift` (RevaCore test target), `Tests/RevaCoreTests/{DomainTests,SymptomEntryTests,MedicalProfileTests,LiveServerTests}` (existing coverage and live-test gating), `design/palette.json`.
- Browser parity references: `apps/web/src/features/visits/{visitDates.ts,VisitEditor.tsx,VisitsPage.tsx}`, `apps/web/src/features/records/RecordsPage.tsx` (lines 46-72), `apps/web/src/App.tsx` and `features/profile/MedicalProfilePage.tsx` (isDemo lines only).
- Not read at all: `Features/Visits/**` (booking/recording UI, Track 05+), `Features/Onboarding` if any, `Device/**` beyond the two files above, server and browser code beyond the parity lines listed.
- Not read by rule: any `.env`, keychain, live main-checkout application files, real patient storage. No credential-like values were encountered in the reviewed files.

### 1.3 Method

Each screen action was traced view → `AppStore` extension → `mutate`/`perform` → `LocalRepository` and back to the published projection, with attention to back/cancel/empty/failure paths, ghost records on failed save, staleness after source/goal/pin changes, late-AI overwrite in both directions, PDF export content, exact palette usage through `RevaTheme`, and VoiceOver/Dynamic Type affordances. For each candidate I attempted a refutation (looking for a guard, a rebase, a normalization step or a test that already covers the case) before recording it; refuted candidates are listed in section 6.

## 2. Checklist dispositions

Legend: Pass = source-proven correct on the assigned paths; Defect = a finding in section 3; Unverified = requires runtime evidence not available to this track (no simulator permitted); WIP = not present in snapshot; Deferred/Not applicable as stated.

### C01 — Native screens, flows, back/cancel/empty/failure handling
**Disposition: Defect (candidate), runtime Unverified.**
- Navigation shell: `RootView.swift:31-48` four tabs; `34-39` "View all records" resets the Records stack via `recordsGeneration` and `.id(recordsGeneration)`; `SummaryView.swift:123-130` triggers it. Welcome sheet `RootView.swift:59-65`; startup recovery screen `RootView.swift:21-29` fed by `AppStore.startupError` (`AppStore.swift:86`).
- Empty states: Records `RecordsView.swift:60-64` (`ContentUnavailableView.search`), Visits `VisitsView.swift:28-31`, Report `ReportView.swift:88-89` ("No brief yet"); symptom details render only populated fields (`SymptomEntryDetailsView.swift:25-29`).
- Failure boundary: `AppStore.perform` (`AppStore.swift:119-127`) routes thrown errors to `errorMessage`; the sole presenter is the root alert (`RootView.swift:50-58`). Because Settings, all five editors and intake are presented as `.sheet`, failures raised while a sheet is up are at risk of not being shown — RVA-04-002 (candidate, P2, medium confidence; ER-04-02 requested). Only the symptom editor shows inline errors (`SymptomEntryEditorView.swift:105-110,133-139`).
- Cancel/discard: consistent `dismiss()` with no persistence before Save, so no ghost records; discard confirmation exists only in the symptom editor — RVA-04-010 (suggestion). Silent no-op of "Create pre-visit brief" while the provider is busy — RVA-04-004 (candidate, P3).
- Runtime journeys (tap sequences, sheet/alert stacking, focus behavior): Unverified in this audit; evidence requests ER-04-02 and ER-04-04.

### C03 — Native records: upload, OCR review, originals preserved, editing and versioning
**Disposition: Pass (source-proven), runtime Unverified.**
- Intake paths `AddRecordView.swift:121-200`: file importer (`.fileImporter`, 121-125), PhotosPicker (127-138), VisionKit scanner rendered to PDF (139-165), demo files (174-200). All go through `DocumentImportService.ingest`, which produces `ImportedDocument` with original bytes, filename, MIME, SHA-256, page map and OCR warnings; nothing is persisted until Save (`AddRecordView.swift:263-281`: `repository.storeAttachment` then `MedicalRecord` construction then `store.save(record)` inside one `perform`), so a failed or cancelled review never leaves a ghost record.
- Save path: `AddRecordView.swift:264-266` writes the attachment via `LocalRepository.storeAttachment` (`LocalRepository.swift:51`) before `store.save(record)` (`AppStore+Records.swift:11-27`); if the snapshot save fails the attachment file is orphaned (unreferenced, never listed) but no record row exists. Edit path bumps `version` only when brief-relevant fields change (`AppStore+Records.swift:20-24`), matching `ReportEngine.signature` inputs (`ReportEngine.swift:33-51`).
- `RecordDetailView.swift:46-58` shows the summary with its origin label (AI model vs local excerpt), `77` "Open original · page N" and `96-99` notes (where OCR warnings are stored at intake, `AddRecordView.swift:273`); `SourcePreview.swift` opens the preserved original via `store.sourceURL` and offers `ShareLink`.
- Notes: camera scans get kind "Notes" (RVA-04-006, candidate, D06-related); stale import error banner and non-cancelled extraction Task (RVA-04-014, suggestion).

### C04 — Native medical profile: view, edit, persist, demo labeling
**Disposition: Pass (source-proven), with one suggestion.**
- `MedicalProfileView.swift:22-77` renders name/DOB/allergies/medications/conditions/surgeries/care notes with "Not provided" fallbacks; `32-34` shows "Fictional demo profile" when `isDemo`.
- `MedicalProfileEditor.swift:44-50` DOB picker uses a UTC calendar consistent with `RevaDate.day`; `108-117` copies `profile`, applies trimmed fields, saves via `store.perform { try store.saveMedicalProfile(edited) }`.
- `AppStore+Profile.swift:11-35` normalizes whitespace, rejects an empty name, guards the profile id, and touches only `data.profile`; `MedicalProfileTests` cover normalization.
- `isDemo` persists after real edits (RVA-04-013, suggestion). No defect.

### C05 — Profile and records feed preparation coherently; profile save does not disturb records/visits
**Disposition: Pass (source-proven).**
- `ReportEngine.generate` consumes `records` only (`AppStore+Visits.swift:26-31`; `AppStore+AI.swift:44-60` builds the AI request from the same pool). Profile data does not enter brief generation, so profile edits cannot stale a brief (consistent with `ReportEngine.signature` omitting profile).
- Profile save mutates only `data.profile` (`AppStore+Profile.swift:26-33`); records and visits are untouched. Record save/edit never touches visits; staleness is computed, not stored (`ReportEngine.isStale`, `ReportView.swift:84-85`).

### C06 — Native symptom entries: create, edit, detail, search, contribute to briefs
**Disposition: Pass (source-proven), runtime Unverified.**
- `SymptomEntryEditorView.swift:45-100` collects symptom, severity, onset, duration, notes; `133-139` saves through `store.addSymptomEntry`/`updateSymptomEntry` with inline error; `AppStore+Symptoms.swift:11-41` builds a `MedicalRecord` with `kind == "User symptom entry"`, versioned text, and `symptomEntry` payload; `SymptomEntryTests` cover text rendering.
- `SymptomEntryDetailsView.swift` renders the structured entry; `RecordDetailView.swift` offers "Edit entry" for symptom records and the record editor for others.
- Entries are `MedicalRecord`s, so `ReportEngine` and the AI path include them automatically; search covers title/text/summary/tags (`RecordsView.swift:29-32`).
- Minor: `@FocusState symptomFocused` never set (RVA-04-009 item e); discard confirmation present here only (RVA-04-010).

### D04 — Failed save leaves no partial/ghost record; originals never lost
**Disposition: Pass (source-proven) with notes.**
- All writes go through `AppStore.mutate` (`AppStore.swift:111-116`): copy → `repository.save` (which validates, then atomically replaces with backup) → publish. A validation or I/O failure leaves the published snapshot unchanged.
- Intake stores the attachment before the snapshot write (`AddRecordView.swift:264-266` → `LocalRepository.swift:51`); on failure the attachment file is orphaned but unreferenced — no ghost record, no lost original. `AddRecordView` keeps the `ImportedDocument` in memory until Save succeeds.
- Related: error visibility under sheets (RVA-04-002), stale error banner/extraction cancellation (RVA-04-014).

### D06 — Records list: filters, search, empty state, kind coherence
**Disposition: Pass with notes; one candidate.**
- `RecordsView.swift:18-20` filter chips (All, Labs, Imaging, Procedure, Notes, Scan, Recording, User symptom entry); `22-32` kind equality plus search over title, provider, tags, text, summary, ISO date and display date; `60-64` empty state.
- Parity gaps: native search does not include `kind` or `notes` (browser haystack `RecordsPage.tsx:59-66` includes kind); camera scans are filed as "Notes" so the "Scan" chip misses them and kind is not editable — RVA-04-006 (candidate, P3). The `ContentUnavailableView.search(text: filter)` wording shows the chip name as the "search" term when the query is empty (`RecordsView.swift:63`), a wording nit folded into RVA-04-006's fix note rather than a separate finding.

### E01 — Visits: create, edit, list ordering, time zones, status
**Disposition: Defect (confirmed) plus candidates.**
- `VisitEditorView.swift:99-117` saves `RevaDate.iso(date)` (UTC "Z") with the chosen `timeZone`; seed visits are stored with "-05:00" offsets (`Resources/seed.json:286,306,326`). `AppStore.visits` sorts raw strings (`AppStore.swift:98`) while `records` parses dates (`90-96`); mixed formats therefore misorder and `SummaryView.nextVisit` (`SummaryView.swift:20`) can pick the wrong visit — RVA-04-001 (confirmed, P2). Browser sorts by parsed epoch (`VisitsPage.tsx:28-35`).
- Zone picker changes the displayed instant rather than preserving wall-clock time, defaults to a literal "America/Chicago", and lists six zones — RVA-04-003 (candidate, P3).
- Editors save a stale full copy captured at open time, which can discard a concurrently generated brief/AI summary — RVA-04-005 (candidate, P3, medium).
- Past visits oldest-first and status-only "Upcoming" — RVA-04-011 (suggestion). No visit delete; notes only after brief — RVA-04-012 (suggestion).
- Status toggle `VisitDetailView.swift:146-150` persists via `perform`/`save(visit)`; `save(_:)` re-syncs `report.questions/notes` (`AppStore+Visits.swift:11-14`).

### E04 — Pre-visit brief: source-grounded generation, staleness, late-AI protection, question/notes preservation
**Disposition: Pass (source-proven for the protected direction), runtime Unverified.**
- Local generation `AppStore+Visits.swift:26-31`; AI generation `AppStore+AI.swift:34-87` snapshots the visit, computes the signature before the request, and discards the result if the visit's signature changed while awaiting (`51-56`); the same guard protects record summaries (`17-28`, keyed by record version). User-edited questions/notes are preserved across regeneration (`74-79`; `AppStore+Visits.swift:12-14`).
- Staleness: `ReportEngine.isStale` compares the stored `sourceSignature` against a fresh signature over visit type/concern/goal/date/pins and every record's id/version/title/date/text/summary/tags/status (`ReportEngine.swift:33-51`); `ReportView.swift:84-85` disables Share while stale and offers Regenerate. Existing `DomainTests` (lines 40-113) cover signature changes on source edits and pin changes; `apps/web/src/core/__tests__/domain.test.ts:19-21` asserts browser signatures match native goldens.
- Gaps: the reverse direction (a newer editor Save reverting a delayed AI result) — RVA-04-005; silent busy no-op — RVA-04-004.
- Runtime evidence request: ER-04-01 (RevaCore unit tests).

### E05 — PDF export content and gating
**Disposition: Unverified at runtime; source Pass, one style suggestion.**
- `ReportView.swift:98-126` `exportReport()` builds title, visit summary, each evidence section with "Source:" labels, questions, notes and a sources list with record versions; Share is disabled while stale (84-85), so an export cannot silently carry a superseded brief.
- `ReportPDFRenderer.swift` (sampled) paginates with UIGraphicsPDFRenderer; pagination/clipping of long quotations cannot be checked without rendering — ER-04-04 (deferred, simulator).
- Style: renderer still uses legacy teal `#0A5B6C` (`ReportPDFRenderer.swift:208-210`, applied at 126,133,141,181) — RVA-04-008 (suggestion; file is outside this track's path scope, flagged for dedup with the Device/native-core track).

### K01 — Exact heart palette usage through Theme.swift
**Disposition: Pass, one marginal suggestion.**
- `Theme.swift:13-19` defines canvas #FBF7F5, surface #FFFFFF, accent #B84250, accentText #8C2F3B, soft #FAE6E5, hairline #DBCBC9, matching `design/palette.json` and the supervisor brief. `RevaApp.swift:17-18` applies `.tint(RevaTheme.accent)` and `.preferredColorScheme(.light)`; grep over `Features/**` found no literal `Color(red:`/hex usage outside `Theme.swift`.
- Contrast (computed): deep red on petal 6.78:1, white on heart red 5.34:1, heart red on ivory 5.01:1, heart red on petal 4.45:1. The only small-text use of accent-on-petal is the question number badge (`ReportView.swift:55-56`) — RVA-04-007 (suggestion). ER-04-05 requests a scripted recomputation.

### K04 — Accessibility: VoiceOver labels, Dynamic Type, targets
**Disposition: Unverified at runtime; source review yields suggestions only.**
- Positive: image-only toolbar buttons are labeled (`RecordsView.swift:84`, `VisitsView.swift:57`, `MedicalProfileView.swift:83`, `SummaryView.swift:38,140`); filter chips expose `.isSelected` (`RecordsView.swift:53`); `IconTile` is `accessibilityHidden`; symptom fields carry labels; all text uses semantic text styles except Welcome.
- Gaps (RVA-04-009, suggestion): fixed-size badges with scaled text (`SummaryView.swift:137-139`, `MedicalProfileView.swift:26-29`, `ReportView.swift:55-56`, `ViewComponents.swift:79`), fixed `.system(size:)` on Welcome (`WelcomeView.swift:18,20`), 17pt dismiss target (`SummaryView.swift:34-38`), notices/inline errors not announced, unused `symptomFocused`, unlabeled decorative chevrons and image-only `ShareLink` (`SourcePreview.swift:32`).
- Accessibility Inspector/VoiceOver evidence would require a simulator, which this audit does not permit; no evidence request is filed because the runner is also barred from simulators, so K04 remains Unverified.

## 3. Findings

Full records (trigger/expected/actual/impact/evidence/fix/regression) are in `track-04-findings.json`. Summary:

| ID | Status | Sev | Title | File:line | Owner |
| --- | --- | --- | --- | --- | --- |
| RVA-04-001 | confirmed | P2 | Visit ordering compares raw ISO strings; offset-formatted seed vs Z-formatted user visits misorder; Summary may show wrong next visit | `apps/ios/Reva/State/AppStore.swift:98` | Captain / Person 2 |
| RVA-04-002 | candidate | P2 | Global error alert on RootView sits beneath modal sheets; Settings/editor failures may never be shown | `apps/ios/Reva/Features/Shared/RootView.swift:50` | Captain / P1 / P2 |
| RVA-04-003 | candidate | P3 | Zone picker shifts entered wall-clock time; literal Chicago default; six-zone list (browser differs) | `apps/ios/Reva/Features/Preparation/VisitEditorView.swift:43` | Person 2 |
| RVA-04-004 | candidate | P3 | "Create pre-visit brief" silently no-ops while provider busy | `apps/ios/Reva/Features/Preparation/VisitDetailView.swift:76` | Person 2 |
| RVA-04-005 | candidate | P3 | Visit/record editors save stale full copies; concurrent AI result discarded on Save | `apps/ios/Reva/Features/Preparation/VisitEditorView.swift:100` | Person 2 / Person 1 |
| RVA-04-006 | candidate | P3 | Camera scans saved as "Notes"; kind never editable; "Scan" filter misses them | `apps/ios/Reva/Features/Records/AddRecordView.swift:268` | Person 1 |
| RVA-04-007 | suggestion | P3 | Question number badge accent-on-petal 4.45:1 | `apps/ios/Reva/Features/Preparation/ReportView.swift:55` | Person 2 |
| RVA-04-008 | suggestion | P3 | PDF export uses legacy teal (out-of-scope path; dedup) | `apps/ios/Reva/Device/ReportPDFRenderer.swift:208` | Captain / Person 2 |
| RVA-04-009 | suggestion | P3 | Dynamic Type/VoiceOver robustness items | `apps/ios/Reva/Features/Shared/SummaryView.swift:137` | Captain / P1 / P2 |
| RVA-04-010 | suggestion | P3 | Discard confirmation only in symptom editor | `apps/ios/Reva/Features/Preparation/VisitEditorView.swift:80` | Person 1 / Person 2 |
| RVA-04-011 | suggestion | P3 | Past visits oldest-first; status-only Upcoming (browser differs) | `apps/ios/Reva/Features/Preparation/VisitsView.swift:17` | Person 2 |
| RVA-04-012 | suggestion | P3 | No visit delete; notes only after a brief | `apps/ios/Reva/State/AppStore+Visits.swift:11` | Person 2 |
| RVA-04-013 | suggestion | P3 | Profile isDemo persists after real edits | `apps/ios/Reva/Features/Profile/MedicalProfileEditor.swift:109` | Person 1 |
| RVA-04-014 | suggestion | P3 | Stale import error on photo/scan path; Cancel does not cancel extraction | `apps/ios/Reva/Features/Records/AddRecordView.swift:127` | Person 1 |

Counts: confirmed 1, candidate 5, suggestion 8, rejected 0, WIP 0, evidence-gap 0. No P0/P1. No efficiency findings are claimed (no measurement available; nothing in the reviewed views does unbounded work — list projections are O(n log n) sorts over the in-memory snapshot on each access, which is a design note, not a defect at the demo data sizes).

## 4. Evidence requests

No `evidence/commands.jsonl` existed when this track ran. Requests for the runner follow-up pass (all read-only with respect to tracked files; simulator items are expected to be Deferred under the audit's isolation rules and are listed so the gap is explicit):

| ID | Command (cwd) | Purpose | Expected | Priority | Findings |
| --- | --- | --- | --- | --- | --- |
| ER-04-01 | `env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" swift test --package-path /Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322 --filter 'RevaCoreTests.(DomainTests|SymptomEntryTests|MedicalProfileTests|FixtureEvidenceTests)'` (cwd: worktree root; `.build` is a permitted temporary artifact) | Confirm the RevaCore staleness/signature, symptom text and profile normalization tests pass on the snapshot; LiveServerTests must skip (`REVA_RUN_LIVE_CLIENT_TESTS` unset). | All filtered tests pass; 0 live tests executed. | high | E04, C06, C04 |
| ER-04-02 | Simulator (deferred): launch the app on a fresh, non-shared simulator; Medical profile > Settings; set Server URL to `http://127.0.0.1:1`; tap "Check available services" and "Check connection". | Determine whether the RootView alert appears while the Settings sheet is presented. | If no alert appears until the sheet is dismissed, RVA-04-002 is confirmed. | medium | RVA-04-002, C01 |
| ER-04-03 | `swift -e 'let a = "2026-09-15T09:00:00-05:00"; let b = "2026-09-15T13:00:00Z"; let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; print("string:", a < b, "instant:", f.date(from: a)! < f.date(from: b)!)'` (cwd: scratchpad `/private/tmp/claude-502/-Users-tempadmin-Documents-Reva/a4829c72-eed5-4457-959e-34f8c5715bdc/scratchpad`) | Bounded demonstration that lexical ordering and instant ordering disagree for the seed/editor formats. | Prints `string: true instant: false`. | high | RVA-04-001, E01 |
| ER-04-04 | Simulator (deferred): open `demo-visit-orthopedics`, create the local brief, Share visit brief, save the PDF to the evidence dir and inspect pagination and quotation clipping. | E05 export content check. | Every section, "Source:" label and sources list present; no clipped quotations. | low | E05, RVA-04-008 |
| ER-04-05 | `python3 - <<'EOF'` script computing WCAG relative luminance for (#8C2F3B on #FAE6E5), (#FFFFFF on #B84250), (#B84250 on #FBF7F5), (#B84250 on #FAE6E5) (cwd: scratchpad) | Independent recomputation of the contrast ratios cited under K01. | 6.78, 5.34, 5.01, 4.45 (±0.02). | low | RVA-04-007, K01 |

## 5. What was NOT reviewed and why

- Runtime UI behavior on device/simulator (sheet-over-alert presentation, Dynamic Type rendering, VoiceOver order, PDF rendering): the audit forbids simulator use by reviewers; the runner is also barred from the shared simulator, so these remain Unverified rather than evidence-gap-with-a-plan.
- `Features/Visits/**` (booking, recording, transcription UI) and `State/AppStore+{Sync,Providers,LiveCalls,Transcription}.swift`: outside Track 04's assignment; only their `errorMessage` write sites were grepped to characterize RVA-04-002.
- `Device/**` beyond the two sampled files, `Core/**` beyond contract reading, server and browser code beyond the parity lines listed in 1.2.
- Account/session/Tiger work: not present in this snapshot and not part of the native feature scope; no WIP findings raised by this track.
- No `.env`, credential, keychain or patient storage was opened.

## 6. Refuted or dropped candidates (for validator context)

- Attachment filename overflow on import: refuted — importer truncates to `prefix(180)` so UUID + "-" + name ≤ 217 chars, under `AppSnapshot.safeFilename`'s 240 limit.
- Double-tap duplicate Save in editors: Save buttons are inside sheets that dismiss on success; a second tap before dismissal would re-save the same id (upsert), so no duplicate rows — dropped.
- AI summary guard using the full record pool for the unknown-id check: negligible cost, correct behavior — dropped.
- Profile edits stale-ing briefs: refuted — profile is not a signature input and not a generation input (C05 Pass).
- Filename/MIME/SHA-256 loss on failed save: refuted — nothing is written before Save; attachment write precedes the atomic snapshot write (D04 Pass).

## 7. Statement on actionable defects

One source-proven defect survived (RVA-04-001, P2, visit ordering by raw ISO string). Five further items are candidates that depend on runtime confirmation or on a narrow trigger window (RVA-04-002 through -006). Everything else in this track is a suggestion (style, parity or roadmap). No P0/P1 defect was found in the assigned native feature UI and AppStore flow files.
