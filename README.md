# Reva

**Making every appointment count.** A SwiftUI iPhone and responsive React browser MVP for importing medical records, preparing cited visit briefs, and keeping visit memories. Start with a clearly fictional dataset; provider accounts are optional manual setup. The [revised MVP goal](docs/mvp-goal.md) defines the current scope.

Both clients follow the selected [heart-red palette](design/palette.json) in **light appearance only**: blush ivory `#FBF7F5`, white cards, heart red `#B84250`, deep red `#8C2F3B`, petal `#FAE6E5`, and linen `#DBCBC9`. The [earlier supplied palette](design/palette-supplied.json) is preserved as historical provenance.

## Run the app

Verified toolchain: Xcode 26.4, Swift 6.3 and iOS 26.4 simulator; deployment target iOS 18. No third-party client packages or provider keys are needed for the local demo.

1. Open `Reva.xcodeproj` in Xcode.
2. Select the **Reva** scheme and an iPhone simulator, then Run.
3. Choose **Explore Reva**.

Regenerate the checked-in project after adding or moving sources/resources; do not manually edit its generated project file:

```sh
python3 scripts/generate_project.py
xcodebuild -project Reva.xcodeproj -scheme Reva \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Run in a browser

The browser client has a desktop sidebar, searchable records, two-column care views, and mobile navigation. It shares the native snapshot/API contract through a dedicated React interface; SwiftUI is not compiled into the browser. See the [browser guide](apps/web/README.md) for local OCR, microphone support, storage, sync, and hosting details.

```sh
cd apps/web
npm ci
npm run dev
```

Open **http://127.0.0.1:5173**. For a built preview, run `npm run build` then `npm run serve` and open **http://127.0.0.1:4173**. Both proxy the same-origin API to the local Swift server on port 8080 by default. The fictional local demo works without that server.

## Try the fictional demo

Follow the [presentation walkthrough](demo/demo-script.md) using the [standalone synthetic documents](demo/README.md).

- Import a PDF, text file or image, review its extraction, and save the automatic local excerpt. Compare any uncertain extraction with its original.
- Prepare the nausea/palpitations and orthopedic visits to see different relevant histories. The orthopedic implant evidence opens its original PDF on page 2.
- Edit questions, pin records, correct a source, regenerate a stale brief, and export/share its formatted PDF.
- Review a booking request and run the clearly labeled simulated outcome. Confirmation updates the existing local visit once.
- Open the separate sample transcript, correct text or add notes, save a visit memory, and follow its source link. New microphone audio never receives an unrelated sample transcript.

The gear in Medical profile opens Settings for server configuration and explicit demo reset. Local state survives relaunch. Deleted/reset items leave active history, while original files and one previous-state backup remain in app storage for recovery; uninstalling clears that sandbox. No real records are bundled or automatically imported.

## Configurable APIs

The Swift server, native client, and browser entry points are implemented. **No live provider request or real call was made during this build; accounts and credentials remain manual setup.** Configuration flags report settings, not a successful credential probe.

| Feature | Implemented behavior |
| --- | --- |
| Gemini | Document summaries and visit preparation; configurable model, default `gemini-2.5-flash`. Selected IDs are validated; original-source citations come from local records. |
| OpenAI Whisper | Saved-audio transcription using `whisper-1`, with recording-relative segment times and generic speaker labels; no diarization claim. |
| ElevenLabs / Twilio | Outbound call through a configured ElevenLabs agent and imported Twilio number, followed by status/transcript polling. Durable intent/receipts prevent automatic duplicate attempts. A call's completion never confirms an appointment; the user reviews and confirms details manually. |
| Local workflow | Import/OCR, reviewable excerpts, cited briefs/PDF, simulated booking, recording/playback and sample memory work without provider setup. |
| Tiger Data PostgreSQL | Compiled PostgresNIO adapter and versioned JSONB/BYTEA schema for domain snapshots and attachments. Live database setup/testing remains manual. |

From the repository root, start the local API:

```sh
python3 scripts/run_server.py --build
```

The launcher reads optional dotenv values without shell evaluation; exported environment variables take precedence. The delivered root `.env` is **exactly empty and Git-ignored**. A fresh clone can create it with `touch .env`. Use the commented [root example](.env.example) and [server example](server/.env.example) for later manual setup; provider secrets stay on the server.

Local defaults are `http://127.0.0.1:8080` and the public demo token `reva-local-demo-token`. Set the URL/token in the app's server settings. Paid providers additionally require a private configured token mapping; outbound calls require the live-call enable flag and explicit consent. See the [provider setup and routes](server/README.md#configurable-mvp-providers) and [MVP wire contract](docs/task-specs/mvp-api-contract.md).

The phone stays locally authoritative between explicit server push/pull actions. The server provides owner-scoped revisions and conflict errors. Attachment transfers and snapshot commits are separate transactions, so a failed transfer may leave files already copied. Call receipts need persistent server storage even when snapshots use PostgreSQL. Details and limits are in the [server guide](server/README.md).

See the [full-stack architecture and flow diagrams](docs/architecture.md) for the implemented client, server, database, provider boundaries, and data journeys.

## Project overview packet

The [seven-page PDF packet](output/pdf/reva-project-overview-packet.pdf) covers existing worktrees, proposed team ownership, technologies, data flows, functionality, API setup, and verification. The [editable Markdown source](docs/project-overview-packet.md) records the same `d0af1df` baseline; use the current team workflow and coding standard for the later file split. Rebuild both with `scripts/build_overview_packet.py` in a Python environment with ReportLab and the documented macOS fonts.

## Work in parallel

The [three-person workflow](docs/team-workflow.md) assigns exact files, safe worktrees, shared-contract ownership and integration steps. The [coding standard](docs/coding-standard.md) describes focused source blocks, leading responsibility comments, formatting and the structure check:

| Area | Source |
| --- | --- |
| Records and preparation | [Features/Records](apps/ios/Reva/Features/Records), [Features/Preparation](apps/ios/Reva/Features/Preparation) |
| Booking and visit memory | [Features/Visits](apps/ios/Reva/Features/Visits) |
| Browser UI and state | [apps/web](apps/web), [browser wire compatibility](apps/web/src/core/COMPATIBILITY.md) |
| Shared native contracts/state | [Core](apps/ios/Reva/Core), [State](apps/ios/Reva/State), [Features/Shared](apps/ios/Reva/Features/Shared) |
| Device adapters / backend providers | [Device](apps/ios/Reva/Device), [server](server) |

## Verification and limits

Latest browser-extension verification: **77 browser tests, 7 isolated HTTP-wrapper tests, 43 native tests, and 30 server tests passed**; one native real-server gate and one live PostgreSQL gate skipped. TypeScript/production build, native simulator compilation, formatting, and responsibility-block checks passed. See [browser verification and screenshots](docs/verification/web-client.md) for the tested responsive widths and local user journeys. Earlier [native verification](docs/verification/README.md) remains historical evidence; older teal screenshots do not show the current heart-red design.

```sh
swift test -j 6
swift test --package-path server -j 6
python3 scripts/test_client_server.py
python3 scripts/check_provider_api.py
```

Build the server before running the two Python checks. [Progress](docs/build-progress.md), [verification evidence](docs/verification/README.md), and [review history](docs/reviews/review-log.md) distinguish executed checks from manual setup.

Physical iPhone signing, camera/microphone input and hardware interruptions require device verification. Recording pauses outside the foreground. Provider accounts/keys/agent/number and a live Tiger database remain manual prerequisites. This is a synthetic hackathon prototype, not a production medical deployment; extraction and AI output need review. MyChart import, custom encryption and production deployment remain outside this MVP. The browser extension is implemented; live provider credentials, cross-browser hardware checks and production operations remain manual setup.

### Medical profile and symptom log

Open **Medical profile** (or the Summary avatar) for persistent allergies, medications, conditions, surgeries/implants, and care notes. Its gear opens Settings. Use **Log symptoms** on Summary or the Records add menu to save a dated **User symptom entry**. Optional fields capture severity, duration, details, possible triggers, and what helped; entries can be edited, searched, and used as sources during visit preparation. **View all records** at the bottom of Recent records switches to the full Records tab.

The current light theme uses the selected heart-red roles above. The [earlier profile and symptom verification](docs/verification/profile-symptoms.md) records the functionality at its prior palette checkpoint.
