# Reva Swift API

The runnable prototype server provides owner-scoped state sync and source/audio attachment storage. It uses Vapor and PostgresNIO with a checked-in dependency lockfile. Local mode works without credentials; Tiger Data/PostgreSQL configuration and live connectivity are deferred.

## Run locally

From the repository root, with Xcode selected:

```sh
cd server
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -j 6
swift run --skip-build RevaAPI
```

The default listener is `http://127.0.0.1:8080`. The deliberately public local demo token is `reva-local-demo-token`; it maps only to `demo-user`. State persists under `server/.local-data` when launched from `server/`. Use fictional documents only. Set `REVA_DATA_DIRECTORY` to an absolute path for a stable location independent of working directory. Exactly one local server/store can hold that directory’s writer lock.

```sh
curl http://127.0.0.1:8080/health
curl -H 'Authorization: Bearer reva-local-demo-token' http://127.0.0.1:8080/v1/state
```

The first state read returns 404 and `X-State-Revision: 0`. Push the app’s snapshot using revision zero. The iOS simulator can use localhost; a physical iPhone requires an explicitly configured reachable host and non-demo token mapping. Configure the listener through `REVA_HOST`/`REVA_PORT`; Vapor CLI binding overrides are rejected. The server itself serves HTTP, so any non-loopback deployment needs a separately configured HTTPS boundary. No deployment is included.

The root `.env` is delivered empty. The Swift API reads its environment only. The optional root launcher, `python3 scripts/run_server.py --build`, safely loads settings from root `.env` when you manually add them later; exported environment values take precedence and empty placeholders are skipped. No shell expansion is performed. [`.env.example`](.env.example) is documentation, not active configuration. `REVA_STORAGE` defaults to `local`; unknown values, malformed values, a supplied `DATABASE_URL` in local mode, or missing PostgreSQL credentials are startup errors.

## HTTP contract

All `/v1` endpoints require `Authorization: Bearer <token>`. Configure tokens with `REVA_TOKENS`, a JSON object mapping random tokens of 24–256 visible ASCII characters to safe server owner IDs. Request snapshot `profile.id` or other owner-looking fields have no authority. There is no public user registration or real authentication provider in this prototype. Token rotation and secure device credential provisioning are later work.

| Method / path | Request | Successful response |
| --- | --- | --- |
| `GET /health` | Public | `{status:"ok",storage:"local"\|"postgres",isDemo:Bool}` |
| `GET /v1/state` | Bearer token | `{revision:Int,snapshot:Object}` |
| `PUT /v1/state` | JSON `{baseRevision:Int,snapshot:Object}` | `{revision:Int}` with incremented revision |
| `DELETE /v1/state` | Bearer token | `{revision:Int}` after clearing snapshot and all owner attachments |
| `PUT /v1/attachments/{id}` | Raw bytes, `Content-Type`, `X-Filename` | 204 |
| `GET /v1/attachments/{id}` | Bearer token | Exact bytes, `Content-Type`, `X-Filename`, attachment disposition |
| `DELETE /v1/attachments/{id}` | Bearer token | 204; absent attachment deletion is idempotent |

Every response uses `Cache-Control: no-store`. Errors use JSON `{error:true,reason:String}`: 400 invalid payload/path, 401 authentication, 404 absent content, 409 stale revision, 413 size/quota, 415 unsupported media, 500 storage unavailable. Missing state and 409 include `X-State-Revision`. Health probes the selected storage adapter and reports failure without changing modes.

`snapshot` requires `schemaVersion:1`, a nonempty profile object, and records/visits/bookings/recordings arrays of objects. It preserves additional fields; the app owns full domain validation and relationship correctness. State request body maximum is 4 MiB, array maximum 5000 each, nesting maximum 32. Server revision is independent of record/report domain versions.

Attachments use IDs containing only letters, digits, hyphens and underscores, length 1–80. `X-Filename` is a flat ASCII name (1–180 bytes) with letters, digits, spaces, dots, hyphens, underscores or parentheses; no leading dot, surrounding spaces, slash or control characters. The filename is metadata only and never becomes a filesystem path. MIME types: PDF, plain text, PNG, JPEG, HEIC/HEIF, common M4A/MP4/MP3/WAV audio and octet-stream. MIME metadata is validated against this list, but bytes are preserved without pretending to scan or verify the file format. The native import adapter validates actual import formats. Each attachment is nonempty and at most 16 MiB; each owner has at most 128 attachments totaling 64 MiB. Upload replacement at an existing ID counts only the new bytes.

State writes use compare-and-swap. A repeat write with the old revision produces 409; fetch/review before retrying and never blindly overwrite. Attachment PUT has replacement semantics by stable ID. DELETE state preserves a monotonic tombstone: after revision 1 is deleted, missing GET returns revision 2, and the next PUT must use 2. Repeated DELETE on an empty owner does not increase the revision. This prevents pre-delete stale clients restoring the snapshot. DELETE attachment does not change the state revision or rewrite snapshot references; the client must update its snapshot coherently. Upload sources before the referencing snapshot; cleanup after a failed sync is an explicit client action. Source upload and snapshot PUT are separate transactions.

## Tiger Data / PostgreSQL setup

1. Manually provision a dedicated PostgreSQL database in Tiger Data and obtain its endpoint/credentials. No cloud resource is provisioned here.
2. Export `REVA_STORAGE=postgres`, `DATABASE_URL` and `REVA_TOKENS`. URL format: `postgres://user:password@host:5432/database?sslmode=verify-full`. Percent-encode reserved characters in credentials. Only the `sslmode` URL option is accepted.
3. The default requires TLS with normal system trust and hostname verification. `sslmode=require` also retains full verification; it does not turn off certificate checks. Install any legitimately required CA through the platform’s normal trust mechanism. Never disable validation for a hosted database.
4. Start the API. Startup runs [migration 001](Sources/RevaServer/Migrations/001_snapshot.sql) in a transaction under a PostgreSQL advisory lock and records schema version 1. The configured DB role needs create-table/index and read/write permissions for these tables. Later least-privilege migration/runtime role separation is not implemented. Unsupported newer schema versions fail startup.
5. Use the same HTTP API to push the fictional app snapshot and upload source/audio attachments. There is no hidden seed operation, automatic fixture fallback, direct phone-to-database connection, or cloud Storage dependency.

Tables: `reva_owner_state` owns each versioned JSONB snapshot/tombstone, including profile, records/source metadata, summaries, visits/reports/evidence, bookings and recordings/transcripts. `reva_attachments` stores owner-scoped BYTEA originals with a composite primary key and foreign key. `reva_mutations` keeps the last 128 mutation UUIDs/actions/revisions/timestamps per owner, with unique owner/mutation keys and an owner/time index. It holds metadata, not patient text. These mutation IDs are audit identities, not a general client `Idempotency-Key` replay feature. Booking idempotency lives in the persisted app domain; state CAS and stable attachment IDs prevent duplicate aggregate writes/files.

Every state/attachment mutation locks the owner row and commits quota checks, data and audit together. SQL values use PostgresNIO parameter binding. An explicit four-connection pool, 5-second TCP connect timeout, 15-second SQL statement timeout, and 20-second operation/acquisition deadline bound failures. PostgreSQL errors are redacted rather than printing bind parameters or credentials. No fallback occurs on bad configuration, migration failure, connection failure, or runtime failure.

This JSONB/BYTEA aggregate schema deliberately trades normalized querying and large-blob streaming for a coherent bounded hackathon sync contract. Future production work includes identity integration, normalized reporting views/tables, broader relationship validation, TLS hosting, retention/access policy, backups, encryption operations, rate limits, and streaming attachment scale. Those are not claimed implemented.

## Verification

```sh
cd server
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 6
python3 scripts/smoke.py
python3 scripts/check_postgres_failure.py
```

Tests exercise HTTP auth/owner isolation, required JSON/type/path/size checks, stale and concurrent revision writes, exact binary metadata/byte roundtrip, deletions, persistent restart recovery, corrupt-store rejection, writer lock, and fail-closed configuration. `scripts/smoke.py` launches actual local API processes and verifies HTTP persistence across termination/restart using only temporary synthetic data. `scripts/check_postgres_failure.py` checks that an unreachable loopback PostgreSQL configuration exits within 27 seconds, redacts its dummy password, and creates no local fallback files; it does not validate live database operations.

Live PostgreSQL schema/adapter testing is gated and **has not run** without a dedicated database. To run it later, export `REVA_TEST_DATABASE_URL` for a disposable test database, then run `swift test --filter realDatabaseRoundtripAndMigrations`. It applies the schema, writes one random synthetic owner, verifies operations, and removes that owner on success. A failed test may leave that clearly named synthetic owner for inspection; do not point it at a real patient database. For a separately installed loopback test server only, `sslmode=disable` also needs `REVA_ALLOW_INSECURE_LOCAL_POSTGRES=true`. No PostgreSQL or Docker installation is required or performed by this build.

Local persistence serializes a bounded owner document with Base64 attachments, writes a private temporary file, synchronizes it, and atomically renames it into place. Reads validate persisted envelope version; corrupt files fail instead of resetting data. Directory/files use owner-only permissions. Disk work runs on the store actor rather than a Vapor event loop, and writes rewrite the whole owner aggregate. It is a single-process demo store, with a file lock enforcing that constraint; it is not a production database or custom encryption system. Atomic rename handles process interruption; durability across storage hardware/power failure is not promised without filesystem-level backup guarantees.

Implementation API references checked against official sources: [Vapor async testing](https://docs.vapor.codes/advanced/testing/), [Vapor routing/body bounds](https://docs.vapor.codes/basics/routing/), and [PostgresNIO client and parameter binding](https://github.com/vapor/postgres-nio). Resolved versions during verification: Vapor 4.122.1, PostgresNIO 1.33.1, Xcode Swift 6.3.

## Configurable MVP providers

The server includes real Gemini document/preparation, OpenAI Whisper transcription, and ElevenLabs outbound-call adapters. They are disabled until manually configured. This build uses mocked transports to verify provider request/response contracts; no paid provider request or real call was executed during implementation. `GET /v1/providers` requires the normal bearer token and reports `gemini`, `transcription`, `booking` objects with `configured` and `model`, plus `liveCallsEnabled`. These flags describe server settings, not a successful credentialed connection probe.

Start with `python3 scripts/run_server.py --build` from the repository root. When ready for a credentialed manual check, supply your own settings through exported environment variables or root `.env`, following the commented examples. Set a private `REVA_TOKENS` JSON mapping and use its token in the iPhone's server settings. Provider keys alone cannot activate paid services for the deliberately public `reva-local-demo-token`. Keys and provider agent/phone identifiers are never returned to the phone or included in provider failure messages.

| Feature | Required server settings | Authenticated route |
| --- | --- | --- |
| Document summary / visit preparation | `GEMINI_API_KEY`; optional `GEMINI_MODEL` | `POST /v1/ai/summarize`, `POST /v1/ai/prepare` |
| Timestamped audio transcription | `OPENAI_API_KEY`; `OPENAI_TRANSCRIPTION_MODEL=whisper-1` | `POST /v1/audio/transcribe` |
| Outbound appointment inquiry | `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `ELEVENLABS_PHONE_NUMBER_ID`, `REVA_ENABLE_LIVE_CALLS=true` | `POST /v1/booking/call`; `GET /v1/booking/call/{requestID}` |

Gemini uses the Google AI Studio/API key flow and the fixed HTTPS `generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` endpoint. The supported stable default is `gemini-2.5-flash`; a manually chosen Gemini model ID can override it. Requests ask for structured JSON using `responseMimeType`/`responseJsonSchema`, place source content in a separate untrusted data message, and provide no tools. The summary request is `{recordID,title,text}` and returns `{summary,model}`. Preparation accepts `{visit:{id,type,concern,goal,questions},records:[{id,title,date,text,summary,version}]}` and returns `{overview,questions,selectedRecordIDs,model}`. Source IDs returned by the model must be unique members of the supplied candidates. The server rejects empty summaries, unknown IDs, malformed JSON, blocked/truncated candidates and unexpected output fields. The app constructs its original-source citations; model text supplies no page numbers or source quotes.

Gemini limits: 256 KiB summary request, 1 MiB preparation request, 120000 UTF-8 bytes per source, 100 records and 500000 combined source/summary bytes for preparation, 20 questions, and bounded generated text. Outbound requests have a 40-second request / 45-second resource timeout and no automatic retries or redirects. Responses are limited to 1 MiB (streamed and capped while reading on the tested macOS runtime; checked after collection on FoundationNetworking platforms). A missing setup or provider failure returns safe HTTP 503 with no silent local fallback. Invalid input fails before any provider request. The app preserves the existing local state and can explicitly use its local workflow.

Whisper accepts original raw audio up to 16 MiB with supported audio MIME and safe `X-Filename` metadata. Only `whisper-1` is supported for the MVP `verbose_json` segment-timestamp contract. Returned segment times are relative to the uploaded audio; the generic speaker label does not claim diarization. Sample text-only transcripts are not submitted as captured audio. Configure the OpenAI account/key manually before a credentialed transcription check.

For ElevenLabs, configure your conversational agent and import the outbound Twilio phone number through ElevenLabs, then use its agent ID and imported phone-number ID. The server does not provision those resources. Calls need both the environment flag and explicit `consent:true`, an E.164 destination, and the request's clinic/patient/appointment constraints. A persisted owner/request receipt prevents duplicate attempts, including uncertain calls after a restart; polling returns provider status/transcript for user review. No provider completion automatically confirms an appointment. Keep the server data directory on persistent storage to retain call receipts, including when state snapshots use PostgreSQL. Call receipt/reset behavior is implemented in the voice module and covered by its mocked tests.

Configure the ElevenLabs agent prompt to consume the supplied dynamic variables `request_id`, `clinic_name`, `patient_name`, `appointment_reason`, `earliest`, `latest`, `time_zone`, and `preferences`. The adapter supplies those variables and requests call recording disabled; it does not override the configured agent prompt. Status values describe the conversation (`initiated`, `in-progress`, `processing`, `done`, `failed`, or uncertain), not an appointment confirmation. Receipts remain under `<REVA_DATA_DIRECTORY>/voice-call-receipts` even when a snapshot is deleted. Preserve them across redeploys and do not delete an uncertain receipt to force a retry.

Official Gemini references checked September 12, 2026: [stable Flash model and structured-output support](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash), [GenerateContent REST schema](https://ai.google.dev/api/generate-content), and [structured output guidance](https://ai.google.dev/gemini-api/docs/generate-content/structured-output). Model/account availability is ultimately verified during the user's later credentialed smoke check.

Provider verification: from `server/`, run `swift test -j 6 --filter GeminiProviderTests` for eight mocked Gemini/config/status tests; the regular server suite also includes voice provider tests. From the repository root, `python3 scripts/check_provider_api.py` launches the compiled API on a temporary loopback port after removing inherited provider/Reva/database settings. It verifies the real status shape, six route authentication boundaries and four safe unconfigured 503 responses, then removes its temporary server/data. That real-HTTP smoke and all eight Gemini tests passed during implementation. These checks never require or exercise live provider keys.

Combined backend verification on September 12: `swift test -j 6` passed 29 local/mocked tests; the single live PostgreSQL integration test was skipped without credentials (30 registered tests across four suites). This includes Gemini validation, Whisper multipart/timestamps, and durable outbound-call replay/uncertainty behavior. Live provider/account checks remain manual.
