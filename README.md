# Reva

**Making every appointment count.** A native SwiftUI iPhone prototype for bringing medical records together, preparing a relevant visit brief, and keeping the details afterward. Built around Apple Health’s native hierarchy and the exact six-color palette in [design/palette.json](design/palette.json).

## Run the iPhone app

Requires macOS with Xcode and an installed iOS simulator. Verified with Xcode26.4, Swift6.3 and iOS26.4; deployment target iOS18. No third-party client packages or provider keys are needed.

1. Open `Reva.xcodeproj` in Xcode.
2. Select the **Reva** scheme and an iPhone simulator, then Run.
3. Choose **Explore Reva**. All seeded people and medical documents are fictional.

The project is checked in. Regenerate it after adding Swift files or bundled resources:

```sh
python3 scripts/generate_project.py
```

A reproducible command-line build:

```sh
xcodebuild -project Reva.xcodeproj -scheme Reva \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

For a physical iPhone, choose your own development team/signing in Xcode. Camera scanning needs a real supported iPhone. Microphone permission and consent are required before recording. Recording pauses when Reva leaves the foreground; saved audio has playback, but live transcription is unconfigured.

## Try the demo

[Presentation walkthrough](demo/demo-script.md) · [Standalone fictional records](demo/README.md) · [Full task list](docs/task-list.md)

- **Summary:** open the upcoming nausea/palpitations visit and create its brief.
- **Visits:** compare the orthopedic brief, including the historical implant inventory on page2. Open its source, pin additional records, and edit questions.
- **Records:** search/filter, open an original, add a fictional sample or import a PDF/text/image, review its extraction and save. Edit a source and regenerate an out-of-date brief.
- **Booking:** review a clinic/date window and run an explicitly simulated success, needs-input, or no-answer scenario. Confirming updates the existing local visit once.
- **Visit memory:** open the separate fictional transcript, edit notes, and save its memory to Records. New microphone recordings never receive this sample transcript.
- **Share:** export the current visit brief to a paginated PDF using the native preview/share control.
- **Profile & settings:** choose appearance, inspect connection status, and explicitly restore the fictional demo.

All active state persists locally across relaunch. Deleted/reset items leave the active history; their original bytes and one previous-state backup remain in app storage for recovery. Remove the app to clear that sandbox. No real patient data is bundled or automatically imported.

## What works and what is deferred

| Area | This prototype |
| --- | --- |
| iPhone UI and local persistence | Functional SwiftUI screens and atomic local JSON/files |
| Files/photo/camera intake | Native adapters, PDFKit text and Vision OCR; review errors/uncertainty explicitly |
| Document memory | Automatic source-based **local excerpts**, or clearly labeled authored demo summaries |
| Pre-visit preparation | Deterministic relevant-source selection, pins, page/version evidence, editable questions and PDF export |
| Clinic booking | Local state-machine simulation; no call is placed |
| Recording | Native audio capture adapter and playback; physical input/interruptions require device verification |
| Transcription | Explicit bundled sample and manual notes; live speech service deferred |
| Swift API | Runnable Vapor server, local durable store, real native-client integration tests |
| Tiger Data PostgreSQL | Compiled PostgresNIO adapter, versioned SQL migration, JSONB domain snapshots and BYTEA sources; live database credentials/testing deferred |
| Gemini / ElevenLabs / Twilio | Documented future provider connections; no keys, network jobs or paid resources activated |
| MyChart / custom encryption / web app | Excluded from this prototype per scope; manual import and native iPhone first |

Text extraction is reviewable, not guaranteed perfect. Briefs quote source information and propose discussion questions; they do not diagnose or recommend treatment. The prototype is a fictional hackathon demonstration, with no production medical-data readiness claim.

## Server and configuration

See [server/README.md](server/README.md) for the actual HTTP contract, local run, auth/ownership, limits, PostgreSQL/Tiger setup and deferred checks. The phone never connects directly to PostgreSQL.

```sh
cd server
swift build -j 6
swift run --skip-build RevaAPI
```

Local defaults: `http://127.0.0.1:8080`, public demo token `reva-local-demo-token`, loopback only. In the simulator, **Profile & settings → Developer server connection** offers explicit probe/push/pull. The local snapshot remains authoritative between these actions. Conflicts are visible and require choosing which snapshot to keep; no network failure silently swaps in demo data.

The working folder’s root `.env` is intentionally **zero bytes** and ignored by Git. A fresh clone can create it with `touch .env`. [Root example](.env.example) and [server example](server/.env.example) contain documentation/placeholders only. The server reads exported environment variables; it does not automatically load dotenv files. The iOS app does not read server secrets or `.env`. No API configuration is needed to run the demo.

## Verification and history

```sh
swift test -j 6
(cd server && swift test -j 6)
python3 scripts/test_client_server.py
```

Native device-adapter checks and instructions live in [their task spec](docs/task-specs/device-services.md). Live PostgreSQL tests are explicitly gated on a separately supplied disposable test database. [Completion criteria](docs/completion-criteria.md), [progress and edit history](docs/build-progress.md), [review decisions](docs/reviews/review-log.md), and [verification evidence](docs/verification/README.md) distinguish executed checks from manual setup.

Checkpoint commits preserve meaningful stages. `.worktrees/implementation-review` was used for Claude Desktop’s review and bounded source/provenance revision; it is intentionally Git-ignored. Compare checkpoints with `git log --oneline` and `git diff <commit>..<commit>`. Use a new branch/worktree for a revision and apply reviewed commits or patches; no destructive reset is needed.
