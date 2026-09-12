# Appointment recording, transcription and summaries

September 12, 2026. User requested removal of calling and a clear appointment record/transcribe/summarize flow with doctor consent. [Current scope/spec comparison](../reva-stack-spec.md) and [updated stack diagram](../architecture.md) describe the resulting product.

## Delivered behavior

- Both clients expose **Record appointment** and require confirmation that the doctor and everyone present agreed. The disclaimer reads: **Get your doctor’s consent and permission from everyone present before recording.** Browser uploads/save are gated too.
- Saved audio can be transcribed with Whisper and its exact full timestamped transcript summarized with Gemini. AI output has separate model/time provenance; personal notes and source audio/transcript remain intact.
- Transcript edits invalidate AI. In-flight results cannot overwrite changed recordings or a new connection context. Summary/transcription publication and updates to existing memory commit together, preserving independently edited memory notes.
- New memory dates use US Central time, including UTC-midnight boundaries. Existing edited dates remain unchanged.
- Calling/simulation views, engines, routes, provider configuration and active setup instructions are removed. Authenticated and unauthenticated requests to retired call endpoints return 404. The legacy bookings array remains inert for non-destructive old-snapshot compatibility.
- The approved native glass tab implementation, existing time-zone defaults, account storage, record evidence, OCR and other features remain intact.

## Executed checks

| Check | Result |
| --- | --- |
| Web unit and component tests | 216 passed across 19 files |
| Browser proxy HTTP tests | 7 passed, including no upstream dispatch for retired calling paths |
| TypeScript, web production build and whole-web formatting | Passed |
| Core Swift package | 57 passed, one opt-in live-client test skipped in package run |
| Native state/audio harness | Passed: five provider operations, 60 stale result cases, cancellation, exact transcript summary input, atomic failed writes, edited notes/dates, summary invalidation and audio recovery |
| Native optimization harness | R1/R2/R3/R5/R6/R9 passed |
| iOS Simulator build | Passed after project regeneration and final Central-date change; 48 app Swift files and 15 resources |
| Server suite and build | 53 passed; two live PostgreSQL tests skipped |
| Real provider HTTP smoke | Four authenticated routes, three safe unconfigured failures and retired calling 404s passed |
| Real native client ↔ temporary local Vapor API | Passed auth, full domains, stale conflicts, nine original sources, owner isolation, Unicode metadata and deletion tombstones |
| Swift lint / structure / diff whitespace | Passed; 65 Swift and 76 browser files checked for source contracts/sections |
| iPhone simulator walkthrough | Appointment page has recording and no calling; explicit doctor-consent notice; Start disabled before consent; sample transcript exposes summary action and missing-setup guidance |
| Production browser walkthrough | Appointment page has recording and no calling; doctor-consent notice; Start/upload/save disabled before consent; recording dialog visually inspected |

New focused tests include `Tests/RevaCoreTests/AppointmentRecordingTests.swift`, browser `recordingSummary.test.ts` and `appointmentWorkflow.test.tsx`, plus server transcript-grounding and retired-route tests. Native and browser original fixture JSON remains unchanged. Root `.env` stays empty/ignored; provider credentials were not read or used.

## Remaining verification

No live Gemini/Whisper request, real microphone/camera capture, physical-device interruption check, Tiger/PostgreSQL round trip, or hosted deployment was performed. Component and mocked transport tests establish code behavior, not live model quality or production readiness. The earlier calling setup/test documents are available in Git history and are no longer current setup instructions.
