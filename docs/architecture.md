# Reva — as-built MVP stack

**September 12, 2026 · browser implementation checkpoint `2640360` · current diagram updated before the documentation push.**

Reva has a native SwiftUI iPhone app, a responsive React browser client, and a shared Swift server. Both clients run the same fictional local demo and retain source provenance. Provider adapters are implemented and tested with mocks; their accounts/credentials and a live Tiger database remain manual setup. The app never needs provider keys to demonstrate the local patient journey. The [revised MVP goal](mvp-goal.md), [setup guide](../README.md), [API contract](task-specs/mvp-api-contract.md), and [verification evidence](verification/README.md) define the delivered scope.

For a shareable teammate handoff, use the [seven-page project overview packet](../output/pdf/reva-project-overview-packet.pdf) or its [editable source](project-overview-packet.md). It records the inspected worktree inventory, proposed ownership split, functionality matrix, and setup guide at baseline `d0af1df`. The [coding standard](coding-standard.md), [browser guide](../apps/web/README.md), and current team guide describe the later source-file split and browser extension; the baseline PDF is historical.

## Full stack at a glance

Petal nodes work locally. White nodes with red outlines are implemented provider/database boundaries that need configuration. Dashed nodes are external accounts or infrastructure that have not been activated by this build.

```mermaid
flowchart TB
    subgraph PHONE["Native iPhone app · SwiftUI · iOS18+"]
        UI["Summary / Records / Visits / Medical profile / Settings"]
        FEATURES["Feature modules and AppStore extensions"]
        CORE["Codable domain models / source versions / report engine"]
        LOCAL["LocalRepository: atomic JSON + one backup + original files"]
        DEVICE["PDFKit / Vision OCR / VisionKit scan / AVFoundation / PDF export"]
        CLIENT["ServerClient + ProviderClient / URLSession"]
        UI --> FEATURES --> CORE
        FEATURES --> LOCAL
        FEATURES --> DEVICE
        FEATURES --> CLIENT
    end
    subgraph WEB["Responsive browser · React19 / TypeScript7 / Vite8"]
        WEBUI["Overview / Records / Visits / Medical profile / Settings"]
        WEBSTATE["RevaContext + serialized store / shared Codable JSON contract"]
        IDB["IndexedDB: snapshot revisions + original Blobs"]
        WEBDEVICE["PDF.js / local Tesseract English OCR / MediaRecorder / browser print"]
        PROXY["Same-origin Node static host / fixed loopback API proxy"]
        WEBUI --> WEBSTATE --> IDB
        WEBSTATE --> WEBDEVICE
        WEBSTATE -->|"fetch /v1 / memory-only bearer token"| PROXY
    end
    subgraph API["Swift server · Vapor4 / private bearer owner identity"]
        ROUTES["Authenticated state, attachment and provider routes"]
        STORE["RevaStore boundary / revisions / owner-scoped writes"]
        FILES["LocalFileStore / private durable owner files"]
        PG["PostgresNIO / migration001 / parameterized transactions"]
        GEMINI["Gemini summary and preparation adapter"]
        WHISPER["Whisper multipart audio adapter"]
        CALL["ElevenLabs outbound + conversation polling"]
        RECEIPTS["Durable owner/request call receipts / fsync / single-writer lock"]
        ROUTES --> STORE
        STORE --> FILES
        STORE --> PG
        ROUTES --> GEMINI
        ROUTES --> WHISPER
        ROUTES --> CALL --> RECEIPTS
    end
    CLIENT -->|"HTTPS; loopback HTTP for simulator"| ROUTES
    PROXY -->|"Explicit authenticated push/pull and provider requests"| ROUTES
    PG -.-> TIGER["Tiger Data PostgreSQL account"]
    GEMINI -.-> GOOGLE["Google Gemini Developer API"]
    WHISPER -.-> OPENAI["OpenAI Audio Transcriptions API"]
    CALL -.-> ELEVEN["ElevenLabs configured agent"]
    ELEVEN -.-> TWILIO["Imported Twilio number → clinic"]
    classDef local fill:#FAE6E5,stroke:#B84250,color:#342B2C;
    classDef adapter fill:#FFFFFF,stroke:#B84250,color:#342B2C;
    classDef external fill:#FBF7F5,stroke:#DBCBC9,color:#342B2C,stroke-dasharray:5 5;
    class UI,FEATURES,CORE,LOCAL,DEVICE,CLIENT,WEBUI,WEBSTATE,IDB,WEBDEVICE,PROXY,ROUTES,STORE,FILES,RECEIPTS local;
    class PG,GEMINI,WHISPER,CALL adapter;
    class TIGER,GOOGLE,OPENAI,ELEVEN,TWILIO external;
```

Each client remains locally authoritative between sync operations. Its server snapshot transfers are explicit push/pull actions; they are separate from individual AI or calling requests. Neither client connects directly to PostgreSQL. The browser is a separate interface using the existing wire contract, not a SwiftUI-to-web compilation. Its production host permits only current API routes and a fixed loopback destination; HTTPS termination is a hosting setup step. Provider responses update local state only after validation, and generation checks protect source/visit edits made while a request is running.

## Stack inventory

| Layer | Actual implementation | Entry point / setup |
| --- | --- | --- |
| Native app | Swift6.3 compiler, SwiftUI, iOS18 deployment target; verified Xcode26.4/iOS26.4 simulator | [RevaApp.swift](../apps/ios/Reva/RevaApp.swift), [Xcode project](../Reva.xcodeproj) |
| Design | Selected blush ivory `#FBF7F5`, white, heart red `#B84250`, deep red `#8C2F3B`, petal `#FAE6E5`, linen `#DBCBC9`; fixed light appearance | [Theme](../apps/ios/Reva/Features/Shared/Theme.swift), [source palette](../design/palette.json) |
| Browser | React19.3.0, TypeScript7.0.2, Vite8.3.0, lucide-react1.45.0; desktop sidebar/two-column layout and mobile bottom navigation | [Browser guide](../apps/web/README.md), [app shell](../apps/web/src/App.tsx) |
| Browser state and devices | IndexedDB revisions/Blobs; PDF.js6.3.289; Tesseract.js7 with local English assets; MediaRecorder; print CSS | [Core](../apps/web/src/core), [records](../apps/web/src/features/records), [visits](../apps/web/src/features/visits) |
| Browser hosting | Node24 verified; static dist + bounded same-origin loopback proxy; no arbitrary external target or client provider keys | [serve.mjs](../apps/web/scripts/serve.mjs), [HTTP regression suite](../apps/web/scripts/serve.test.mjs) |
| State/domain | Codable snapshots, record versions, source-page references, visit/report/question authority, booking and recording state | [Core](../apps/ios/Reva/Core), [focused AppStore extensions](../apps/ios/Reva/State) |
| Local storage | App Support JSON state with atomic save/backup; original documents/audio stored separately | [LocalRepository.swift](../apps/ios/Reva/Core/LocalRepository.swift) |
| Document intake | Files/PhotosUI, PDFKit embedded text, Vision OCR, VisionKit supported-device scanner; review warnings and bounded inputs | [Device adapters](../apps/ios/Reva/Device) |
| Recording/export | AVFoundation capture/playback, timestamped transcript UI, UIKit/CoreText PDF pagination, PDFKit/QuickLook preview and native sharing | [Visit features](../apps/ios/Reva/Features/Visits), [ReportPDFRenderer](../apps/ios/Reva/Device/ReportPDFRenderer.swift) |
| Native HTTP | Foundation URLSession; explicit bearer token; HTTPS except loopback; provider secrets stay on server | [ServerClient](../apps/ios/Reva/Core/ServerClient.swift), [ProviderClient](../apps/ios/Reva/Core/ProviderClient.swift) |
| Swift backend | Vapor4.122.1, bounded authenticated routes, safe errors and owner-scoped data access | [HTTP.swift](../server/Sources/RevaServer/HTTP.swift), [server package](../server/Package.swift) |
| Database | PostgresNIO1.33.1, TLS verification, migration001; JSONB snapshots, BYTEA originals and mutation audit | [PostgresStore](../server/Sources/RevaServer/PostgresStore.swift), [SQL](../server/Sources/RevaServer/Migrations/001_snapshot.sql) |
| Document/visit AI | Gemini Developer API `generateContent`; default `gemini-2.5-flash`, configurable `GEMINI_MODEL`; structured JSON validation | [Gemini provider files](../server/Sources/RevaServer/Providers/GeminiService.swift) |
| Speech AI | OpenAI `whisper-1`, multipart `verbose_json`, segment timestamps and generic speaker labels | [Whisper adapter](../server/Sources/RevaServer/Providers/VoiceTranscription.swift) |
| Calling | ElevenLabs Twilio outbound endpoint and conversation status API; durable replay receipts; no automatic appointment confirmation | [VoiceCalls.swift](../server/Sources/RevaServer/Providers/VoiceCalls.swift) |
| Configuration | Root `.env` delivered empty and ignored; optional safe dotenv launcher; exported environment overrides file values | [run_server.py](../scripts/run_server.py), [example](../.env.example), [provider setup](../server/README.md#configurable-mvp-providers) |

The verified Gemini default uses a current documented model ID. The earlier planning names are not assumed available: choose a model your account supports through `GEMINI_MODEL`. The selected MVP speech path is Whisper; local Whisper and Google Speech-to-Text are alternatives for later work, not extra hidden integrations. Official API references are linked in the [server guide](../server/README.md) and adapter source.

## Documents → memory → visit brief

```mermaid
flowchart TD
    SYMPTOM["Log symptoms: observed time + optional severity/details"] --> OBSERVATION["Save self-reported MedicalRecord + structured SymptomEntry"]
    OBSERVATION --> MEMORY
    IMPORT["Files / photo / iPhone scanner or browser camera picker"] --> EXTRACT["Native PDFKit + Vision / browser PDF.js + Tesseract"]
    EXTRACT --> REVIEW["Preview original + text + warnings; correct date/text"]
    REVIEW --> SAVE["Save original bytes + record + local excerpt"]
    SAVE --> MEMORY["Searchable versioned record memory"]
    SAVE --> ENABLED{"Connected AI enabled?"}
    ENABLED -->|"Yes, usable text"| SUMMARY["POST /v1/ai/summarize → Gemini"]
    SUMMARY --> VALID["Validate response; keep concurrent edits; label model"] --> MEMORY
    MEMORY --> VISIT["Visit type, concern, goal and pinned records"]
    VISIT --> MODE{"Preparation mode"}
    MODE -->|"Local"| LOCAL["Keyword/context selection over full text"]
    MODE -->|"Connected"| AI["POST /v1/ai/prepare → overview, questions, valid source IDs"]
    LOCAL --> QUOTES["Original text passages + page/version references + pins"]
    AI --> QUOTES
    QUOTES --> BRIEF["Reviewable brief; preserve personal questions/notes"]
    BRIEF --> SOURCE["Open original evidence"]
    BRIEF --> PDF["Native paginated PDF / browser print or Save as PDF"]
    MEMORY -->|"Source changes"| STALE["Mark prior briefs stale; regenerate before export"]
    classDef reva fill:#FAE6E5,stroke:#B84250,color:#342B2C;
    class SYMPTOM,OBSERVATION,IMPORT,EXTRACT,REVIEW,SAVE,MEMORY,ENABLED,SUMMARY,VALID,VISIT,MODE,LOCAL,AI,QUOTES,BRIEF,SOURCE,PDF,STALE reva;
```

Local excerpts quote source wording; authored fictional summaries are labeled separately. Connected summaries/overviews identify the model and require review. Gemini selects only supplied IDs; the client constructs original-source quotes and page references. OCR is reviewable, with explicit uncertainty; perfect extraction is not claimed. Imported unreadable text remains a needs-review record rather than pretending AI processing succeeded.

## Medical profile and symptom entry structure

```mermaid
flowchart TD
    AVATAR["Summary avatar / Medical profile tab"] --> PROFILE["Persistent medical profile"]
    PROFILE --> EDIT["Edit identity, allergies, medications, conditions, procedures, care notes"]
    EDIT --> PATIENT["PatientProfile in AppSnapshot"]
    PROFILE --> SETTINGS["Gear → service and app Settings"]
    LOG["Summary Log symptoms / Records add menu"] --> FORM["Required observation and time; optional severity and detail"]
    FORM --> ENTRY["SymptomEntry + self-reported MedicalRecord"]
    ENTRY --> RECORDS["Searchable Records / Symptoms filter / edit / delete"]
    RECORDS --> PREP["Relevant source selection and exact quotes for visit briefs"]
    PATIENT --> JSON["Local atomic snapshot / explicit server push and pull"]
    ENTRY --> JSON
    ALL["Recent records footer: View all records"] --> RECORDS
    classDef reva fill:#FBF7F5,stroke:#B84250,color:#342B2C;
    class AVATAR,PROFILE,EDIT,PATIENT,SETTINGS,LOG,FORM,ENTRY,RECORDS,PREP,JSON,ALL reva;
```

The medical profile is editable quick-reference data, separate from historical source documents. Optional `surgeriesAndImplants` and `careNotes` fields preserve earlier snapshots. The preparation contract currently uses records, so profile edits do not silently rewrite evidence. User symptom entries contain their structured observation and exact labelled source text; edits preserve identity and creation time while the usual source versioning marks prior briefs stale. Full ISO occurrence time and time zone are preserved, and the record list uses the observation's local calendar day.

Both clients now use exact blush ivory `#FBF7F5`, white outlined cards, and heart-red `#B84250` actions. Small labels on petal use deep red `#8C2F3B`. The [browser verification](verification/web-client.md) records the current responsive pass. The [earlier native follow-up](verification/profile-symptoms.md) preserves historical teal-palette evidence.

## Booking: simulation and configured calls

```mermaid
flowchart TD
    VISIT["Existing visit"] --> REVIEW["Review clinic, number, reason, window and constraints"]
    REVIEW --> MODE{"User chooses flow"}
    MODE -->|"Simulation"| DEMO["Queued → simulated call → proposal / needs-input / failure"]
    DEMO --> CONFIRM["Confirm once; update existing local visit"]
    MODE -->|"Real call, configured"| CONSENT["Explicit sharing/call consent and final review"]
    CONSENT --> API["POST /v1/booking/call / stable requestID"]
    API --> INTENT["Persist owner/request intent before dialing"]
    INTENT --> CALL["ElevenLabs agent + imported Twilio number"]
    CALL --> RECEIPT["Persist conversation ID or uncertain outcome"]
    RECEIPT --> POLL["User checks status / GET call by requestID"]
    POLL --> TRANSCRIPT["Review conversation status and bounded transcript"]
    TRANSCRIPT --> EDIT["Manually update visit only after clinic confirmation"]
    INTENT --> REPLAY["Repeated or uncertain request never automatically redials"]
    classDef reva fill:#FAE6E5,stroke:#B84250,color:#342B2C;
    class VISIT,REVIEW,MODE,DEMO,CONFIRM,CONSENT,API,INTENT,CALL,RECEIPT,POLL,TRANSCRIPT,EDIT,REPLAY reva;
```

Calling requires private server tokens, ElevenLabs key/agent/phone-number IDs, `REVA_ENABLE_LIVE_CALLS=true`, and explicit per-request consent. The server passes the reviewed patient/clinic/scheduling variables to the configured agent. It requests provider call recording disabled. Conversation completion is not treated as an appointment confirmation. Uncertain calls need inspection in ElevenLabs before authorizing any new request.

Call receipts live in a persistent server directory even in PostgreSQL mode. A single-writer lock and durable intent protect against duplicate attempts across concurrency and process restarts; keep that directory across deployments. Snapshot deletion does not remove call receipts.

## Recording → transcript → future memory

```mermaid
flowchart TD
    VISIT["Visit"] --> CONSENT["Recording consent + microphone permission"]
    CONSENT --> AUDIO["Native AVFoundation / browser MediaRecorder; pause / finish / saved original"]
    AUDIO --> PLAY["Playback from original saved file"]
    AUDIO --> REQUEST["Explicit transcribe action when configured"]
    REQUEST --> SERVER["Raw audio to Swift API; max16MiB"]
    SERVER --> WHISPER["Whisper1 multipart request;90s server bound"]
    WHISPER --> SEGMENTS["Validated relative offsets + generic speaker + text"]
    SAMPLE["Separate fictional transcript / no matching audio"] --> SEGMENTS
    SEGMENTS --> EDIT["Correct words; retain timestamps, speakers and separate notes"]
    EDIT --> MEMORY["Stable saved-memory record linked to originating transcript"]
    MEMORY --> FUTURE["Search and future pre-visit source selection"]
    classDef reva fill:#FAE6E5,stroke:#B84250,color:#342B2C;
    class VISIT,CONSENT,AUDIO,PLAY,REQUEST,SERVER,WHISPER,SEGMENTS,SAMPLE,EDIT,MEMORY,FUTURE reva;
```

New audio never receives the sample transcript. Recording pauses when the app leaves the foreground. Existing saved memory updates under its stable ID, while corrections retain source identity and separate notes. Browser media uses a secure context (HTTPS or localhost), capability checks, consent and original codec metadata; WebM/Ogg are accepted by the Swift transport, while playback depends on the receiving device. Physical capture/signing and Safari/Firefox hardware validation remain manual checks; sample and adapter tests provide the deterministic demo.

## Data and ownership boundaries

| Storage | What it holds | Consistency boundary |
| --- | --- | --- |
| iPhone App Support | Medical profile, records including structured symptom entries, visits/reports, bookings, recordings/transcripts; original document/audio files | Atomic snapshot plus one backup; originals are separately written |
| Browser IndexedDB | Native-compatible snapshot, local revision, original document/audio Blobs | Atomic snapshot/CAS and downloaded-original transaction; quota errors visible; no silent reset |
| Local Swift server | Owner-scoped snapshot/revision and bounded attachments | Single writer, atomic owner-file replacement |
| Tiger PostgreSQL | `reva_owner_state` JSONB, `reva_attachments` BYTEA, `reva_mutations` audit | Owner row lock and transactional mutation; parameter binding and verified TLS |
| Server call-receipt directory | Reviewed request, durable intent, conversation ID/status | Owner/request identity, file sync/rename, process lock; retained independently of snapshots |
| Provider services | Only content explicitly submitted for that operation | External account policies and credentials; no automatic account provisioning |

Server snapshot push uses a base revision. Conflict resolution is explicit. Attachment transfers and snapshot commits are separate operations; a failed sync can leave already-copied files, so this MVP does not claim atomic rollback across both. Root `.env` stays untracked. Client access tokens remain in memory for the session; provider keys never enter either client. Browser originals are SHA256-checked before fixture fallback; source IDs, page/version citations and all three demo report hashes match the native engine. See the [compatibility limits](../apps/web/src/core/COMPATIBILITY.md).

## Three-person development map

```mermaid
flowchart LR
    P1["Person1 / records, profile and preparation"] --> R["Native Records + Preparation / browser records + profile + visit brief"]
    P2["Person2 / booking and visit memory"] --> V["Native Visits / browser booking + recordings + capture"]
    P3["Person3 / server and providers"] --> S["Server / SQL / provider adapters / native and browser API transport"]
    CAP["Integration captain"] --> SHARED["Shared DTOs / stores / theme and shell / package and project generators"]
    R --> CONTRACT["Versioned wire contract and coordinated shared edits"]
    V --> CONTRACT
    S --> CONTRACT
    SHARED --> CONTRACT
    classDef reva fill:#FAE6E5,stroke:#B84250,color:#342B2C;
    class P1,P2,P3,R,V,S,CAP,SHARED,CONTRACT reva;
```

The [team guide](team-workflow.md) assigns exact files, worktree commands and starter tasks. Feature modules remain one Swift target to keep the MVP simple; separation is by owned folders and focused state extensions. Shared model/wire changes and Xcode project regeneration have one integration owner. Screens/editors now occupy separate files; `BookingEngine` is separate from `ReportEngine`, and provider wire values live in `ProviderContracts`. Every production Swift file and browser source block has a leading responsibility contract and named logical sections, checked by `scripts/check_code_structure.py`; see the [coding standard and block diagram](coding-standard.md).

## Ready now and manual next steps

The native build, local journeys, provider request/response mocks, real local-server auth/persistence checks and native provider-fixture UI have passed. The [verification sheet](verification/README.md) records exact counts and limitations. Before using live integrations, configure private tokens, keys/model access, the ElevenLabs agent and imported Twilio number, a persistent server directory, HTTPS hosting for a physical phone, and Tiger credentials if selecting PostgreSQL; then run a credentialed smoke check with synthetic data. No such live activation was performed here.

The browser extension is implemented and verified locally. MyChart import, custom password encryption, production medical-data deployment and extensive post-MVP polish remain outside this deadline. Checkpoint history and the manual feedback workflow are preserved for the next revisions.
