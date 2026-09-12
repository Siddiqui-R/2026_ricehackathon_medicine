# Reva — current scope and stack

Updated September 12, 2026 after the user removed appointment calling and prioritized recording, transcription, and appointment summaries. The [original spec sheet](reva-stack-spec-planning.md) is retained as historical planning; this document controls current scope. See [architecture](architecture.md) for runtime boundaries and [verification](verification/appointment-recording.md) for this revision’s checks.

## Where the product is

| Area | Current state versus the original proposal |
| --- | --- |
| Records and preparation | Built: PDF/image/text import, local OCR, originals, search, source edits, cited appointment briefs, questions, stale-source checks, PDF/print export. Full structured clinical extraction and cloud jobs remain unbuilt. |
| Appointments | Built: manual appointment entry/editing, Central-time defaults, preparation, record/upload audio, timestamped transcription, separate AI appointment summary, personal notes, and saved transcript-backed memory. Calling and booking simulation are removed. |
| Clients | Native SwiftUI iPhone plus responsive React/TypeScript browser. The browser is already delivered, beyond the original “later phase.” |
| Identity | Browser accounts, bcrypt passwords, hashed sessions, per-user storage, and auto-sync are implemented. This replaces the proposed Identity Platform/Sign in with Apple path. Native uses configured bearer tokens. |
| Storage | Atomic native JSON/files, browser IndexedDB, server local files or PostgresNIO PostgreSQL JSONB/BYTEA. Tiger configuration/provisioning exists; live deployment is unverified. Private Google Cloud Storage and Fluent are not used. |
| AI and OCR | Gemini for records, preparation and appointment summaries; OpenAI Whisper for transcription; Vision/PDFKit or PDF.js/Tesseract for OCR. These replace proposed Document AI and Google Speech-to-Text. Live credentials/model access still need verification. |
| Deferred | MyChart/FHIR/HealthKit, managed Apple sign-in, object storage, durable cloud jobs/workers, calendar/reminders/APNs, vector retrieval, production hardening and medical-data deployment. |

## Appointment recording

1. Open an appointment and choose **Record appointment**. Ask the doctor and everyone present for permission before recording; confirm consent before capture. Browser audio uploads require the same confirmation.
2. Stop and save the original audio. Failures preserve captured audio for retry; microphone capture is never replaced with a fictional sample.
3. **Transcribe** saved audio with the configured server. Relative timestamps and the original audio remain available for review and correction. Speaker labels do not claim reliable doctor/patient diarization.
4. **Summarize appointment** from the exact timestamped transcript. The generated summary, model and timestamp are separate from personal notes. Source changes invalidate the old summary; stale in-flight responses cannot replace newer data.
5. Save/update a visit memory in Records. Its source is the full transcript, with the AI summary only as a derived view. Corrections retain source identity, timing, notes and audio.

Consent notice: **“Get your doctor’s consent and permission from everyone present before recording.”** AI transcription and summaries need review against the source.

## Stack and deployment

| Layer | Repository implementation |
| --- | --- |
| iPhone | SwiftUI, Foundation/Codable, Observation, PDFKit, Vision/VisionKit, AVFoundation, UIKit PDF rendering |
| Browser | React, TypeScript, Vite, IndexedDB, PDF.js, local Tesseract, MediaRecorder, browser print |
| API | Swift/Vapor, authenticated REST/JSON, bounded operations, owner revisions and explicit conflicts |
| Accounts | Bcrypt on worker threads; opaque hashed session tokens; expiry/revocation; atomic password/session checks |
| Database | Local file adapter or PostgresNIO; migrations 001/002; Tiger-compatible PostgreSQL |
| AI | Server-side Gemini `GEMINI_MODEL` (repository default `gemini-3.8-flash`); OpenAI `whisper-1` |
| Hosting | Vercel static browser configuration; containerized Swift API and Tiger setup instructions. Live API/database readiness is unverified. |

Model IDs describe configuration, not proof of availability. Provider keys stay server-side. The default time zone is `America/Chicago` (CST/CDT); explicit saved zones and date-only calendar values are preserved.

## Active API surface

- `/health`; authenticated `/v1/state` and `/v1/attachments/:filename` for revisioned snapshots and originals.
- `/v1/auth/signup`, `/login`, `/session`, `/logout`, `/logout-all`, `/password`, `/account` under the auth prefix.
- `GET /v1/providers` exposes only Gemini and transcription configuration.
- `POST /v1/ai/summarize` handles record or full appointment-transcript text; `POST /v1/ai/prepare` handles visit preparation.
- `POST /v1/audio/transcribe` accepts saved original audio.

Calling routes, screens, provider settings and booking simulation no longer exist. The legacy `bookings` snapshot array remains inert solely to preserve older saved/synced data; no code creates or executes a call from it. Existing historical call files are not deleted from user storage.

Setup: [root guide](../README.md), [browser guide](../apps/web/README.md), [server guide](../server/README.md), [Tiger guide](tiger-setup.md), [API contract](task-specs/mvp-api-contract.md).
