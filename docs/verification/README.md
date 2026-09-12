# Reva verification evidence

Evidence is being collected against the actual native app and backend. Final completion auditing remains pending until the complete walkthrough and final review finish.

| Check | Observed result |
| --- | --- |
| Installed toolchain | Xcode26.4, Swift6.3, iOS26.4; native project opened in Xcode |
| Native executable | Integrated Reva scheme builds; iPhone17 installs and launches |
| Core and fixture tests | 23 tests passed before the additional date/question regression; all explicit expected record sets, page2 implant excerpt and lab value checked |
| Native client/server | Real URLSession client ↔ temporary Vapor server: health/auth/owner isolation, full state domains, all9 original attachments, revisions, conflicts, deletion/tombstones passed |
| Server unit/integration | 8 local tests passed; live PostgreSQL test skipped by explicit credential gate |
| Server process behavior | HTTP restart persistence and failed-PostgreSQL/no-fallback checks passed |
| Device adapters | 26 isolated simulator checks passed, including OCR/bytes/limits, source pages, paginated PDF and real tone playback |
| Manual booking flow | Reviewed details → queued → proposed → confirmed; existing visit updated with no real call |
| Manual sample memory | Explicit sample transcript opened; saved to Records; persisted recording isSample=true, associated with its original completed fixture visit, audioFilename absent |

Screenshots in `screenshots/` contain fictional data only. Generated 16-page device-adapter export was rendered and inspected by the contributor and primary; final native-app brief export will be inspected separately. Physical camera capture, actual microphone input/hardware interruptions, signing, live Tiger and provider credentials remain manual prerequisites.
