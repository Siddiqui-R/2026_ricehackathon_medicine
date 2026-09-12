# Track 07 — Browser records, OCR and profile

Author: Codex continuation (`/root/audit_browser_finish`), 2026-09-12. The user explicitly requested that Codex pick up the audit after Claude exhausted its limits; this supersedes the Fable-only worker preference. This is independent source review, not a claim of a resumed Fable worker.

Snapshot: **fable-audit-20260912-114322 @ cfe0997+wip**, `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`. No live checkout application code or newer account/Tiger implementation was mixed into this review. Read the supervisor brief including Addendum 1 and its frozen current-spec authority. Source was read only; only this track report and findings JSON were written. No builds, live providers, UI sessions, ports, credentials or Git operations were used.

## Result

One unambiguous source defect: mixed PDF pages with a sufficiently long embedded header skip OCR of their scanned body without an incomplete warning (**RVA-07-001**, P2). One source-proven failure-path candidate: retrying a record save after the snapshot commit fails can leave a new unreferenced original per retry (**RVA-07-002**, P2, storage impact not measured). Both await independent validation. No arbitrary style or file-size findings were added.

The core intake flow has useful safeguards: original bytes remain separate from corrected text; extraction is bounded and cancellable; stale extraction completion cannot publish into a newer selection; saved text corrections drop page mappings instead of inventing page references; symptom observations preserve identity/creation time; and profile facts explicitly remain separate from historical Records.

## File inventory and reviewed responsibilities

All assigned production files were read:

- `apps/web/src/features/records/ImportDialog.tsx` — selection, review, page-map invalidation, separate original/record publication, optional summary.
- `extractDocument.ts` — PDF.js, English Tesseract, image decoding, bounded text/pages/time/canvas, cancellation/worker cleanup.
- `RecordsPage.tsx` — search, categories, ordering, route-triggered import/symptoms, empty states.
- `RecordDetail.tsx` — honest summary/source/provenance display, review states, edit/delete, linked transcript/source pages.
- `RecordEditor.tsx` — immutable editing baseline, expected source version, corrected excerpt/page map, original retention.
- `SymptomDialog.tsx` — optional symptom fields, local occurrence entry, original instant/zone retention, conflict/version boundary.
- `SourcePreview.tsx` — repository lookup, blob URL lifetime, PDF page clamping, image/text/download presentation.
- `recordPresentation.tsx` — icons, date-only display helper, ordering and query parsing.
- `apps/web/src/features/profile/MedicalProfilePage.tsx` — persistent medical sections, DOB/name validation, absent-field wording, immutable original-profile conflict detection.

Shared interfaces consulted only where needed: `core/{domain,symptoms,mutations,repository,store,validation,api,models}.ts`, `components/ui.tsx`, the audit runner artifacts and existing track 02/03/05/06 reports. No test files exist under the assigned records/profile feature folders in this snapshot; the shared core suite covers several underlying invariants rather than complete import/editor DOM flows.

## Checklist dispositions

Statuses below cover this browser track only. A source-level Pass does not assert a live end-to-end journey, hardware OCR correctness or physical storage durability.

| ID | Status | Evidence and practical limit |
|---|---|---|
| C04 | Pass | `MedicalProfilePage.tsx:35-40,85-110,118-190` renders all required sections, uses Not provided for missing fields, validates calendar DOB and preserves unrelated fields. `175-190` checks the immutable original before one aggregate profile mutation; optional surgeries/care notes tolerate legacy absence. Browser reload/edit round trip was not newly exercised by this reviewer. |
| C05 | Pass | Explicit copy at `MedicalProfilePage.tsx:108-110` says preparation uses Records. `store.ts:269-275` supplies records to preparation; profile editing changes only `draft.profile`. This is a disclosed product boundary, not a claim that medication/allergy profile cards drive retrieval. |
| C06 | Pass | `SymptomDialog.tsx:21-41,58-70` preserves original identity, occurrence instant/zone unless changed, rejects nonexistent edited DST wall times; `core/symptoms.ts:9-44,48-90` validates required observation and optional fields, projects self-reported source text, preserves ID/uploadedAt, and uses the observation-zone calendar day. `mutations.ts:9-24` versions meaningful changes; Records search/filter and explicit edit/delete are present. UTC-plus-zone source wording is a shared candidate already owned by RVA-02-001, not duplicated here. |
| D01 | Pass | `extractDocument.ts:11-14,141,157-158,235-267,335-367` bounds 16 MiB input, 24 PDF pages, 120,000 UTF-8 text bytes and a nominal three-minute PDF operation; decode/worker/render waits are individually bounded; image decode checks 40 MP and canvas side 2200. Empty/invalid/unsupported/corrupt extraction becomes an explicit reviewable failure retaining the original. Browser-specific inability to decode HEIC or obscure scripts is not silently called perfect OCR. Actual malformed-file corpus/cancellation timing remains unverified. |
| D02 | Unverified | Byte-preserving `saveAttachment(filename,file)` at `ImportDialog.tsx:125-126`, immutable original reference on edit, UUID prefix, and manifest-verified demo fallback (`repository.ts:204-226`) are source-verified. Normal user originals have no stored content SHA-256 identity; only bundled fallback is hash checked. Atomic failure-path and same-name pull concerns are RVA-07-002 and existing RVA-06-009. Do not claim the whole hash/round-trip requirement passes. |
| D03 | Defect | RVA-07-001 at `extractDocument.ts:289`: embedded-text count is insufficient to distinguish text-only from mixed raster/text content. Sequential page mapping, page-limit warnings, confidence warnings and English-OCR caveats otherwise exist; corrected full text deliberately has no claimed mapping (`ImportDialog.tsx:141`, `RecordEditor.tsx:54`). |
| D04 | Defect | RVA-07-002 is a candidate failure-path defect pending independent validation. Cancellation/stale selection guards at `ImportDialog.tsx:40-102`, inline failures at `152-157`, and expected-version edit rejection work by source inspection. The file remains selected after a save failure; publishing original then snapshot is not atomic and each retry changes the staging identity. |
| D05 | Defect | Local excerpt is set before publication (`ImportDialog.tsx:137`), optional AI is requested after save (`149`); detail labels AI model/local excerpt/demo correctly (`RecordDetail.tsx:145-164`). RVA-07-001 can silently omit raster-body evidence. Shared source excerpt truncation/wrapper risks are already RVA-02-002/RVA-02-005 (`domain.ts:45-61`), not additional findings. Live Gemini generation remains unverified. |
| D06 | Pass | `RecordsPage.tsx:47-70` searches title/provider/kind/text/summary/raw and formatted date/tags; symptoms are projected into text, filters use status/kind/structured entry, rows follow state changes. `recordPresentation.tsx:21-29` orders canonical record date strings; `RecordDetail.tsx:77-86,131-137,194-215` handles removed/stale/reviewable source navigation. Search of separate record notes is not explicitly advertised as a distinct field. Large-data latency was not measured. |
| K04 | Unverified | Shared native HTML dialog traps focus/restores prior focus and handles Escape (`components/ui.tsx:79-119`); fields use enclosing labels; upload/drop zone is a native button; errors/status have live roles. Saved UI matrix has no unlabeled controls for recorded screens. No actual keyboard traversal, screen-reader output, focus restoration after child form transitions, contrast audit or large-text interaction was completed by this reviewer. |
| M01 | Unverified | Concrete bounded algorithm/resource reasoning: one OCR worker, sequential pages, 16 MiB/24 pages/120 KB/2200-pixel bounds, finally termination and URL revocation. `RecordsPage.tsx:47-70` rebuilds a full text index on each query render; actual large-record main-thread latency, peak decoded image memory and cleanup under timeout are not measured. A complexity hint alone is not a performance defect. |

## Reused evidence and limitations

- `evidence/runner1-summary.json` and `reports/17-evidence-runner.md`: Fable runner recorded 77 browser tests passing after generated assets and the browser build passing. This reviewer did not rerun them or infer import coverage from their count.
- `evidence/r2-ui-matrix.jsonl`: 76 saved rows total (72 ordinary matrix + 4 tall captures); all recorded rows report no horizontal overflow and no unlabeled controls. Relevant source/screens include Records, import-opening dialog, symptom-opening dialog, Medical profile and record detail at 375/390/768/1024/1440/1920. These are **static starting-screen observations**, not evidence of upload/OCR/edit/save/reload journeys or screen-reader correctness. Matching DOM/PNG artifacts exist under `evidence/ui/`.
- The runner's Stage 2 report is still a placeholder in the saved runner Markdown. Preserve this provenance rather than inventing a finished UI journey report.
- No new-account/per-user repository behavior was audited; it is absent from this frozen snapshot. No perfect OCR, real-device camera, live providers, Safari/Firefox compatibility or synthetic quota reproduction is claimed.

## Evidence requests and regression acceptance

ER-07-1 (sent to coordinator): construct a one-page synthetic mixed PDF with a >35-character embedded header and a raster-only unique medical token; call production extraction under the shared runner, save result/warnings and prove whether token is absent with `incomplete=false`. Preserve synthetic source and page image for validation.

ER-07-2: inject a stale IndexedDB revision between import open and save; fail/retry three times; compare attachment-key counts and snapshot identity. A corrected implementation must retain exactly one unchanged original for one successful record and no extra staged keys from failed attempts.

Other testing gaps (not defect claims): real import-review-correct-save-reload, manual page-map removal, camera/HEIC decode, worker timeout/abort cleanup, full keyboard dialog paths, and representative large-data latency.
