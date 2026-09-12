# Reva implementation review 02 — checkpoint eb2ec3a

Static read-only review of the worktree at `eb2ec3a` against `docs/completion-criteria.md` and `docs/implementation-contract.md`. No build, run, or test execution; the relevance engine was traced by a line-for-line Python port of `ReportEngine.selectedRecords`/`generate` over `demo/seed.json`. Physical camera, live credentials and production hardening are out of scope.

Verdict: the journey is wired end to end and persistence, booking idempotency, sample/real-audio separation and the server boundary hold up. Two faults in the brief itself will visibly hurt the demo, and three medium issues cause lost edits, false "out of date" states, or lost provenance.

## Findings, ranked

### 1. High — Brief evidence is header boilerplate, and the tibia citation lands on page 1

`ReportEngine.localExcerpt` (`apps/ios/Reva/Core/ReportEngine.swift:5-8`) takes the first eight non-empty lines of the chosen page. Every fixture PDF opens with seven header lines (synthetic banner, library label, title, name/DOB, source, date, section heading), so each brief section shows the banner block plus at most one clinical line. The traced excerpts for all eleven selections (both visits) contain no lab value, no rhythm, no implant detail. `expected-evidence.json` `sourceChecks` (`1.62 mIU/L`, `Implant location: RIGHT TIBIA`) never appear in a section body.

Page choice (`ReportEngine.swift:45-49`) counts substring hits of concern/goal words per page. For `demo-record-tibia-procedure` the trace gives 13 hits on page 1 versus 11 on page 2, so the source link is `p. 1` and demo step 2 ("show the implant inventory on page 2") cannot be reached from the brief. `DomainTests.swift:25-26` only asserts the page is within `pageCount`.

Fix: build the excerpt from lines around the best focus-term hits (skip lines matching the banner/DOB/Source/Source date patterns, or lines before the first all-caps section heading), keep the 1400-char cap; score pages on hits in content lines only, and prefer later pages on ties. Add a Swift test that runs both `expected-evidence.json` scenarios and asserts each `sourceChecks.contains` string is inside the cited page's excerpt. After the fix, verify on the simulator that `NativePDFView` (`RecordsView.swift:212`) actually opens page 2; `PDFView.go(to:)` issued inside `makeUIView` before layout is frequently ignored, so move it to `updateUIView` or a main-queue hop if it is.

### 2. High — Two question lists diverge; regeneration discards visit-level edits

`generate` (`ReportEngine.swift:57`) prefers `visit.report?.questions` and `visit.report?.notes` over `visit.questions`/`visit.notes`. `VisitEditorView.save` (`UI/VisitsView.swift:133`) writes edited questions to `visit.questions` only, while its footer (`:125`) says the brief's questions are editable too, and `ReportEditorView` (`:196`) writes to `report.questions` only. Once a brief exists, a question edited through the visit "Edit" button never appears in the brief or the PDF, even after "Regenerate from current records"; an edit made in the brief never appears in the visit form. Demo steps 2 and 7 ("edit a question… confirm the edited question persists") hit this directly.

Fix: make `visit.questions`/`visit.notes` the single source. `ReportEditorView` should write to `latest.questions`/`latest.notes` (and mirror into the report), and `generate` should use `visit.questions.isEmpty ? suggested : visit.questions` without the report fallback. Consider adding questions to the signature only if you want edits to show as stale.

### 3. Medium — Date re-serialization falsely marks briefs stale and disables sharing

The seed stores visit dates with offsets (`2026-09-15T09:00:00-05:00`). `VisitEditorView.save` (`VisitsView.swift:133`) and `BookingEngine.confirm` (`ReportEngine.swift:71`, via `BookingViews.swift:31`) rewrite `visit.date` with `RevaDate.iso` (`Models.swift:156`), which emits `…T14:00:00Z`. The raw string is part of the signature (`ReportEngine.swift:11`), so editing any visit field or confirming a booking at the prefilled time makes the brief "need an update" and disables "Share visit brief" (`VisitsView.swift:170`) although nothing the brief uses changed. In the scripted route (edit question → booking → share) the presenter sees "Records or visit details changed" twice and must regenerate before step 7.

Fix: drop `visit.date` from the signature (selection does not depend on it), or hash `RevaDate.parse(visit.date).timeIntervalSince1970`. Also stop rewriting `visit.date` when the parsed instant is unchanged.

### 4. Medium — Any record edit erases provenance and page segmentation

`RecordEditorView` save (`UI/RecordsView.swift:99-101`) unconditionally replaces `summary` with a local excerpt, sets `isDemo = false`, and nils `pageTexts`, even when only title, date or notes changed. A synthetic record then shows `SAVED ON DEVICE`/`Local excerpt` (`RecordsView.swift:59`, `Models.swift:44`), and a two-page fixture can only ever be cited as page 1 afterwards. Adding the presenter's labeled date note to the symptom diary (demo step 3) triggers this. `AppStore.save(record)` (`State/AppStore.swift:53`) also bumps `version` for notes-only edits, staling every brief.

Fix: compare `revised.text` with the original; only when text changed reset summary, `pageTexts` and status. Keep `isDemo` as a fictional-origin flag and record "edited on device" separately if the badge should change. Bump `version` only when text, tags or status change.

### 5. Medium — Fixture scenarios are not executed by tests

The Python trace passes every `mustInclude`/`mustExclude` for both scenarios and the pinning case, but this is a port, not the Swift engine. `Tests/RevaCoreTests/DomainTests.swift` checks two inclusions and one exclusion; `mustExclude` sets, `mayInclude`, the pinning case and both `sourceChecks` are unasserted. Given how sensitive the keyword groups (`ReportEngine.swift:20-25`) are to summary wording, one regenerated fixture summary could silently pull labs into the orthopedic brief.

Fix: load `expected-evidence.json` in `DomainTests` and assert scenarios, pinning case, and `sourceChecks` against `generate`; fold in the page/excerpt assertion from finding 1.

### 6. Low — Developer transport dead ends and a soft-misleading dialog

- After "Restore fictional demo" (`AppStore.swift:49`) or a token/URL change (`:102`), `serverRevision` is 0; a push against existing server state returns 409 forever and the only recovery is a pull that replaces local data. Fix: on `.conflict`, read the server revision (`GET /v1/state` or `X-State-Revision`) and offer "Overwrite server with local".
- Push sends `record.mimeType` (`AppStore.swift:113`); image imports carry whatever ImageIO reports (`Device/DocumentImportService.swift:162`), so a TIFF/GIF/WebP photo makes the whole push fail against `Validation.contentTypes` (`server/Sources/RevaServer/Models.swift:89`). Fix: map unknown image types to `application/octet-stream` before upload, or widen the allowlist.
- The pull dialog (`UI/SettingsView.swift:43`) promises a kept backup; `LocalRepository.save` keeps exactly one previous state that only automatic recovery reads. Either add a "Restore previous local state" action or soften the text.

### 7. Low — Deleted items leave files behind and one notice overwrites another

`deleteRecord` (`AppStore.swift:57-58`) and the recording delete (`UI/RecordingViews.swift:87`) remove snapshot entries but never the attachment or `.m4a`; the Settings reset footer admits this. Fix: remove the file when no other record or recording references the name. At startup the interrupted-booking notice (`AppStore.swift:24`) replaces the recovery notice (`:21`); show both or prioritize recovery.

## Checked, no material issue

- Core models and validation (`Models.swift:129-141`): unique IDs, visit references, safe filenames; visits cannot be deleted, so the booking/recording reference rule cannot strand data.
- `LocalRepository`: backup-then-atomic write, 16 MB attachment cap; imports get a UUID-prefixed filename (`RecordsView.swift:187`), so no overwrite collisions.
- Booking: single start guard (`BookingViews.swift:23,31`), status-gated transitions, idempotent `confirm` via `confirmedVisitID` mutating the existing visit only, queued/calling → needsUser on relaunch with retry.
- Recording: consent gate, `interactiveDismissDisabled` while recording, discard dialog, pause on background/interruption/route loss, empty-audio rejection, `cancel` deletes only unfinished drafts, real audio never receives segments; `loadSample` pins the sample to its fixture visit with `audioFilename = nil`; `saveMemory` labels fictional versus user-entered origin.
- Import: security scope, coordinated reads, embedded-text-then-OCR per page with explicit warnings, size/page/pixel bounds, honest simulator gating of the camera with a real sample-import path.
- Source viewer honesty: "Open original · page N" uses PDFKit for PDFs and QuickLook otherwise; page numbers only ever come from `pageTexts`.
- PDF export: bounded, paginated, headings kept with bodies, per-section `Source: title · p. N`, source list with versions, honest footer.
- Server: constant-time bearer compare, demo token only on loopback, owner scoping from auth, CAS revisions with 409/404 + `X-State-Revision`, tombstones, atomic file store with `flock`, Postgres advisory-lock migration and `FOR UPDATE` transactions, quotas, content-type allowlist; eight local tests cover these paths, Postgres integration test correctly gated.
- Fixtures: `demo/` and `apps/ios/Reva/Resources` copies byte-identical; seed has no bookings/recordings; transcript timestamps ordered.
- Theme tokens match the six supplied colors with dark variants; portrait-only, purpose strings present, no background audio mode.

## Caveats

Findings 1–5 are confirmed from source and fixture data; runtime behaviors (PDFKit page jump, simulator OCR quality, share sheet) were not exercised. `docs/build-progress.md` still lists an empty Checkpoints section and no `swift test` evidence for `RevaCoreTests`; record that before closing gates 7, 8, 14 and 17.
