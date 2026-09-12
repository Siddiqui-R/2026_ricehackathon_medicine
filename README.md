# Reva

**Making every appointment count.** A SwiftUI iPhone and responsive React browser MVP for importing medical records, preparing cited visit briefs, and keeping visit memories. Start with a clearly fictional dataset; provider accounts are optional manual setup. The [current scope and spec comparison](docs/reva-stack-spec.md) describes what is built and what remains deferred.

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
- Open an appointment, get the doctor’s and everyone present’s consent, record and save audio, then transcribe and summarize it when the providers are configured. AI summaries remain separate from your personal notes.
- Open the separate sample transcript, correct text or add notes, save a visit memory, and follow its source link. New microphone audio never receives an unrelated sample transcript.

The gear in Medical profile opens Settings for server configuration and explicit demo reset. Local state survives relaunch. Deleted/reset items leave active history, while original files and one previous-state backup remain in app storage for recovery; uninstalling clears that sandbox. No real records are bundled or automatically imported.

## Configurable APIs

The browser deploys with a same-origin Node.js backend on Vercel, using Tiger PostgreSQL for accounts, snapshots and originals. See the [deployment and verification checklist](docs/deployment-vercel.md). The Swift server remains available for local/native development. Configuration flags report settings, not a successful credential probe.

| Feature | Implemented behavior |
| --- | --- |
| Gemini | Document summaries, visit preparation and summaries of full appointment transcripts; configurable model, default `gemini-3.8-flash`. Selected IDs are validated; original-source citations come from local records. |
| OpenAI Whisper | Saved-audio transcription using `whisper-1`, with recording-relative segment times and generic speaker labels; no diarization claim. |
| ElevenLabs Scribe | Vercel saved-audio transcription using `scribe_v2`, recording-relative timestamps and neutral speaker labels. |
| Local workflow | Import/OCR, reviewable excerpts, cited briefs/PDF, consent-gated recording/playback and sample memory work without provider setup. |
| Tiger Data PostgreSQL | Shared versioned JSONB/BYTEA schema for accounts, snapshots and originals; Vercel integration tested against Tiger with isolated fictional accounts. |

From the repository root, start the local API:

```sh
python3 scripts/run_server.py --build
```

The launcher reads optional dotenv values without shell evaluation; exported environment variables take precedence. The root `.env` is local and Git-ignored. A fresh clone can create it with `touch .env`. Use the commented [root example](.env.example) and [server example](server/.env.example) for later manual setup; provider secrets stay on the server.

Local defaults are `http://127.0.0.1:8080` and the public demo token `reva-local-demo-token`. Set the URL/token in the app's server settings. Provider requests require a private configured identity and server-side keys. See the [provider setup and routes](server/README.md#configurable-mvp-providers) and [MVP wire contract](docs/task-specs/mvp-api-contract.md).

The phone stays locally authoritative between explicit server push/pull actions. The server provides owner-scoped revisions and conflict errors. Attachment transfers and snapshot commits are separate transactions, so a failed transfer may leave files already copied. Details and limits are in the [server guide](server/README.md).

See the [full-stack architecture and flow diagrams](docs/architecture.md) for the implemented client, server, database, provider boundaries, and data journeys.

Accounts and hosted persistence: the browser's `/signup`, `/login`, and `/app` pages use the API's `POST /v1/auth/signup`, `POST /v1/auth/login`, `GET /v1/auth/session`, `POST /v1/auth/logout`, `POST /v1/auth/logout-all`, `PUT /v1/auth/password`, and `DELETE /v1/auth/account` routes, with each account's data in Tiger Cloud PostgreSQL when `REVA_STORAGE=postgres`. The [Tiger setup guide](docs/tiger-setup.md) covers the free shared service (`scripts/tiger_provision.py`), `server/Dockerfile`, the Vercel `VITE_REVA_API_ORIGIN` setting, and a verification checklist; the [accounts architecture section](docs/architecture.md#accounts-and-tiger-persistence) shows the flows. Configured, not live-verified.

## Appointment recording

Choose **Record appointment** in an appointment. **Get your doctor’s consent and permission from everyone present before recording.** The confirmation gates microphone capture; browser uploads require it too. Saved original audio can be transcribed with Whisper, reviewed/corrected, and summarized with Gemini. Generated summaries are labeled, remain separate from personal notes, and are invalidated when the transcript changes. Save a visit memory to retain the full transcript source and its recording link in Records.

Appointment calling and booking simulation have been removed. Older snapshot booking data is preserved only for compatibility.

## Project overview packet

The [seven-page PDF packet](output/pdf/reva-project-overview-packet.pdf) covers existing worktrees, proposed team ownership, technologies, data flows, functionality, API setup, and verification. The [editable Markdown source](docs/project-overview-packet.md) records the same `d0af1df` baseline; use the current team workflow and coding standard for the later file split. Rebuild both with `scripts/build_overview_packet.py` in a Python environment with ReportLab and the documented macOS fonts.

## Work in parallel

The [three-person workflow](docs/team-workflow.md) assigns exact files, safe worktrees, shared-contract ownership and integration steps. The [coding standard](docs/coding-standard.md) describes focused source blocks, leading responsibility comments, formatting and the structure check:

| Area | Source |
| --- | --- |
| Records and preparation | [Features/Records](apps/ios/Reva/Features/Records), [Features/Preparation](apps/ios/Reva/Features/Preparation) |
| Appointment recording and visit memory | [Features/Visits](apps/ios/Reva/Features/Visits) |
| Browser UI and state | [apps/web](apps/web), [browser wire compatibility](apps/web/src/core/COMPATIBILITY.md) |
| Shared native contracts/state | [Core](apps/ios/Reva/Core), [State](apps/ios/Reva/State), [Features/Shared](apps/ios/Reva/Features/Shared) |
| Device adapters / backend providers | [Device](apps/ios/Reva/Device), [server](server) |

## Verification and limits

The [appointment recording verification](docs/verification/appointment-recording.md), [integration report](docs/reviews/08-preserved-integration.md), [repair report](docs/reviews/06-audit-repairs.md) and [23-finding checklist](docs/reviews/audit-repair-status.csv) record the integrated fixes, fresh native/browser checks, concurrent Windows-checkpoint reconciliation and remaining device/service gates. The earlier totals below are historical.

Latest browser-extension verification: **77 browser tests, 7 isolated HTTP-wrapper tests, 43 native tests, and 30 server tests passed**; one native real-server gate and one live PostgreSQL gate skipped. TypeScript/production build, native simulator compilation, formatting, and responsibility-block checks passed. See [browser verification and screenshots](docs/verification/web-client.md) for the tested responsive widths and local user journeys. Earlier [native verification](docs/verification/README.md) remains historical evidence; older teal screenshots do not show the current heart-red design.

```sh
swift test -j 6
swift test --package-path server -j 6
python3 scripts/test_client_server.py
python3 scripts/check_provider_api.py
```

Build the server before running the two Python checks. [Progress](docs/build-progress.md), [verification evidence](docs/verification/README.md), and [review history](docs/reviews/review-log.md) distinguish executed checks from manual setup.

Physical iPhone signing, camera/microphone input and hardware interruptions require device verification. Recording pauses outside the foreground. Provider keys and a live Tiger database remain manual prerequisites. This is a synthetic hackathon prototype, not a production medical deployment; extraction and AI output need review. MyChart import, custom encryption and production deployment remain outside this MVP. The browser extension is implemented; live provider credentials, cross-browser hardware checks and production operations remain manual setup.

### Optimization regression checks

The [optimization checklist](docs/optimization-review-checklist.md) records six
implemented fixes, their compatibility checks, and the remaining work. With Swift
installed, run `python scripts/check_optimization_fixes.py` for focused state,
storage, and intercepted-HTTP checks using synthetic inputs. These checks also run
on Windows with test doubles for unavailable Apple observation APIs; they do not
replace the full package suites or iPhone build.

Native pull now preserves existing original files: conflicting bytes under the same
filename stop the pull for review. Identical originals and newly named files still
sync normally, and a failed pull removes its newly staged files when possible.

### Medical profile and symptom log

Open **Medical profile** (or the Summary avatar) for persistent allergies, medications, conditions, surgeries/implants, and care notes. Its gear opens Settings. Use **Log symptoms** on Summary or the Records add menu to save a dated **User symptom entry**. Optional fields capture severity, duration, details, possible triggers, and what helped; entries can be edited, searched, and used as sources during visit preparation. **View all records** at the bottom of Recent records switches to the full Records tab.

The current light theme uses the selected heart-red roles above. The [earlier profile and symptom verification](docs/verification/profile-symptoms.md) records the functionality at its prior palette checkpoint.
