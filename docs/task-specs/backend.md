# Backend task specification

Owner: backend contributor. Authorized scope: `server/` and this packet only. Do not modify app, shared contracts, root configuration, or final architecture documentation; do not commit or push. This packet implements the existing implementation contract and completion gates 11, 12, 14, 16, and 17, plus tasks T25–T27/T33.

## Deliverable

Build a Swift/Vapor HTTP service with public health, authenticated snapshot synchronization, and authenticated binary attachment CRUD. Owner identity is derived solely from configured bearer token mappings. The snapshot preserves schema version, fictional/profile state, records, visits/reports, booking requests, and recordings/transcripts together. Unknown profile owner-looking fields never influence storage ownership.

Local mode runs on loopback with an obvious demo token and atomic, bounded per-owner file persistence. PostgreSQL mode requires valid explicit connection and non-demo authentication configuration, connects using verified TLS by default, applies an idempotent versioned migration under a database advisory lock, and fails startup on configuration/connection/migration failure. It must never fall back silently. PostgreSQL uses JSONB for snapshots, BYTEA for attachments, owner/revision constraints, timestamps, mutation IDs, and transactional audit metadata. No database, Docker, cloud resource, or provider is installed or provisioned.

## Wire behavior and safety

- `GET /health`: status, storage mode, and local-demo flag only.
- `GET /v1/state`: revision and JSON snapshot; missing snapshot is 404.
- `PUT /v1/state`: bounded JSON `{baseRevision,snapshot}`; validated top-level shape; successful writes increment revision, conflicting stale writes return 409.
- `DELETE /v1/state`: delete snapshot and owner attachments; preserve a revision tombstone to prevent stale writes resurrecting deleted state. Return the new revision; missing GET supplies `X-State-Revision` so resynchronization can use the tombstone revision. First-ever revision is zero.
- `PUT/GET/DELETE /v1/attachments/{id}`: owner-scoped bytes and MIME type/flat ASCII filename, with strict attachment ID/path, content type, individual size and owner-total bounds.
- No patient payload or bearer token logging. Errors use predictable HTTP status and safe reason text. Local store atomic writes fail without changing acknowledged state. Corrupt persisted state fails visibly rather than being replaced by a fixture.

## Implementation boundaries

Use modular configuration, JSON wire models/validation, bearer middleware, routes, store protocol, local adapter, PostgreSQL adapter and SQL migration resource. Use official Vapor and vapor/PostgresNIO Swift packages with a pinned resolved dependency graph. Prefer async modern PostgresClient APIs. Validate unfamiliar APIs against official docs/source, then compiler evidence. The schema is intentionally a coherent aggregate for the hackathon, not a claim of implemented production normalized domain tables.

## Verification plan

Compile with the installed Xcode Swift toolchain. Test unauthorized rejection, distinct-token owner isolation, stale and concurrent revisions, required shape/type/size validation, safe attachment paths, exact bytes/content metadata roundtrip, attachment deletion, state deletion/tombstone semantics, restart durability, corrupt-store behavior, and explicit configuration failure. Add a separately gated PostgreSQL integration test requiring a dedicated test database; record it as not run without credentials. Exercise a live local HTTP smoke route and record exact commands. SQL migration structure must be inspected even without a live Tiger connection.

## Handoff

Provide server setup/run/API documentation, configuration examples separate from the untouched empty root `.env`, tests and command evidence, limits and tradeoffs, and integration information for the parent’s URLSession client. Parent owns manual review, shared docs updates, app integration, commits, and final publication. This packet will be updated with actual verification and material deviations before handoff.

## Completed implementation and verification — September 12, 2026

- Implemented `server/Package.swift`, modular configuration/models/validation/auth/routes, local atomic file adapter, PostgreSQL adapter, bounded database operation wrapper, executable entry point, embedded versioned SQL migration, server setup/API README, inactive `.env.example`, request/store tests, gated PostgreSQL tests, and reproducible real-HTTP/startup-failure scripts.
- Primary accepted the tombstone contract explicitly: missing GET state returns `X-State-Revision`, and DELETE state returns the new revision and clears all owner attachments. Primary owns the URLSession header handling and explicit manual push/pull UI.
- Official APIs checked against Vapor documentation and PostgresNIO source/docs. Resolved and compiled dependencies: Vapor 4.122.1 and PostgresNIO 1.33.1; exact transitive lockfile is `server/Package.resolved`. Xcode toolchain reports Swift 6.3.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift package resolve` succeeded. Initial sandbox attempt could not write the compiler’s module cache; the approved escalated retry fetched only official Swift package dependencies.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift build -j 6` succeeded (initial full build 53.52 seconds).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test -j 6` succeeded after final source changes. Eight local tests passed; one live PostgreSQL test was explicitly skipped because `REVA_TEST_DATABASE_URL` is unset (Swift Testing reports nine registered tests). Final incremental build 3.54 seconds; tests 0.147 seconds. Logs during work: `/tmp/reva-server-build.log`, `/tmp/reva-server-tests.log`.
- `python3 scripts/smoke.py` succeeded: actual HTTP auth, server-derived owner isolation, stale revisions, exact binary bytes, process termination/restart persistence, state/attachment deletion, tombstones and post-deletion revision write. The script uses temporary synthetic data and stops its child server.
- Explicit unreachable loopback PostgreSQL startup check succeeded: exit status 1 after 21.0 seconds, dummy password absent from output, no fallback files created. The reproducible command is `python3 scripts/check_postgres_failure.py`.
- Source-reviewed SQL: required JSONB domains/shape/version; owner and attachment composite keys; BYTEA and size constraints; foreign keys; mutation uniqueness and owner/time index; owner row locks covering compare-and-swap/quota/data/audit; migration advisory lock and transaction; parameter-bound request values. No PostgreSQL executable/parser is installed and no live Tiger or local PostgreSQL schema execution has occurred. The dedicated integration test compiles and remains a manual follow-up with credentials.
- Verified root `.env` remains exactly 0 bytes and is Git-ignored. The backend never reads it. Build artifacts and local data are ignored through `server/.gitignore`. No app/shared-doc changes, commit, push, database installation, provider API call, cloud resource, or final architecture file was made by this contributor.

## Material implementation decisions

Local persistence uses a synchronized private temporary file and same-directory atomic rename; a nonblocking OS file lock enforces one store/process per directory. Actor isolation serializes local state revision checks. A corrupt owner file fails visibly and is not overwritten. No fallible permission change occurs after the rename commit point. PostgreSQL uses a four-connection pool, 5-second TCP connect timeout, 15-second statement timeout, and 20-second connection-acquisition/operation deadline; startup errors exit cleanly with redacted diagnostics. CLI listener overrides are disabled so Vapor cannot bypass loopback-only demo-token configuration.

Limits are 4 MiB state request, 16 MiB per attachment, 64 MiB/128 attachments per owner, 5000 objects per domain array, depth 32. Filenames are flat ASCII metadata, IDs use safe ASCII characters. Full domain relationships remain app-validated. Source-byte type metadata is checked against an allowlist, without claiming server-side content extraction, malware scanning, or verified media decoding.

The hackathon aggregate design intentionally rewrites a bounded local owner file, persists coherent domains as JSONB, and stores source/audio as BYTEA. Attachment upload and snapshot write are separate API transactions. No general client idempotency replay cache or normalized production domain tables are claimed: state retries conflict using revisions, attachment replacement uses stable IDs, repeat deletes are idempotent, and audit UUIDs provide mutation identity. Production identity/HTTPS hosting, database provisioning, normalized query views and scalable streaming/retention remain deferred setup or future work.
