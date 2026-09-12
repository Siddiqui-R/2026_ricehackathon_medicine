# Track 08 — Browser visits, booking and audio UI

Author: Codex continuation (`/root/audit_browser_finish`), 2026-09-12. User-authorized takeover after Claude limits supersedes the original Fable-only preference. This report continues the frozen audit; it does not claim a Fable agent was restarted.

Snapshot: **fable-audit-20260912-114322 @ cfe0997+wip**, `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`. Read START-HERE, task 08, checklist, finding schema and supervisor brief including its frozen-spec addendum. Source read only; no live source, builds, tests, ports, UI, providers, credentials or Git activity. Only this track Markdown/JSON were written.

## Result

One unambiguous source defect: the questions-and-notes editor uses changing props as its conflict baseline, allowing a note-only save to erase questions generated after the editor opened (**RVA-08-001**, P2, independent validation pending). The separate main visit editor already has a proper baseline/changed-field merge and its concurrency tests pass in the saved runner evidence; this finding applies specifically to `BriefNotesEditor`.

Booking clearly separates simulation from real calls, collects final reviewed consent, preserves a request ID, and never treats call completion as appointment confirmation. Recording is explicit, consent gated, bounded and cleaned up on unmount; mock lifecycle tests cover late microphone responses and page-hide pause. Live calls/audio hardware and the complete browser journey remain unverified.

## File inventory

Read all 11 assigned production files and their three test files:

- `VisitsPage.tsx`, `VisitDetail.tsx`, `VisitEditor.tsx` — list filtering, numeric instant ordering, routed workspace and editor.
- `visitDates.ts`, `visitEdits.ts` — zoned date conversion and baseline merge at the serialized store boundary.
- `VisitBrief.tsx` — source freshness, citation links, print guard and notes/questions modal.
- `BookingPanel.tsx` — persistent requests, simulation transitions, reviewed live authorization and status refresh.
- `RecordingsPanel.tsx`, `RecordingCapture.tsx`, `RecordingDetail.tsx` — audio intake/playback, separated sample, transcript corrections and memory.
- `useVisitRecorder.ts` — capability selection, recorder/microphone generation ownership, clock, page-hide and cleanup.
- `visitDates.test.ts`, `visitEdits.test.ts`, `useVisitRecorder.test.ts` — date/calendar/DST, real-store edit races and explicitly mocked microphone lifecycle.

Consulted shared contracts only as needed: `core/{domain,store,mutations,models}.ts`, `components/ui.tsx`, print CSS in `styles/layout.css`, and saved tracks 02/04/05/06/11. No assigned source file was omitted.

## Checklist dispositions

Browser-scope statuses below do not constitute end-to-end provider or hardware verification.

| ID | Status | Evidence and practical limit |
|---|---|---|
| E01 | Defect | RVA-08-001 affects notes/questions concurrency. Date conversion (`visitDates.ts:16-43`) rejects invalid calendar/nonexistent DST wall times, resolves the repeated fall hour deterministically, and editor preserves exact unchanged instants (`VisitEditor.tsx:46-55`). Main field merge (`visitEdits.ts:64-89`) preserves unrelated fields and rejects edited-field conflicts. `VisitsPage.tsx:20-35` orders instants numerically. No browser delete/complete-visit UI exists; lifecycle scope gap is already RVA-04-012, not duplicated as a new completed-feature failure. |
| E02 | Defect | Browser domain source selection and page quotation share previously flagged native/domain behavior: `domain.ts:118-141` expands visit terms, includes contextual/pinned records; `173-183` chooses the last tied page, so an unrelated trailing page can win for zero-hit pinned records (RVA-02-003). Generic-goal/fixture-trailer relevance concerns are RVA-02-004. Shared runner's domain tests protect stated demo implant/ear scenarios but do not prove general clinical relevance. |
| E03 | Unverified | `VisitBrief.tsx:148-164` displays stored quotations and actual record/page/version links; full-text corrections with no mapping link to record text. `store.ts:277-294` rejects unknown AI candidate IDs, re-adds pins and locally assembles citations. The displayed AI overview is expressly marked for review and has no local citations (`store.ts:298-302`). Exact clinical assertion grounding for live responses, truncation boundary consequences (RVA-02-002) and an end-to-end source navigation journey are not fully verified. No invented quotation is asserted merely because whitespace normalizes. |
| E04 | Defect | RVA-08-001. Separately, `VisitBrief.tsx:33-53,64-75` checks current source signature and latest fingerprint before explicit print; `store.ts:282-319` refuses stale AI preparation and preserves authoritative latest questions/notes. Full candidate-pool version/text changes affect `domain.ts:78-89`. Swift-vs-browser golden provenance is already RVA-06-002, pending shared runner verification. |
| E05 | Unverified | Explicit Print / save PDF rechecks freshness; `data-print-ready` in `VisitBrief.tsx:123-126` plus `layout.css:439-488` suppresses stale/unchecked content even for ordinary system printing and prints a warning. Headers/questions/notes/citations are included. No actual print artifact, pagination/clipping check or system-print stale scenario is present in the saved runner output reviewed here. |
| I01 | Pass | `BookingPanel.tsx:175-201,226-245` validates clinic/window/preferences, shows a final local simulation review and all three outcomes. `core/mutations.ts:126-137` updates one existing visit and is idempotent; `store.ts:147-156` repairs interrupted queued/calling simulations to needsUser on reload rather than pretending they completed. Labels repeatedly state no real booking occurred. Runtime modal/reload journey not rerun. |
| I02 | Pass | `BookingPanel.tsx:22,43,175-225,267-305` checks configuration/live enable flags, freezes request/window/preferences, displays patient name and explicit authorization, rechecks name/config before calling, and guards duplicate submission with a ref and persisted request ID. `store.ts:402-447` owns the actual durable request/provider gate. Forward-looking late-bound patient identity caveat is already RVA-11-004. Real call was never made. |
| I04 | Pass | `BookingPanel.tsx:68-87,124-140` labels done as Call ended, unknown separately, says completion does not confirm an appointment, and requires manually reviewed time via edit. Live requests do not expose simulation confirmation. `store.ts:468-483` refreshes only retained live requests with identity checks; provider outcomes are not automatically applied to visit time. Provider/network behavior is owned by track 11 and remains synthetic/source-tested only. |
| J01 | Pass | Source and explicitly mocked hook tests support: no mount-time mic request; secure-context/capability check; permission generation handling (`useVisitRecorder.ts:70-95,145-159`); pause/resume excludes paused time; 16 MiB/30-minute bounds; visibility pause; unmount stops tracks and handlers (`162-195`). Navigation away unmounts/discards unsaved capture rather than persisting it; the UI copy about leaving the page should not be read as an autosave promise. No actual microphone/hardware interruption test. |
| J02 | Unverified | `RecordingCapture.tsx:104-132` saves real original bytes plus empty segments and no invented transcript; object URLs clean up. `RecordingsPanel.tsx:31-53` binds sample to the original fictional visit, clears audio filename, never attaches sample words to microphone audio. `RecordingDetail.tsx:30-46,66-87` refuses sample playback. Playback of a synced codec unsupported by the destination browser is not exercised; the audio element lacks an explicit media-error handler, so a supported HTML audio element does not guarantee usable playback/error wording. |
| J03 | Pass | `RecordingDetail.tsx:184-207` checks original segment text before corrections; `core/mutations.ts:82-111` validates segment ID set, changes words only, updates a stable memory ID, preserves separate notes and original segment timing/speakers/audio. Notes remain separate and explicitly require Update saved memory (`RecordingDetail.tsx:256-290`). `store.ts:379-397` rejects transcript overwrite after concurrent segment changes and updates existing memory. Actual provider transcription remains unverified. |
| K04 | Unverified | Source uses real buttons/labels/dialog, named controls, inline error/status roles and shared focus/Escape handling. Static UI evidence covers Visits and visit detail at six widths with no recorded overflow or unlabeled inputs; it does not prove keyboard flows for booking/recording/transcript/print, actual announcements or screen-reader behavior. |

## Evidence reused, not rerun

`evidence/runner1-summary.json` records 77/77 browser Vitest checks after generated assets. The source test inventory specifically confirms date DST/calendar cases, six appointment merge scenarios against the real serialized store, and seven mocked-recorder cases. The hook tests explicitly disclaim DOM/hardware integration. Do not treat them as microphone permission, actual codec decode or physical playback evidence.

`evidence/r2-ui-matrix.jsonl` contains 76 static observations; relevant `demo-visits-*` and `demo-visit-detail-*` rows include six widths and a 375-wide tall capture. The inspected visit detail had no prepared report yet, so it cannot prove export/citation pagination. Stage 2 browser journeys had not been summarized when Claude stopped. No new validation claim is based on historical pre-audit screenshots.

## Focused follow-up requests

ER-08-1 (sent to coordinator): render the real BriefNotesEditor, start with empty questions, allow first preparation to publish while the editor is open, save only changed notes and observe whether generated questions vanish. A real DOM test or hook driver with preserved useState and changing props can demonstrate the issue; explicitly label a hook driver if used. Expected fix is immutable baseline plus changed-field merge, consistent with `visitEdits.ts`.

ER-08-2 (not a defect claim): actual fresh/stale browser print artifacts, booking simulation full flow/reload, transcript correction/memory update/reload, and an unsupported audio codec error case in supported Safari/Firefox/Chromium surfaces. No live providers or production medical data are needed.

Cleanliness note: the directory has clear feature responsibility contracts and useful domain/UI separation. Share the existing edit-merge helper pattern with the notes modal rather than splitting files merely to reduce length. Missing browser visit lifecycle actions and shared memory summary-reset behavior are existing findings (RVA-04-012 / RVA-05-010), not newly duplicated issues.
