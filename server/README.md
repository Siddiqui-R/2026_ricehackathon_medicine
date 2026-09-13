# Reva Swift API

The runnable prototype server provides owner-scoped state sync, source/audio attachment storage, and real accounts: email/password sign-up and log-in with bcrypt password hashes and opaque hashed session tokens. It uses Vapor and PostgresNIO with a checked-in dependency lockfile. Local mode works without credentials; PostgreSQL on Tiger Cloud persists every account's data when `REVA_STORAGE=postgres`.

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

Accounts also work locally: `POST /v1/auth/signup` returns a session token that authenticates every `/v1` route with the new user’s ID as the owner (see [Accounts and sessions](#accounts-and-sessions)). Users and session hashes live in `.accounts.json` beside the owner files. Earlier `accounts.json` registries are migrated after shape validation; an existing static owner named `accounts` keeps its separate document.

```sh
curl -X POST http://127.0.0.1:8080/v1/auth/signup -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"a-long-passphrase","name":"Your Name"}'
```

The first state read returns 404 and `X-State-Revision: 0`. Push the app’s snapshot using revision zero. The iOS simulator can use localhost; a physical iPhone requires an explicitly configured reachable host and non-demo token mapping. Configure the listener through `REVA_HOST`/`REVA_PORT`; Vapor CLI binding overrides are rejected. The server itself serves HTTP, so any non-loopback deployment needs a separately configured HTTPS boundary. No deployment is included.

The root `.env` is delivered empty. The Swift API reads its environment only. The optional root launcher, `python3 scripts/run_server.py --build`, safely loads settings from root `.env` when you manually add them later; exported environment values take precedence and empty placeholders are skipped. No shell expansion is performed. [`.env.example`](.env.example) is documentation, not active configuration. `REVA_STORAGE` defaults to `local`; unknown values, malformed values, a supplied `DATABASE_URL` in local mode, or missing PostgreSQL credentials are startup errors.

## HTTP contract

All `/v1` endpoints require `Authorization: Bearer <token>`; the bearer is either a static workspace token or an account session token. Configure static tokens with `REVA_TOKENS`, a JSON object mapping random tokens of 24–256 visible ASCII characters to safe server owner IDs. Request snapshot `profile.id` or other owner-looking fields have no authority. Session tokens are issued by the `/v1/auth` routes below and map to the account’s user ID as the owner.

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

`snapshot` requires `schemaVersion:1`, a nonempty profile object, and records/visits/bookings/recordings arrays of objects. The bookings array is retained only for compatibility with historical snapshots; no booking/calling endpoint uses it. It preserves additional fields; the app owns full domain validation and relationship correctness. State request body maximum is 4 MiB, array maximum 5000 each, nesting maximum 32. Server revision is independent of record/report domain versions.

Attachments use IDs containing only letters, digits, hyphens and underscores, length 1–80. `X-Filename` is a flat ASCII name (1–180 bytes) with letters, digits, spaces, dots, hyphens, underscores or parentheses; no leading dot, surrounding spaces, slash or control characters. The filename is metadata only and never becomes a filesystem path. MIME types: PDF, plain text, PNG, JPEG, HEIC/HEIF, common M4A/MP4/MP3/WAV audio and octet-stream. MIME metadata is validated against this list, but bytes are preserved without pretending to scan or verify the file format. The native import adapter validates actual import formats. Each attachment is nonempty and at most 16 MiB; each owner has at most 128 attachments totaling 64 MiB. Upload replacement at an existing ID counts only the new bytes.

## Accounts and sessions

| Variable | Values | Meaning |
| --- | --- | --- |
| `REVA_ACCOUNTS` | `enabled` (default), `disabled` | `disabled` removes the `/v1/auth/*` routes (404) and makes the bearer middleware accept static tokens only. |
| `REVA_SIGNUP` | `open` (default), `closed` | `closed` answers sign-up with 403 `Sign-up is closed on this server.`; log-in still works. |
| `REVA_SESSION_DAYS` | 1–365, default 30 | Session lifetime from issue time. |
| `REVA_ALLOWED_ORIGINS` | comma-separated exact origins | Enables CORS for those origins only: `https://host[:port]`, or `http://127.0.0.1[:port]` / `http://localhost[:port]`. Never `*`; invalid entries fail startup. |

Identity rule: PostgreSQL mode or a non-loopback listener requires `REVA_TOKENS` **or** `REVA_ACCOUNTS=enabled`. Without `REVA_TOKENS` there are no static tokens and `isDemo` is false, so configured paid providers are available to signed-in accounts. The public demo token exists only for local storage on a loopback listener without `REVA_TOKENS`; accounts also work in that mode, but paid providers stay off.

Public routes (no bearer) require `Content-Type: application/json` and bodies of at most 16 KiB:

| Method / path | Request | Successful response |
| --- | --- | --- |
| `POST /v1/auth/signup` | `{email,password,name}` | 201 `{token:"rs_…",expiresAt:ISO-8601,user:{id,email,name,createdAt}}`; 400 policy failure naming the field, 403 sign-up closed, 409 `An account with this email already exists.` |
| `POST /v1/auth/login` | `{email,password}` | 200 with the same envelope; 401 `Email or password is incorrect.` for unknown email and wrong password alike; 429 with `Retry-After` after 8 failures for one email within 15 minutes |

Authenticated routes (session or static token):

| Method / path | Request | Successful response |
| --- | --- | --- |
| `GET /v1/auth/session` | Bearer | `{kind:"account"\|"token",owner,user\|null,session:{id,createdAt,expiresAt,lastUsedAt}\|null}` |
| `POST /v1/auth/logout` | Bearer session | 204; revokes the presenting session |
| `POST /v1/auth/logout-all` | Bearer session | 204; revokes every session of the user |
| `PUT /v1/auth/password` | `{currentPassword,newPassword}` | 204; revokes every *other* session; 401 wrong current password, 400 policy failure |
| `DELETE /v1/auth/account` | `{password}` | 204; hard-deletes the user, all sessions, and the owner’s snapshot, attachments, and audit rows |

Static tokens receive 400 `Static workspace tokens cannot be logged out.` on the four mutation routes.

Policy: the user ID is `u_` + 24 hex characters and is the owner ID for `/v1/state` and `/v1/attachments`. Email is trimmed, lowercased, 3–254 characters with a single `@` and dotted domain, stored normalized and unique. Name is trimmed, 1–80 characters, no control characters. Passwords are used verbatim: at least 8 Unicode characters with 1 capital letter (A–Z), 1 number (0–9), and 1 punctuation/symbol character, capped at 72 UTF-8 bytes (the bcrypt limit), no line breaks, never equal to the email; only bcrypt hashes (cost 12) are stored and hashing runs on the thread pool. Session tokens are `rs_` + 43 base64url characters; the server stores only the SHA-256 hex, checks expiry/revocation on every request, and updates `lastUsedAt` at most once per five minutes. Each user keeps at most 20 live sessions; the 21st revokes the oldest. The log-in throttle is in-memory per process and bounded to 10,000 email keys; an unknown email still runs a bcrypt verification against a dummy hash so timing does not reveal existence.

CORS, when enabled, echoes only an exactly listed origin with `Vary: Origin`, allows GET/PUT/POST/DELETE/OPTIONS and the `Authorization`, `Content-Type`, `X-Filename` headers, exposes `X-State-Revision` and `X-Filename`, answers preflight with 204 and `Access-Control-Max-Age: 600`, and never sets a credentials flag (bearer tokens, not cookies). Any non-loopback deployment still needs a separately configured HTTPS boundary.

State writes use compare-and-swap. A repeat write with the old revision produces 409; fetch/review before retrying and never blindly overwrite. Attachment PUT has replacement semantics by stable ID. DELETE state preserves a monotonic tombstone: after revision 1 is deleted, missing GET returns revision 2, and the next PUT must use 2. Repeated DELETE on an empty owner does not increase the revision. This prevents pre-delete stale clients restoring the snapshot. DELETE attachment does not change the state revision or rewrite snapshot references; the client must update its snapshot coherently. Upload sources before the referencing snapshot; cleanup after a failed sync is an explicit client action. Source upload and snapshot PUT are separate transactions.

## Tiger Data / PostgreSQL setup

1. Manually provision a dedicated PostgreSQL database in Tiger Data and obtain its endpoint/credentials. No cloud resource is provisioned here.
2. Export `REVA_STORAGE=postgres` and `DATABASE_URL`; add `REVA_TOKENS` for static workspace identities, or rely on accounts (`REVA_ACCOUNTS=enabled`, the default). URL format: `postgres://user:password@host:5432/database?sslmode=verify-full`. Percent-encode reserved characters in credentials. Only the `sslmode` URL option is accepted.
3. The default requires TLS with normal system trust and hostname verification. `sslmode=require` also retains full verification; it does not turn off certificate checks. Install any legitimately required CA through the platform’s normal trust mechanism. Never disable validation for a hosted database.
4. Start the API. Startup runs the ordered migrations [001](Sources/RevaServer/Migrations/001_snapshot.sql) and [002](Sources/RevaServer/Migrations/002_accounts.sql) in one transaction under a PostgreSQL advisory lock and records each schema version; every version above the recorded maximum runs in order. The configured DB role needs create-table/index and read/write permissions for these tables. Later least-privilege migration/runtime role separation is not implemented. Unsupported newer schema versions fail startup.
5. Use the same HTTP API to push the fictional app snapshot and upload source/audio attachments. There is no hidden seed operation, automatic fixture fallback, direct phone-to-database connection, or cloud Storage dependency.

Tables: `reva_owner_state` owns each versioned JSONB snapshot/tombstone, including profile, records/source metadata, summaries, visits/reports/evidence, bookings and recordings/transcripts. `reva_attachments` stores owner-scoped BYTEA originals with a composite primary key and foreign key. `reva_mutations` keeps the last 128 mutation UUIDs/actions/revisions/timestamps per owner, with unique owner/mutation keys and an owner/time index. It holds metadata, not patient text. `reva_users` stores normalized unique emails and bcrypt hashes; `reva_sessions` stores SHA-256 token hashes with expiry/revocation and cascades from its user. Deleting an account deletes its `reva_owner_state` row, which cascades to attachments and audit rows. These mutation IDs are audit identities, not a general client `Idempotency-Key` replay feature. Historical bookings remain inert persisted data for snapshot compatibility. State CAS and stable attachment IDs prevent duplicate aggregate writes/files.

Every state/attachment mutation locks the owner row and commits quota checks, data and audit together. SQL values use PostgresNIO parameter binding. An explicit four-connection pool, 5-second TCP connect timeout, 15-second SQL statement timeout, and 20-second operation/acquisition deadline bound failures. PostgreSQL errors are redacted rather than printing bind parameters or credentials. No fallback occurs on bad configuration, migration failure, connection failure, or runtime failure.

This JSONB/BYTEA aggregate schema deliberately trades normalized querying and large-blob streaming for a coherent bounded hackathon sync contract. Future production work includes identity integration, normalized reporting views/tables, broader relationship validation, TLS hosting, retention/access policy, backups, encryption operations, rate limits, and streaming attachment scale. Those are not claimed implemented.

## Verification

```sh
cd server
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 6
python3 scripts/smoke.py
python3 scripts/check_postgres_failure.py
```

Tests exercise HTTP auth/owner isolation, required JSON/type/path/size checks, stale and concurrent revision writes, exact binary metadata/byte roundtrip, deletions, persistent restart recovery, corrupt-store rejection, writer lock, and fail-closed configuration. `AccountTests` (bcrypt cost 4) cover sign-up/log-in envelopes, owner isolation between accounts, case-insensitive duplicate and log-in handling, identical 401 reasons, the 429 throttle with `Retry-After`, session inspection for both bearer kinds, logout/logout-all, password change revoking other sessions, hard account deletion, closed sign-up, disabled accounts, password/email/name policy bounds, the identity and CORS configuration rules, preflight/echo behaviour, session expiry/revocation/touch, local persistence of `.accounts.json` with 0600 permissions, and the 20-session cap with pruning. `scripts/smoke.py` launches actual local API processes and verifies HTTP persistence across termination/restart using only temporary synthetic data. `scripts/check_postgres_failure.py` checks that an unreachable loopback PostgreSQL configuration exits within 27 seconds, redacts its dummy password, and creates no local fallback files; it does not validate live database operations.

Live PostgreSQL schema/adapter testing is gated and **has not run** without a dedicated database. To run it later, export `REVA_TEST_DATABASE_URL` for a disposable test database, then run `swift test --filter PostgresIntegrationTests`. It applies the schema, writes one random synthetic owner and one synthetic user (duplicate email conflict, session lookup/touch/revoke, the 20-session cap, cascading deletion), verifies operations, and removes those rows on success. A failed test may leave that clearly named synthetic owner for inspection; do not point it at a real patient database. For a separately installed loopback test server only, `sslmode=disable` also needs `REVA_ALLOW_INSECURE_LOCAL_POSTGRES=true`. No PostgreSQL or Docker installation is required or performed by this build.

Password replacement and revocation of other sessions commit atomically. Login and sign-up session issuance recheck the verified password hash under the same user lock, so an in-flight request cannot issue a session for a replaced password.

Local persistence serializes a bounded owner document with Base64 attachments, writes a private temporary file, synchronizes it, and atomically renames it into place. `.accounts.json` uses the same commit path with mode 0600, is bounded to 10,000 users and 100,000 session rows, and prunes revoked or expired sessions older than 30 days on write; deleting an account also removes `<owner>.json`. Reads validate persisted envelope version; corrupt files fail instead of resetting data. Directory/files use owner-only permissions. Disk work runs on the store actor rather than a Vapor event loop, and writes rewrite the whole owner aggregate. It is a single-process demo store, with a file lock enforcing that constraint; it is not a production database or custom encryption system. Atomic rename handles process interruption; durability across storage hardware/power failure is not promised without filesystem-level backup guarantees.

Implementation API references checked against official sources: [Vapor async testing](https://docs.vapor.codes/advanced/testing/), [Vapor routing/body bounds](https://docs.vapor.codes/basics/routing/), and [PostgresNIO client and parameter binding](https://github.com/vapor/postgres-nio). Resolved versions during verification: Vapor 4.122.1, PostgresNIO 1.33.1, Xcode Swift 6.3.

## Appointment transcription and source summaries

The server supports Gemini document/appointment-transcript summaries and visit preparation, plus OpenAI Whisper transcription. `GET /v1/providers` requires a bearer token and returns only `gemini` and `transcription`, each with `configured` and `model`. These flags describe server settings, not a successful credentialed connection probe.

Start with `python3 scripts/run_server.py --build` from the repository root. Configure provider keys in the API host's environment. Private workspace tokens or account sessions authenticate provider requests; the deliberately public `reva-local-demo-token` cannot activate paid providers. Provider keys are never returned to clients or included in failure messages.

| Feature | Required server settings | Authenticated route |
| --- | --- | --- |
| Document/transcript summaries, visit preparation and medical profile | `GEMINI_API_KEY`; optional `GEMINI_MODEL=gemini-flash-lite-latest` | `POST /v1/ai/summarize`, `POST /v1/ai/prepare`, `POST /v1/ai/profile` |
| Timestamped appointment audio transcription | `OPENAI_API_KEY`; `OPENAI_TRANSCRIPTION_MODEL=whisper-1` | `POST /v1/audio/transcribe` |

The appointment workflow records audio in the client only after the doctor agrees. The client sends the recording's original audio to Whisper, displays the timestamped transcript for review, and requests a Gemini summary from that exact transcript. A transcript-summary request uses `{recordID: recording.id, title: "Appointment transcript", text: <exact timestamped transcript>}` and returns the existing `{summary,model}` response. Personal notes are not substituted for the transcript or represented as recorded speech. Consent is collected by the recording client; the server does not record audio itself.

The summary prompt grounds appointment output in the stated discussion, instructions and follow-ups. It preserves numbers, negations and uncertainty; it does not infer speaker identities or doctor roles, diagnose, or add new medical advice. Generated output remains for the user to review.

Gemini uses the fixed HTTPS `generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` endpoint. Every analysis operation shares the `gemini-flash-lite-latest` default, which follows Google's latest Flash-Lite release. Missing/blank `GEMINI_MODEL` and the prior shipped `gemini-3.8-flash` / `gemini-3.5-flash-lite` values resolve to this alias automatically; other well-formed explicit model overrides apply to all operations. Set `GEMINI_MODEL=gemini-flash-lite-latest` explicitly when upgrading a deployment previously pinned to any other model. Preparation no longer has a separate hardcoded model, and clients accept attributed responses without requiring one version. Requests use structured JSON (`responseMimeType`/`responseJsonSchema`), keep source content in a separate untrusted-data message, and provide no tools. Preparation accepts `{visit:{id,type,concern,goal,questions},records:[{id,title,date,text,summary,version}]}` and returns `{overview,questions,selectedRecordIDs,model}`. Returned IDs must be unique members of the supplied records. Empty summaries, unknown IDs, malformed JSON, blocked/truncated candidates and extra output fields are rejected. Clients construct original-source citations. [Google model aliases](https://ai.google.dev/gemini-api/docs/models), [Flash-Lite latest identifier](https://ai.google.dev/api/interactions-api).

Gemini limits: 256 KiB summary request, 1 MiB preparation request, 120000 UTF-8 bytes per source, 100 records and 500000 combined source/summary bytes for preparation, 20 questions, and bounded generated text. Requests have a 40-second request / 45-second resource timeout and no automatic retries or redirects. Responses are limited to 1 MiB (streamed and capped on the tested macOS runtime; checked after collection on FoundationNetworking platforms). Permanent request/output failures return 422, provider configuration/access failures 424, quota limits 429 and transient outages 503, without a silent local fallback. Invalid input fails before any provider request.

Whisper accepts original raw audio up to 16 MiB with supported audio MIME and safe `X-Filename` metadata. Only `whisper-1` is supported for the `verbose_json` segment-timestamp contract. Segment times are relative to the uploaded audio; the generic speaker label does not claim speaker identification. Sample text transcripts are not submitted as captured audio.

Outbound calling has been removed. The former `POST /v1/booking/call` and `GET /v1/booking/call/{requestID}` routes return 404, and legacy ElevenLabs/live-call environment settings are ignored. Historical bookings in snapshots and any existing files under `<REVA_DATA_DIRECTORY>/voice-call-receipts` remain untouched. Earlier calling setup documents describe retired behavior and are not current configuration instructions.

Provider verification uses injected mock transports. Run `swift test -j 6 --filter GeminiProviderTests` for discovery, summary/preparation schemas, exact appointment transcript forwarding, retired-route 404s, and ignored obsolete settings. `swift test -j 6 --filter VoiceProviderTests` covers original audio bytes/MIME, timestamp validation, neutral speaker labels, authentication and safe failures. The complete server suite also covers persistence and accounts. These checks make no live provider requests; live PostgreSQL tests remain gated on a dedicated test database.
