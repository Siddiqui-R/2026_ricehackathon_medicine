> **Latest follow-up:** [Browser extension verification](web-client.md) records the responsive web client, current heart-red palette, and updated test counts. The native MVP evidence below is historical; older teal screenshots are not the current design.

> Latest scope and checks: [appointment recording, transcription and summaries](appointment-recording.md). Calling has been removed. The counts and calling evidence below are historical.


# Reva MVP verification evidence

Current scope is the [user's two-hour MVP revision](../mvp-goal.md). All application content used below is fictional. No paid AI request, actual clinic call, or live Tiger database operation was executed.

| Check | Observed result |
| --- | --- |
| Native toolchain/build | Xcode26.4, Swift6.3, iOS26.4; current25-source native app builds and launches on iPhone17 simulator |
| Exact supplied palette | Six source hex values preserved; adaptive dark overrides removed. Ivory canvas/Sky cards/Teal actions/Ivory button text visually verified in current app |
| Root suite |35 registered,34 local/mocked tests passed,1 gated native-server test skipped by default |
| Backend suite |30 registered,29 local/mocked tests passed,1 live PostgreSQL test skipped |
| Real native client/server | Actual URLSession↔temporaryVapor health/auth/owner separation, all9 original attachments/full domains, revisions/conflicts/deletion-tombstones passed |
| Real provider HTTP smoke | Auth on all6 provider routes, exact status schema, and4 safe503 unconfigured responses passed; no provider calls |
| Gemini mocks |8 tests: private configuration, structured output, source ID validation, malformed/blocked responses and error redaction |
| Voice mocks |13 tests: multipart audio, relative timestamps, input bounds, consent/config checks, durable concurrent/restarted/uncertain call replay and owner-scoped polling |
| Device adapters |26 isolated simulator checks passed for extraction/OCR/error limits/source bytes/pages/paginated PDF and actual tone playback |
| Transcript persistence |17 isolated actual AppStore checks passed: words-only corrections, timestamps/speakers/audio/origin/notes retained, existing memory updated atomically and idempotently |
| Core native walkthrough | Import fictional text→review/save→orthopedic brief→implant PDF page2→title/date review→stale report→edited questions/regeneration→PDF preview/native share verified |
| Visit/booking flow | Add/edit fictional visit, consent-gated recording UI, simulated queued→proposed→confirmed with no duplicate visit verified |
| Sample memory | Explicit sample saved, persisted after relaunch, and linked back to its correct transcript. Correction editor inspected; native save click was canceled after Computer coordinate control failed; persistence is covered by the harness above |
| Native provider UI | Localhost mock-transport-only fixture: discovered configuration, saved model-labeled summary, generated structured preparation retaining exact original source links |
| Reset/persistence | Edited visit, imported record, booking/sample state and reports survived relaunch; explicit reset then restored known9-record/3-visit fixture data and survived another relaunch |
| Export | Six-page actual app brief in orthopedic-brief.pdf was text-extracted and all pages rendered/inspected; native preview and share sheet opened |

## Artifacts

- [Current exact-palette Summary](screenshots/summary-exact-palette.png)
- [Native provider-fixture brief](screenshots/provider-fixture-brief.png) — explicitly mocked; captured before the palette correction.
- [Implant original page2](screenshots/implant-page-2.png)
- [Native PDF share](screenshots/pdf-share.png)
- [Actual exported orthopedic brief](orthopedic-brief.pdf)

Earlier `summary-dark.png` is retained as rejected design history, not the shipped palette. Other early screenshots may show earlier light neutral surfaces. Current appearance authority is `design/palette.json`; these captures preserve the earlier MVP appearance.

## Repeat the essential checks

```sh
swift test -j 6
swift test --package-path server -j 6
python3 scripts/test_client_server.py
python3 scripts/check_provider_api.py
```

Build the server first. The Python checks own and clean up temporary localhost processes and synthetic data. The local UI fixture is optional: `python3 scripts/mock_provider_server.py` exposes only synthetic Gemini-shaped responses at localhost8082 and never calls a provider. Restore localhost8080 and reset the demo afterward.

Physical iPhone signing, camera input, microphone input and hardware interruption behavior remain manual checks. Live Gemini/OpenAI/ElevenLabs/Tiger credentials, agent prompt/number setup and credentialed smoke checks remain manual prerequisites. Broader device/text-size polish and repeated reviews were deferred by the user's deadline revision.


## Code organization follow-up

The [September 12 source-organization verification](code-organization.md) records the focused file split, block contracts, formatter, structure check, native build and regression results at source checkpoint `30bd762`.
