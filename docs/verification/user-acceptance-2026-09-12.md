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
