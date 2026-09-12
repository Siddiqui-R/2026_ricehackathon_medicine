# Synthetic Reva demo dataset specification

**Status:** authored and artifact-verified; app integration checks remain with the primary agent. All contents fictional. Owner: demo-dataset contributor. Date: 2026-09-12.

## Authority and boundaries

This packet implements T28-T30 and completion gate 13 under `docs/implementation-contract.md`, `docs/completion-criteria.md`, and `docs/task-list.md`. No applicable AGENTS.md was found in the project or its ancestor directories. The contributor owns only `demo/`, `apps/ios/Reva/Resources/`, and this packet. No shared application code, shared progress files, commits, pushes, live services, real medical records, or final architecture diagram are in scope. The PDF skill governs PDF generation and visual QA.

All identities, organizations, clinical events, values, signatures, identifiers, documents, and dialogue are invented for software demonstration. These sources document a fictional story; they are not medical guidance. Dates stay fixed around the demonstration date, September 12, 2026, so reset is reproducible. No address, contact number, real institution branding, signature image, device serial number, or real patient identifier is included.

## Output and source-of-truth design

- `demo/generate_fixtures.py` holds the fictional source model, writes the importable sources, extracts final PDF text into seed records, validates cross-file relationships, and copies flat resources into the app. ReportLab creates PDFs; pypdf checks extraction; Pillow creates a synthetic raster scan. Generated JSON and source bytes are reproducible.
- `demo/seed.json` and its byte-identical app resource use exactly the top-level keys `schemaVersion`, `profile`, `records`, `visits`, `bookings`, and `recordings`. Bookings and recordings start empty. Every record has `isDemo: true`, version 1, contract enum spellings, date strings, unique flat source filenames, and extracted/source text. `pageTexts` is the optional contract extension approved by the primary agent; each PDF page is extracted separately for truthful page references.
- `demo/sample-transcript.json` is a single standalone `VisitRecording`, offered through a separate explicit sample action. It must never be automatically applied to newly captured microphone audio.
- `demo/sources/` contains seven PDFs (one has two pages), an asthma plain-text document, and a raster symptom-diary PNG. An additional raster-only PDF of the same diary demonstrates OCR-only PDF import. A short unseeded preparation text note supports a nonduplicate import demo.
- `demo/fixture-manifest.json` declares synthetic provenance, fixture date, record-to-filename associations, SHA-256 hashes of the exact bundled source bytes, MIME types, page counts, and seeded/unseeded status. Hash matches identify known synthetic imports; filenames alone do not prove synthetic provenance.
- `demo/expected-evidence.json` defines explicit visit inclusion/exclusion cases and the uncertain scan review case. These are acceptance expectations, not generated diagnostic recommendations.
- `demo/README.md` explains use, reproducibility, provenance, file inventory, and limitations. `demo/demo-script.md` gives a brief complete walkthrough and fallback route.
- `demo/qa/verification.json` records machine checks. Rendered QA pages/contact sheets are intermediates, not bundled app resources.

## Fictional profile and chronology

Profile ID: `demo-profile-jordan-avery`; display name: Jordan Avery (Synthetic); DOB: 1991-04-16; initials JA. The profile lists a penicillin-associated rash, intermittent asthma, and previously documented albuterol and cetirizine use. Medication fields describe the fictional source documentation; they do not prescribe or infer a cause for symptoms.

| Record ID | Source date | Kind / source | Narrative purpose |
| --- | --- | --- | --- |
| `demo-record-tibia-procedure` | 2019-04-18 | Procedure / two-page PDF | Prior right tibial fracture fixation; retained intramedullary nail and locking screws, implant details on page 2. |
| `demo-record-ear-infection` | 2025-11-04 | Notes / PDF | Resolved minor right-ear infection; deliberately low relevance to both planned visits. |
| `demo-record-asthma` | 2026-05-12 | Notes / text | Documented intermittent asthma and existing inhaler context; no new instructions. |
| `demo-record-fibula-injury` | 2026-08-22 | Notes / PDF | New right distal fibula fracture after a fall; prior tibial hardware documented. |
| `demo-record-leg-imaging` | 2026-08-29 | Imaging / PDF | Follow-up right tibia/fibula imaging describing distal fibula fracture and intact old hardware. |
| `demo-record-history` | 2026-09-01 | Notes / PDF | Reconciled medications, allergy, and active conditions relevant as general visit context. |
| `demo-record-symptom-diary` | 2026-09-07 | Scan / PNG | Week-ending date legible; individual entry date visibly obscured. Nausea/palpitations patient observations. `needsReview` is deliberate. |
| `demo-record-labs` | 2026-09-07 | Labs / PDF | Fictional CBC, metabolic, and thyroid values; no diagnostic interpretation. |
| `demo-record-ecg` | 2026-09-07 | Notes / PDF | Fictional resting ECG note with rhythm/rate and symptom limitation. |

The right tibia procedure and new distal fibula injury are different events in the same lower leg. The implant was not inserted during the new fibula injury. The symptom diary does not assert that any medicine, fracture, or implant caused palpitations or nausea. No missing record is treated as proof that an event did not occur.

## Visits and expected relevance

Upcoming primary care: `demo-visit-primary-20260915`, September 15, 2026, 09:00 America/Chicago. Concern: intermittent nausea and racing-heart sensations. Goal: organize symptom timing, current medication context, and existing tests for discussion. Questions concern what details to bring, what prior results can establish, and what remains unresolved. Expected evidence includes the diary, labs, ECG, medication/allergy history, and asthma documentation; unrelated ear-infection and leg imaging should not enter by default.

Upcoming orthopedics: `demo-visit-orthopedics-20260917`, September 17, 2026, 10:30 America/Chicago. Concern: follow-up of August right distal fibula fracture, walking comfort, and old tibial hardware. Goal: review interval imaging, distinguish new injury from prior implant history, and prepare recovery questions. Expected evidence includes the injury, follow-up imaging, older procedure (including page 2 implant facts), and medication/allergy history. The ear infection, unrelated ECG/labs, and nausea diary should not enter by default. No record is initially pinned, so baseline relevance must find the old procedure from source content. A separate test pins the ear-infection record to prove explicit user inclusion overrides default exclusion.

Completed primary care: `demo-visit-primary-20260908`, September 8, 2026, 14:00 America/Chicago. This visit is the source of the optional transcript sample. It discussed the documented symptoms and preparing a clearer timeline for follow-up; it did not establish a diagnosis or create new medication instructions. A subsequent upcoming visit is coherent with unresolved questions.

## Exact standalone VisitRecording schema

`sample-transcript.json` has exactly these fields: `id` (String), `visitID` (String matching the completed visit), `title` (String prominently synthetic), `createdAt` (ISO 8601 String), `duration` (Number, seconds), `segments` (Array of objects with `id`, `speaker`, `start`, `end`, `text`), `summary` (String), `isSample` (true), and `status` (`ready`). `audioFilename` is omitted because no recorded audio exists. Segment IDs are stable, unique strings; `start` and `end` are nonnegative recording-relative seconds, ordered with `start < end <= duration`. Speaker names identify fictional patient/clinician roles. The summary cites stable segment IDs for provenance. The visible title and dialogue make sample origin explicit.

## Scan uncertainty and review behavior

The raster diary has a conspicuously synthetic header, printed week-ending date, and a deliberately smudged individual date digit. The canonical seeded text uses `[unclear]` for the obscured digit. The record's `date` is the clearly printed week-ending date, not a guessed individual date. Its `notes` state the uncertainty and its `status` is `needsReview`. The seed is an authored reference transcription, not a claim that OCR executed. Importing its PNG or image-only PDF must still run the actual device extraction path. Correcting the date is a human review action; no value should be invented merely to clear the state.

## Verification and acceptance

1. Validate exact seed top-level keys, required record/visit/recording fields, enum values, date parsing, unique IDs, relationship integrity, source presence, flat uniqueness, and all synthetic flags.
2. Verify every PDF has expected pages and extractable text; normalized `text` equals concatenated `pageTexts`, each of which comes from the final PDF. The raster-only PDF must have no extractable text before OCR.
3. Validate exact source SHA-256 hashes and byte-identical copies under app Resources. Check generated output determinism by regenerating and comparing hashes.
4. Render every PDF page with bundled Poppler, inspect a contact sheet, and inspect full-size pages for typography, spacing, truncation, page labels, and source labels. Inspect the raster diary to ensure the ambiguity is real and the remaining text legible.
5. Check fixture content and expected evidence relationships. Application relevance execution, native OCR results, and transcript navigation are integration checks owned by the primary agent.
6. Record actual commands/results below and notify the primary agent of final filenames and IDs. Never claim app or device validation from fixture-only tests.

## Verification evidence

- Ran `/Users/tempadmin/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 demo/generate_fixtures.py` successfully. Output: 9 synthetic records, 3 visits, 11 importable sources, and all fixture checks passed. Seven text-layer PDFs occupy eight pages; the alternate image-only diary PDF adds one page, for 8 PDFs / 9 PDF pages total. Two text files and one PNG complete the standalone source set.
- Ran the same generator in `--verify-only` mode successfully after final generation. `demo/qa/verification.json` records exact-key/date/enum/relationship validation, matching page text, manifest hashes, byte-identical app resources, ordered transcript offsets, and the intentional review state. No sample recording appears in the initial state's recordings array.
- Rendered all 9 PDF pages with `demo/render_fixtures.py --output /private/tmp/reva-demo-qa` and bundled Poppler. Inspected the complete nine-page contact sheet and full-size laboratory page, both procedure pages, and original scan. Final pages have clear synthetic headers, readable typography/units, consistent margins and footers, valid page numbering, and no clipped or overlapping text. The obscured scan digit is visibly unreadable while surrounding text and the week-ending date are legible.
- Initial rendering exposed an environment fontconfig path/cache issue, resolved by the renderer's temporary task-local font configuration. Visual review also caught substituted-font glyph spacing; embedding the regular and bold document fonts fixed it. Final rendered checks were rerun after these fixes.
- Regenerated every source and fixture JSON file and compared SHA-256 hashes before and after. All 15 files were byte-identical. Results and exact hashes are in `demo/qa/reproducibility.json`. Regeneration depends on the same runtime/font installation; another supported font installation can intentionally change generated raster/PDF bytes and manifest hashes together.
- Removed future-event narration from the historical 2019 procedure source so its contents are temporally coherent with its source date. The newer injury and imaging documents establish the current relationship to old hardware. Removed unrelated clinical keywords from the ear source to keep the negative relevance case meaningful.
- Stable profile ID, visit IDs, flat source filenames, optional `pageTexts`, standalone transcript schema, and manifest/expected-evidence paths were reported to the primary agent. Only the assigned dataset, app resource, and task-spec paths were changed. No commit or push was performed.

Fixture checks do not prove the Swift relevance engine, device OCR, audio capture, app persistence, report export, or live provider behavior. The primary agent should regenerate the Xcode project to include resources, execute the expected-evidence scenarios against the actual domain engine, and verify import/sample-source navigation in the running app.
