# Live user acceptance test — September 12, 2026

Target: https://revamed.health. A new isolated account named **Jordan Example — Fictional** was created in the browser. No existing users or real medical records were used. Credentials remain in ignored test artifacts, not this report.

Three newly authored text documents were uploaded through the authenticated API, then downloaded into the browser with **Pull from server**: a laboratory report, a follow-up note and an unrelated historical ankle note. Fixtures are in `build/user-test/documents/` (ignored). This setup does **not** test the browser file picker, PDF extraction or OCR.

## Results

| Check                        | Result | Evidence                                                                                                                                                                                                                |
| ---------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Signup password confirmation | Pass   | Mismatch displayed “Passwords do not match”; matching values created an empty personal workspace.                                                                                                                       |
| Original upload and download | Pass   | All three text originals downloaded with exact byte equality.                                                                                                                                                           |
| Browser pull                 | Pass   | Confirmation preceded replacement; the browser reported the snapshot and all originals saved. Three sources appeared.                                                                                                   |
| Search within source content | Pass   | Searching “hemoglobin” returned only the laboratory report.                                                                                                                                                             |
| Original viewer              | Pass   | Displayed the full laboratory source and a download link.                                                                                                                                                               |
| Laboratory summary           | Pass   | Preserved September 4, 2026, hemoglobin 13.2 g/dL and sodium 139 mmol/L.                                                                                                                                                |
| Follow-up summary            | Pass   | Preserved three days, no fever, no chest pain, no medication changes, and the September 18 follow-up plan.                                                                                                              |
| Appointment creation         | Pass   | Saved the fictional appointment, clinician, clinic, concern and goal.                                                                                                                                                   |
| Connected preparation        | Pass   | Selected the lab and follow-up note; excluded the unrelated 2022 ankle note. Returned source quotations and questions.                                                                                                  |
| Citation navigation          | Pass   | Follow-up citation opened the correct original source.                                                                                                                                                                  |
| Source correction            | Pass   | Changed three days to two days; incremented source version to 3 and cleared the old AI summary.                                                                                                                         |
| Stale report protection      | Pass   | Existing brief showed an update warning and disabled printing.                                                                                                                                                          |
| Brief regeneration           | Pass   | Refreshed overview and quotation used two days. The corrected text citation no longer claimed a verified original page mapping.                                                                                         |
| Preserve original after edit | Pass   | Server source text contained the correction; original file still matched the unedited fixture byte-for-byte.                                                                                                            |
| Automatic persistence        | Pass   | API read confirmed three records, one visit and the corrected source on the server.                                                                                                                                     |
| Logout and sign-in           | Pass   | Logout returned to the landing page. Signing in restored three records, the appointment and its corrected, non-stale brief.                                                                                             |
| Account cleanup              | Pass   | Browser deletion returned home; subsequent login and the separate API session both returned 401. The test account and its server workspace were removed. Local fictional source files were retained for repeat testing. |

## Scope and observations

No blocking defect was found in the completed checks. These results establish the tested workflow, not an exhaustive product certification.

The generated summaries omitted the fixtures' “fictional” preamble, although the source titles, originals and citations retained it. For hackathon presentation, keep fictional labels visible and do not rely on the summary alone to identify test data.

Not exercised in this run: browser file selection/import, PDF/image OCR, microphone permission/capture, transcription, print-dialog/PDF export, mobile layouts or a separate physical device. Earlier deployment checks of transcription are documented separately and are not counted as this user test.

## Follow-up: actual browser scan/import verification

Completed later on September 12 against the live site using a separate **Fictional Scan Verification** account. Files were selected through the browser's real upload control and file chooser, reviewed in the import dialog, and saved with **Save to Records**. No records were inserted through the API for this follow-up; API reads only verified the results.

| Input                                         | Reading result                                                                                | Saved result                                                                                  |
| --------------------------------------------- | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `reva-synthetic-laboratory-results.pdf`       | 1,175 characters extracted, including hemoglobin 13.4 g/dL and the remaining reported values. | Record and original PDF saved.                                                                |
| `reva-synthetic-symptom-diary-scan.png`       | Local English OCR produced 1,078 characters and an explicit review warning.                   | Scan record, OCR text and original image saved.                                               |
| `reva-synthetic-symptom-diary-image-only.pdf` | Local OCR produced 1,077 characters from the image-only PDF.                                  | Record, OCR text and original PDF saved; manually selected source date September 7 persisted. |

All three appeared in Records after a full reload. Authenticated server reads confirmed the extracted text and all three originals matched the selected files byte-for-byte. [Records screenshot](screenshots/scan-import-records.png).

OCR correctly requires review: the deliberately obscured date in the fixtures was read as “September Of” in the image and “September Oy” in the scanned PDF. Legible symptom content was extracted, but this is not a claim of perfect recognition. Record metadata initially defaults to today's date; users must choose the source date during review. Keyboard edits to the native date input persisted; an automated `fill` attempt alone did not update the form state.

This closes the earlier browser-upload/PDF/OCR coverage gap for these three fixtures. Camera capture, handwriting beyond the fixture, mobile devices and print export remain outside this verification.

The separate scan-test account and its imported records were deleted after verification; the browser returned to the landing page. Only the report and screenshot are committed, not test credentials.

## Follow-up: blocked original PDF preview

The example account exposed a gap in the earlier scan check: original PDF bytes were saved correctly, but Chrome blocked the embedded PDF viewer. Successful extraction and attachment downloads did not establish that the visual PDF preview worked.

Saved-record originals and the import comparison now use the existing PDF.js renderer directly, with previous/next controls and the actual PDF page count. Rendering uses a detached canvas, a 2,200-pixel maximum side, a 16 MB input limit and a 30-second deadline. Dismissal cancels pending work; failures offer the unchanged original download. The existing content security policy remains unchanged.

- [x] Real image-only PDF renders nonblank source pixels in regression tests.
- [x] Real two-page PDF opens page two and clamps out-of-range page requests.
- [x] Malformed files and cancellation before/during byte loading fail safely.
- [x] Chrome under the production security policy displays both procedure pages, including page-two implant inventory; previous/next controls work.
- [x] Actual browser import of the image-only PDF produces 1,077 OCR characters and displays its original page in the comparison panel.
- [x] All 244 browser tests, production build, formatting and source structure checks pass after integrating concurrent homepage/visit changes.

These browser checks used the local production build. Deployment and the same example-account record must also be checked on the live site after publishing.
