# Reva targeted revision 03 — finding 4 and PDF page-jump timing

Worktree `/Users/tempadmin/Documents/Reva/.worktrees/implementation-review` on checkpoint `eb2ec3a`. Uncommitted, unbuilt; the primary applies this diff to main, compiles, and exercises it. Files touched: `apps/ios/Reva/UI/RecordsView.swift` and the `save(_ record: MedicalRecord)` method in `apps/ios/Reva/State/AppStore.swift`. Nothing else changed (`git diff --stat`: 2 files, +55/−14).

## Changes

### 1. `RecordEditorView` compares against the original before touching provenance (`RecordsView.swift`)

- Custom `init(record:)` keeps `original: MedicalRecord` alongside the editable `@State record`; the call site `RecordEditorView(record: record)` is unchanged.
- `save()` replaces the inline toolbar closure:
  - `isDemo` is always carried over from `original`. Fictional origin describes the source, not whether it was edited.
  - Only when `record.text != original.text`: summary becomes `ReportEngine.localExcerpt(text)`, `pageTexts` is nil'd (whole-document correction, per contract), status becomes `ready` if the reviewed toggle is on and text is non-empty, else `needsReview`.
  - When text is unchanged: summary, `pageTexts`, and status are preserved. If the reviewed toggle is on, text is non-empty and the original status is `needsReview`, status becomes `ready`. A `ready` record is no longer silently demoted to `needsReview` by a title or notes edit, which the old code did.
- Footer copy now states the rule: changing text refreshes the excerpt, drops page segmentation, and stales briefs; title, date, and notes edits keep the summary.

### 2. `RecordDetailView` labels the summary by what it is (`RecordsView.swift`)

Because `isDemo` now survives a text correction, a fictional record whose authored summary was replaced would otherwise still read "Demo summary / Prepared from fictional source material". A private `hasAuthoredSummary(_:)` returns `isDemo && summary != localExcerpt(text)`; the label and caption use it. `summaryLabel` in `Models.swift` is unchanged and has no other callers. The `SYNTHETIC RECORD` badge still follows `isDemo`.

### 3. `AppStore.save(_ record:)` bumps `version` only for brief-affecting changes

For an existing record, `version` increments only if title, date, text, tags, summary, or status differ from the stored copy; otherwise the stored version is kept. Notes and provider edits therefore do not stale briefs. New records append unchanged. Callers pass copies of the stored record, so the stored version is authoritative.

### 4. `NativePDFView` navigates after layout and only on change (`RecordsView.swift`)

- `makeUIView` creates a `RevaPDFView` (a `PDFView` subclass) without loading the document; `updateUIView` calls `show(url:page:)`.
- `show` reloads the document only when the URL changes and records a pending page index only when the page changes (clamped to the page count), then calls `setNeedsLayout()`.
- `layoutSubviews` applies `go(to:)` once bounds are non-zero, clears the pending index when `currentPage` matches, and otherwise schedules one more layout pass, at most three attempts. Repeated SwiftUI updates with the same URL and page do nothing.

## Behavior matrix for the editor

| Edit | summary | pageTexts | isDemo | status | version |
| --- | --- | --- | --- | --- | --- |
| Notes only | kept | kept | kept | kept | kept |
| Provider only | kept | kept | kept | kept | kept |
| Title or date only | kept | kept | kept | kept | +1 |
| Reviewed toggle, text unchanged, was needsReview | kept | kept | kept | ready | +1 |
| Text changed, toggle off | excerpt | nil | kept | needsReview | +1 |
| Text changed, toggle on | excerpt | nil | kept | ready | +1 |

## Checks for the primary

1. Compile; the only new symbols are `RevaPDFView`, `RecordEditorView.save()`, `textChanged`, `textPresent`, `hasAuthoredSummary`.
2. Symptom diary: add a note, save. Expect badge `SYNTHETIC RECORD`, label `Demo summary`, status still needs review, no "brief needs an update" on the September 15 visit.
3. Same record: toggle "I checked the text", save without editing text. Expect status ready, summary and label unchanged, the visit brief now stale (status is in the signature).
4. Tibia procedure (2 pages): edit the title only, regenerate the orthopedic brief. Expect the citation page to remain whatever the engine selects from `pageTexts`, not forced to page 1.
5. Tibia procedure: change one character of text, save. Expect label `Local excerpt`, caption "An automatic excerpt…", badge still synthetic, `pageTexts` gone, brief stale.
6. Imported preparation note: notes-only edit, then regenerate. Expect no version change and no stale banner before regeneration.
7. From the orthopedic brief, open a page-2 source link. Expect the viewer to land on page 2 on first presentation and to stay there across SwiftUI re-renders. If it still lands on page 1 on some device, raise `remainingAttempts` or add a main-queue hop before the first `setNeedsLayout()` in `show`.
8. Run `RevaCoreTests`; the staleness test edits text, so it should still pass with the conditional version bump.

## Not changed

Imports, server sync, questions, `ReportEngine`, tests, model definitions, `summaryLabel`, and the `SourcePreview`/`QuickLookView` wrappers. The residual from review finding 4 that is not addressed here: `deleteRecord` still leaves attachment files behind (finding 7).
