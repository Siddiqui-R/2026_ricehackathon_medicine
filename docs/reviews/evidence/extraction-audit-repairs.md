# Source evidence and extraction audit repairs — September 12, 2026

All nine assigned findings have focused repairs on the combined integration tree. The historical audit under `docs/audits/fable-20260912-114322` remains unchanged. Application fixes were developed in an isolated evidence worktree and integrated without including the main checkout's unrelated account work.

| Finding | Implemented repair | Executed evidence and limits |
| --- | --- | --- |
| RVA-02-002 — unsafe excerpt cuts | Native and browser excerpts retain complete, contiguous source lines within the 24-line and 1,800-character limits. Original internal whitespace is preserved. A line that cannot fit is omitted entirely, with an explicit empty-excerpt explanation when necessary. Optional `excerptOmitted` metadata carries the notice outside the exact source field. Record/import previews, native report/PDF output and browser brief/print rendering expose the omission. Older report citations without this metadata require regeneration; old generated local summaries, including edited demo records, display a fresh safe excerpt. | Synthetic regressions reproduce the previous apparent `dose: 100 mg` → `dose: 10` cut and verify that doses, units, negations, Unicode and CRLF source wording are not split. Tests verify contiguous source membership, saved metadata round trips, legacy decoding, legacy-report staleness and regenerated-report freshness. Genuine authored demo summaries remain distinct. Rendering/export paths were source-reviewed; a new UIKit PDF visual capture was not performed in this repair scope. |
| RVA-02-005 — ordinary content stripped as fixture metadata | Wrapper removal requires the explicit demo flag, exact synthetic opening/trailer, recognized date metadata and known footer lines. Ordinary `Source date:` content and quoted demonstration wording are preserved. Appended corrections after a demo footer cause the complete text to be retained. | Native/browser regressions cover ordinary date headers, explicitly flagged and unflagged fixture text, quoted demo wording and a correction appended after the trailer. Native/browser excerpt regeneration call sites retain demo provenance. |
| RVA-02-004 — generic terms and fixture trailer drive relevance | Document-generic goal words are excluded from relevance terms. Recognized fixture wrappers are excluded from the source index. Explicit pins and context tags remain authoritative. Empty `pageTexts` arrays fall back to the full source text. | Both implementations exclude the unrelated ear note for the completed palpitations/nausea seed visit and retain it when explicitly pinned. Empty-page mapping regressions verify that meaningful full record text remains searchable. Existing fixture acceptance checks and all three browser/native signature goldens pass unchanged. This is a narrow relevance repair, not a clinical selection benchmark. |
| RVA-02-006 — date-only and instant display conflated | Date-only values remain calendar days in UTC and do not invent a time. Timestamp values use the supplied or current display zone even when the clock time is hidden. Public call signatures remain compatible. | Native/browser tests cover UTC instants that fall on the previous Chicago date and next Tokyo date, and a date-only value displayed with a Honolulu zone and time requested. |
| RVA-05-004 — native mixed-PDF body skipped | The native service inspects actual PDF painting operations before accepting embedded text. Images, inline images, conservatively handled Form objects and unreadable content trigger bounded OCR. Embedded wording is retained alongside additional recognized text. Page mapping, the existing ten-page OCR cap and explicit OCR/mixed-content review warnings are preserved. | The production service was compiled and run with actual macOS PDFKit and Vision. A synthetic PDF embeds a long fax header over an image containing `Dose: 100 mg` and `No fracture seen`; both body details and the embedded header are recovered on page 1, while page 2 keeps its ordinary embedded text. An actual eleven-page synthetic PDF confirms that page 11 keeps its header and an explicit ten-page-limit warning. This does not establish physical iPhone behavior or general OCR completeness. |
| RVA-07-001 — browser mixed-PDF body skipped | PDF.js image painting operations trigger OCR independently of the embedded-text length. Reading remains bounded by the existing byte, canvas, page and time budgets plus a ten-page OCR limit. Recognition failure retains available embedded text and a review warning; unsuccessful rendering is cancelled. | Browser tests use actual PDF.js parsing and canvas rendering of the checked-in native-generated mixed PDF. A controlled OCR response verifies body/header inclusion, exact page mapping, failure retention and the ten-page OCR cap. The tests do not run the browser Tesseract worker or claim its recognition quality. |
| RVA-04-006 — camera scans classified as Notes | The camera intake path explicitly retains its origin through review and saves its generated PDF as `Scan`. Choosing another source resets that origin. Image imports retain their existing Scan classification. | The camera → generated PDF → review → record construction path was source-reviewed. A physical camera/scanner session was not executed. |
| RVA-04-007 — question-number contrast | Small question-number text on the petal background uses the existing approved `RevaTheme.accentText` token. | The exact foreground/background code pairing was checked against the existing theme contract. No new interactive accessibility or screen-reader test was performed. |
| RVA-04-008 — stale teal PDF headings | Native PDF titles, section headings, Sources heading and page header use approved heart red `#B84250`. | The renderer's former teal usages were replaced and its exact RGB value checked against the approved palette. The UIKit export was not newly rendered or visually inspected during this focused repair. |

## Integrated commits

These are the commit IDs on the integration branch, as observed with `git log`:

- `45d2d97` — complete source excerpts, omission metadata, relevance/date rules, citation rendering and question-number contrast.
- `26bcbea` — coordinated native edited-record excerpt regeneration retains demo provenance.
- `5842501` — coordinated browser brief omission/legacy/empty-excerpt notice outside quoted source text, also used by print rendering.
- `00b6b95` — legacy demo local-summary recognition, empty page mapping fallback and appended fixture-content preservation.
- `90c3e5f` — native/browser mixed-PDF OCR detection, bounded extraction, shared synthetic PDF and regression harnesses.
- `e54cbdd` — camera origin, import preview notices and approved PDF palette.
- `865c372` — required named sections for focused browser regression tests.

No report-signature algorithm or signature golden was changed. Existing reports with unknown excerpt-boundary metadata are intentionally considered stale, while newly generated source references carry explicit metadata. Sections without source references do not trigger that legacy-source check.

## Verification commands and execution boundaries

The completed focused evidence-worktree runs were:

- `swift test --scratch-path /private/tmp/reva-evidence-swift-build --filter 'ExcerptIntegrityTests|FixtureEvidenceTests'` — 12 tests passed, zero failures.
- From `apps/web`: `./node_modules/.bin/vitest run src/core/__tests__/domain.test.ts src/core/__tests__/excerptIntegrity.test.ts src/features/records/extractDocument.test.ts` — 24 tests passed across three files.
- From `apps/web`: `./node_modules/.bin/tsc -b` — exit 0.
- `python3 scripts/check_code_structure.py` and `git diff --check` — passed after test section annotations were added.

The native extraction harness was additionally rerun on the combined integration tree at `1f4b50e` with `python3 scripts/check_document_import.py`. It exited **0** and produced exactly:

```text
PASS mixed PDF: raster dose/negation plus embedded header, original page mapping and review warnings
PASS OCR cap: ten raster pages recognized, page 11 retains header and explicit review warning
```

The harness compiles the unchanged production `DocumentImportService.swift` together with `Tests/DocumentImportChecks/Check.swift`, generates fictional PDFs under a temporary directory, and runs local PDFKit/Vision extraction. Its checked-in two-page fixture is `Tests/DocumentImportChecks/mixed-content.pdf`; regeneration and scope are documented in that directory's README. No real patient data, provider credentials, paid API, network OCR service, microphone or phone call is used.

The broader integration build, full application suites, hosted deployment, physical iPhone intake, browser OCR-worker behavior and visual UIKit export checks belong to the coordinator's integration/device evidence. Passing these focused checks does not certify those unexecuted workflows or perfect OCR accuracy. Imported originals and explicit review warnings remain necessary.
