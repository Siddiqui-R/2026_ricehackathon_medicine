# Reva synthetic demonstration dataset

**All files are fictional. No real patient data, clinic records, signatures, or recorded conversations are included.** The medical details are invented source material for demonstrating software behavior, not clinical guidance.

The fixed demonstration date is September 12, 2026. Jordan Avery (Synthetic) has nine dated records, two upcoming visits with different preparation goals, and one completed visit associated with an optional text-only transcript. The old right tibial implant and new right distal fibula fracture are separate events. The unrelated resolved ear infection demonstrates selective history retrieval.

## Files

- `seed.json`: exact app state fixture; bookings and recordings start empty.
- `sample-transcript.json`: one `VisitRecording` with `isSample: true`, ordered relative-second timestamps, and no audio file. It belongs to `demo-visit-primary-20260908` and is loaded only by an explicit sample action.
- `expected-evidence.json`: baseline inclusion/exclusion expectations for the two upcoming visits, a pinning case, and the scan's uncertain date. It describes expected source selection; app tests still need to execute the relevance engine.
- `fixture-manifest.json`: SHA-256 hashes, filenames, record associations, and MIME types for all eleven source files. Match complete file bytes before identifying an import as a known synthetic fixture.
- `sources/`: standalone importable artifacts listed below.
- `qa/verification.json`: generator's actual validation results. `qa/reproducibility.json` records the verified byte-identical regeneration of all fifteen source/fixture outputs. Visual review evidence is recorded in `docs/task-specs/demo-dataset.md`.
- `demo-script.md`: presentation route and hardware fallbacks.

| Source filename | Format | Seeded use |
| --- | --- | --- |
| `reva-synthetic-health-history.pdf` | 1-page text PDF | Medication/allergy/condition context |
| `reva-synthetic-tibia-procedure-2019.pdf` | 2-page text PDF | Prior procedure; implant inventory on page 2 |
| `reva-synthetic-fibula-injury-2026.pdf` | 1-page text PDF | New lower-leg injury |
| `reva-synthetic-leg-imaging.pdf` | 1-page text PDF | Written imaging report, no radiograph |
| `reva-synthetic-laboratory-results.pdf` | 1-page text PDF | Synthetic values with preserved units |
| `reva-synthetic-resting-ecg-note.pdf` | 1-page text PDF | Written ECG note, no tracing |
| `reva-synthetic-resolved-ear-infection.pdf` | 1-page text PDF | Unrelated resolved episode |
| `reva-synthetic-asthma-context.txt` | UTF-8 text | Asthma and existing medication context |
| `reva-synthetic-symptom-diary-scan.png` | Raster image | Deliberate `needsReview` scan |
| `reva-synthetic-symptom-diary-image-only.pdf` | 1-page raster-only PDF | Alternate import of the same diary; not a second seeded record |
| `reva-synthetic-import-preparation-note.txt` | UTF-8 text | Unseeded source for a distinct manual import |

Every source appears with the same bytes and flat filename in `apps/ios/Reva/Resources/`. The four fixture JSON files are copied there as well. The generator writes only its owned source/fixture paths; use the app project's generator after resources change.

## Reproduce and verify

With Python 3 and `reportlab`, `pypdf`, and `Pillow` installed:

```sh
python3 demo/generate_fixtures.py
python3 demo/generate_fixtures.py --verify-only
python3 demo/render_fixtures.py --output /private/tmp/reva-demo-qa
```

On the supplied Codex desktop environment, the verified Python executable is `/Users/tempadmin/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. The renderer finds system Poppler or the bundled `pdftoppm`. It uses a temporary local fontconfig cache on macOS. Output PDFs use deterministic metadata; the scan is deterministically rendered with installed Arial (or DejaVu Sans on Linux). The exact raster hashes may differ when regenerating with a different font installation. Rerunning with the same runtime/fonts reproduces the source and JSON bytes.

The generator checks exact top-level app keys, domain enum/date types, unique IDs, valid references, truthful page text, source hashes, byte-identical app copies, and transcript timestamp bounds. Fonts are embedded in the text-layer PDFs for consistent rendering. The final PDF's extracted text is the seed's source text, including page headers and footers. Never hand-edit source PDFs and seed text independently; edit the authored model in the generator and regenerate.

## Honest uncertainty and provenance

The diary's printed week-ending date, September 7, 2026, is legible. An individual entry-date digit is visibly smudged. The seeded record date means the week ending; canonical text preserves the entry as `September 0[unclear], 2026`. The source is intentionally unresolved and marked `needsReview`. Correct only information the presenter can independently confirm; a fictional demonstration correction can be identified as a presenter-supplied value in notes.

The seed's diary text is an authored reference transcription. It does not prove OCR ran. Importing the PNG or image-only PDF requires the app's actual native OCR path and can produce imperfect text. A hash match identifies a known fixture but should not replace extraction error handling or erase uncertainty. Similarly, the optional sample transcript has no audio, and must not appear as a transcript of a newly recorded microphone clip.

This package verifies artifacts and relationships. Native app navigation, report selections, OCR, persistence, actual microphone capture, and export are separate integration checks. No remote AI, speech service, phone call, or database connection is performed by these scripts.
