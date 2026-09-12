# Accounts, sessions, and Tiger persistence — implementation contract v1

Written September 12, 2026 for concurrent implementation. Goal: real sign-up and log-in on the web, bcrypt password hashing on the Swift server, opaque hashed session tokens, and every account's data persisted in PostgreSQL on Tiger Cloud when `REVA_STORAGE=postgres`. The fictional demo at `/demo` is unchanged. Nobody commits; the user reviews and commits.

## 1. Identity model

- Account owner ID = `user_id` = `u_` + 24 lowercase hex characters (12 random bytes). It satisfies `Validation.safeID` and the database regex `^[A-Za-z0-9_-]{1,80}$`, so `/v1/state` and `/v1/attachments` work unchanged with the user ID as the owner.
- Static `REVA_TOKENS` identities keep working unchanged (`kind: "token"`).
- Session token = `rs_` + 43 base64url characters (32 random bytes from `SystemRandomNumberGenerator`), 46 characters total. The server stores only its SHA-256 hex (64 chars). Lookup is by hash; expiry and revocation are checked on every request.
- Session lifetime: `REVA_SESSION_DAYS` (default 30, range 1–365). `lastUsedAt` is updated at most once per 5 minutes.
- At most 20 live sessions per user; creating the 21st revokes the oldest.
- Passwords: 10–72 UTF-8 bytes (bcrypt limit), may not contain `\r`/`\n`, may not equal the email. Used verbatim (no trimming). Stored only as bcrypt hashes, cost 12 by default (`Bcrypt.hash`/`Bcrypt.verify` from Vapor). Hashing runs on `app.threadPool.runIfActive`, never on the event loop. Plaintext is never logged or persisted.
- Email: trimmed, lowercased, 3–254 characters, matches `^[^\s@]+@[^\s@]+\.[^\s@]+$`, no control characters; stored normalized and unique. Name: trimmed, 1–80 characters, no control characters.

## 2. Server configuration additions (`server/Sources/RevaServer/Configuration.swift`)

| Variable | Values | Meaning |
| --- | --- | --- |
| `REVA_ACCOUNTS` | `enabled` (default), `disabled` | `disabled` removes the `/v1/auth/*` routes and makes the bearer middleware accept static tokens only. |
| `REVA_SIGNUP` | `open` (default), `closed` | `closed` makes sign-up answer 403 `Sign-up is closed on this server.`; log-in still works. |
| `REVA_SESSION_DAYS` | 1–365, default 30 | Session lifetime. |
| `REVA_ALLOWED_ORIGINS` | comma-separated exact origins | Enables CORS for those origins only (`https://…`, or `http://127.0.0.1[:port]`/`http://localhost[:port]`). Never `*`. Allowed methods GET, PUT, POST, DELETE, OPTIONS; allowed headers Authorization, Content-Type, X-Filename; exposed headers X-State-Revision, X-Filename; `Vary: Origin`; `Access-Control-Max-Age: 600`; preflight → 204. No credentials flag (bearer tokens, not cookies). Invalid entries fail configuration. |

Identity rule change: PostgreSQL mode or a non-loopback listener now requires `REVA_TOKENS` **or** `REVA_ACCOUNTS=enabled`. Without `REVA_TOKENS`, `tokens` is empty and `isDemo` is false. The public demo token still exists only for local storage on a loopback listener without `REVA_TOKENS` (accounts also work in that mode). `paidAccessAllowed` stays `!isDemo`.

## 3. HTTP API (JSON; `SafeErrors` still adds `Cache-Control: no-store` and the `{ "error": true, "reason": "…" }` error body)

Public routes (no bearer). Request `Content-Type` must be `application/json`; bodies are limited to 16 KiB.

- `POST /v1/auth/signup` `{ "email", "password", "name" }` → **201** `{ "token": "rs_…", "expiresAt": ISO-8601, "user": { "id", "email", "name", "createdAt" } }`. 400 for a policy failure (the reason names the field), 403 when sign-up is closed, 409 `An account with this email already exists.`, 404 when accounts are disabled.
- `POST /v1/auth/login` `{ "email", "password" }` → **200** with the same envelope. 401 `Email or password is incorrect.` for unknown email and wrong password alike; an unknown email still runs `Bcrypt.verify` against a fixed dummy hash so timing does not reveal existence. 429 with `Retry-After` after 8 failures for the same normalized email within 15 minutes (in-memory actor, bounded to 10,000 keys, per process; a successful login clears the counter).

Authenticated routes (bearer: session token or static token):

- `GET /v1/auth/session` → 200 `{ "kind": "account" | "token", "owner": "<owner id>", "user": { … } | null, "session": { "id", "createdAt", "expiresAt", "lastUsedAt" } | null }`.
- `POST /v1/auth/logout` → 204; revokes the presenting session. Static token → 400 `Static workspace tokens cannot be logged out.`
- `POST /v1/auth/logout-all` → 204; revokes every session of the user, including the current one. Static → 400.
- `PUT /v1/auth/password` `{ "currentPassword", "newPassword" }` → 204; verifies the current password, stores the new hash, revokes every *other* session. 401 on a wrong current password, 400 on a policy failure. Static → 400.
- `DELETE /v1/auth/account` `{ "password" }` → 204; verifies the password, then hard-deletes the user, all sessions, and the owner's snapshot, attachments, and audit rows (not a tombstone). Static → 400.

Every existing `/v1/state`, `/v1/attachments/*`, and provider route accepts session tokens exactly like static tokens. The owner is the user ID.

## 4. Storage protocol additions (`Models.swift`, additive)

```swift
public struct UserRecord: Codable, Sendable, Equatable {
    public let id: String; public let email: String; public let name: String
    public let passwordHash: String; public let createdAt: Date; public let passwordUpdatedAt: Date
}
public struct SessionRecord: Codable, Sendable, Equatable {
    public let id: UUID; public let tokenHash: String; public let userID: String; public let label: String
    public let createdAt: Date; public let lastUsedAt: Date; public let expiresAt: Date; public let revokedAt: Date?
}
enum AccountError: Error, Sendable { case emailTaken, userMissing, sessionMissing }
public protocol AccountStore: Sendable {
    func createUser(_ user: UserRecord) async throws                 // AccountError.emailTaken on a duplicate (case-insensitive)
    func user(email: String) async throws -> UserRecord?
    func user(id: String) async throws -> UserRecord?
    func updatePassword(userID: String, hash: String, at: Date) async throws
    func changePassword(userID: String, verifiedPasswordHash: String, newHash: String, keepingSessionID: UUID, at: Date) async throws -> Bool
    func deleteUser(id: String) async throws                         // removes sessions and the owner's state/attachments/audit
    func createSession(_ session: SessionRecord) async throws        // enforces the 20-per-user cap
    func createSession(_ session: SessionRecord, verifiedPasswordHash: String) async throws -> Bool
    func session(tokenHash: String) async throws -> (SessionRecord, UserRecord)?   // nil when revoked or expired
    func touchSession(id: UUID, at: Date) async throws
    func revokeSession(id: UUID) async throws
    func revokeSessions(userID: String, except: UUID?) async throws
}
```

`LocalFileStore` and `PostgresStore` conform. `BoundedAccountStore` wraps the account operations with the same deadline. `configure(_:configuration:store:geminiTransport:)` gains `accounts: (any AccountStore)? = nil` and `passwordCost: Int = 12` (tests use a low cost); nil accounts → no auth routes. `session.label` is the sanitized `User-Agent` (printable ASCII, ≤120 chars, empty when absent).

Middleware: `BearerMiddleware(tokens:accounts:)` first performs the existing constant-time static match; otherwise, when the token has the `rs_` prefix and 46 characters, it hashes it, calls `accounts.session(tokenHash:)`, rejects expired/revoked sessions, touches `lastUsedAt` when older than 5 minutes, and logs `OwnerIdentity(id: user.id, session: session, user: user)`. Static identities carry `session: nil, user: nil`.

## 5. Local file store

`.accounts.json` in the data directory (mode 0600, same temp-file + fsync + rename commit as owner documents): `{ "formatVersion": 1, "users": [UserRecord], "sessions": [SessionRecord] }`. Bounds: 10,000 users, 100,000 session rows; revoked or expired sessions older than 30 days are pruned on write. `deleteUser` also removes `<owner>.json`.

A legacy `accounts.json` is moved to `.accounts.json` only after its shape is validated as an account registry. A static owner named `accounts` keeps its existing owner document. Mixed or malformed legacy files fail closed.

Password changes compare the verified hash and presenting live session, replace the hash, and revoke other sessions in one actor commit or PostgreSQL transaction. Session issuance compares the verified hash under the same user lock, preventing a login verified against an old password from completing after a password change. The HTTP contract stays unchanged.

## 6. PostgreSQL

- The migration runner becomes an ordered list `[(1, "001_snapshot"), (2, "002_accounts")]` applied inside the existing advisory-locked transaction; every version above the recorded maximum runs in order and records its row. A recorded version above the list still fails with `Database schema is newer than this server.`
- `Migrations/002_accounts.sql`:
  - `reva_users(user_id TEXT PRIMARY KEY CHECK (user_id ~ '^[A-Za-z0-9_-]{1,80}$'), email TEXT NOT NULL UNIQUE CHECK (email = lower(email) AND length(email) BETWEEN 3 AND 254), display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 80), password_hash TEXT NOT NULL CHECK (password_hash LIKE '$2%' AND length(password_hash) BETWEEN 59 AND 72), password_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_at TIMESTAMPTZ NOT NULL DEFAULT now())`
  - `reva_sessions(session_id UUID PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'), user_id TEXT NOT NULL REFERENCES reva_users(user_id) ON DELETE CASCADE, label TEXT NOT NULL DEFAULT '' CHECK (length(label) <= 120), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(), expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ)` plus `CREATE INDEX IF NOT EXISTS reva_sessions_user ON reva_sessions(user_id)`.
- Every runtime value is a bound parameter (PostgresNIO string interpolation binds; never build SQL text from input).
- `PostgresIntegrationTests` (gated on `REVA_TEST_DATABASE_URL`) gains: create user, duplicate email conflict, session lookup/touch/revoke, 20-session cap, delete user cascades and removes owner state; it cleans up its own rows. No PostgreSQL exists on this machine, so the gate stays closed locally.

## 7. Web client (`apps/web`)

Pathname routes (the workspace keeps its `#/…` hash routes):

- `/` landing (exists). With a stored, unexpired session the primary action becomes **Open your workspace** → `/app` and a **Log out** text action appears; otherwise Sign up / Log in / View the demo.
- `/signup`, `/login`: real forms replacing `AccountGate`. Fields: name (sign-up only), email, password (minimum 10 characters, show/hide toggle), submit. Inline validation, disabled while submitting, the server's `reason` shown on failure, `autocomplete` set to `email`, `name`, `new-password` / `current-password`. Success stores the session and calls `location.assign('/app')`. Each page links to the other and back to `/`. Same visual language as the landing (`landing.css`).
- `/app`: signed-in workspace = `<RevaProvider store={accountStore}><App /></RevaProvider>` with the store in account mode. No valid session → `location.replace('/login')`. A 401 from the server in account mode → clear the session, show a notice, redirect to `/login`.
- `/demo`: unchanged (demo token, manual sync, fictional data).
- `src/core/session.ts`: `localStorage` key `reva.session.v1` → `{ token, expiresAt, user }`; every read/write wrapped in try/catch; expired = absent; the token never appears in a URL.
- `src/core/auth.ts`: `AuthAPI` (signup, login, logout, logoutAll, session, changePassword, deleteAccount) with the same bounded fetch discipline as `RevaAPI` (timeout, `redirect: 'error'`, `credentials: 'omit'`, `cache: 'no-store'`, bounded body, `APIError` mapping incl. 409/429/403). `apiURL(path)` prefixes `import.meta.env.VITE_REVA_API_ORIGIN` when set; the origin must be `https://…` or a loopback `http://` origin, otherwise startup throws. `RevaAPI` uses the same helper.
- `RevaStore` account mode `new RevaStore(repository, apiFactory, { mode: 'account', token, user })`:
  - The repository database name is `reva-account-<first 16 hex of sha256(userID)>-v1`, separate from the demo database `reva-workspace-v1`.
  - `initialize()`: load local; `checkServer()`; server has a snapshot and local is empty → pull; server empty (404 with a revision) and local empty → commit an **empty personal snapshot** (`profile.id = userID`, `name = user.name`, initials derived from the name, `isDemo: false`, empty lists) and push it; both exist with different revisions → keep local, set `mustPull`, notice “The server copy differs; pull to review it.”
  - Auto-sync: after every successful local commit in account mode, debounce 1.5 s, then `pushToServer()` unless busy or `mustPull`; a failure shows the existing error banner and never discards local data. Originals already uploaded during this session under the same identity (filename + size) are not uploaded again.
  - Settings in account mode: an **Account** card (name, email, session expiry, Log out, Log out everywhere), **Change password** form, **Delete account** with typed confirmation; no token field; providers card and manual push/pull stay; “Restore fictional demo” hidden.
  - `App` header in account mode: a Log out item in the sidebar and mobile menu.
- Tests (vitest): `auth.ts` request shapes and error mapping; `session.ts` expiry; store account-mode initialize (empty server → empty personal snapshot pushed; server data → pulled; 401 → session cleared) via `MemoryRepository`/`transport` fixtures; `serve.test.mjs` covers `/app`.
- `scripts/serve.mjs` and `vercel.json` add the `/app` route. `serve.mjs` remains a loopback-only local proxy.

## 8. Tiger Cloud provisioning and deployment

- `scripts/tiger_provision.py` (standard library only): Tiger Cloud REST API, base `https://console.cloud.tigerdata.com/public/api/v1`, HTTP Basic auth with `TIGERDATA_ACCESS_KEY` / `TIGERDATA_SECRET_KEY`, project `TIGERDATA_PROJECT_ID`. `POST /projects/{project_id}/services` with body `{"name": <name>, "cpu_millis": "shared", "memory_gbs": "shared", "region_code": "us-east-1"}` creates the **free shared service** (free services exist only in `us-east-1`; omit `addons` for plain PostgreSQL). Any non-shared `cpu_millis`/`memory_gbs` requires `--allow-paid`; the default never creates a paid service. Poll `GET /projects/{project_id}/services/{service_id}` until `status` is `READY` (statuses seen: `QUEUED`, `CONFIGURING`, `READY`; 15-minute limit). The create response carries `endpoint.host`, `endpoint.port`, `initial_password`, `service_type`. Print `DATABASE_URL=postgresql://tsdbadmin:<initial_password>@<host>:<port>/tsdb?sslmode=require` exactly once to stdout; never log, echo, or write the password anywhere else, and mask it in errors. Also offer `--list` (names, status, host; no passwords) and `--dry-run` (print the request without sending). Reference pages: https://www.tigerdata.com/docs/get-started/quickstart/rest-api and https://www.tigerdata.com/docs/reference/tiger-cloud-rest/resources/projects/subresources/services/methods/create . Equivalent CLI: `tiger service create --cpu shared --memory shared` after `tiger auth login`; connection string via `tiger db connection-string <service-id> --with-password`.
- `DATABASE_URL` form: `postgresql://tsdbadmin:<password>@<service>.<project>.tsdb.cloud.timescale.com:<port>/tsdb?sslmode=require` (the server treats `require` and `verify-full` identically: TLS with system trust).
- `server/Dockerfile` (multi-stage Swift 6 build, slim runtime, non-root user, `EXPOSE 8080`, `CMD ["./RevaAPI", "serve"]`) and `server/.dockerignore`.
- `docs/tiger-setup.md`: create the service (Console, CLI, or script), API host env (`REVA_STORAGE=postgres`, `DATABASE_URL`, `REVA_HOST=0.0.0.0`, `REVA_PORT`, `REVA_ALLOWED_ORIGINS=https://<vercel-domain>`, optional `REVA_TOKENS`, `REVA_SIGNUP`), Vercel env `VITE_REVA_API_ORIGIN=https://<api-host>`, first-run migration, verification checklist (health, curl sign-up, log-in, state round-trip, `psql` row check), lockout and rollback notes.

## 9. Ownership for parallel work

- **A — server:** `server/**` except `server/Dockerfile` and `server/.dockerignore`. Runs `swift build` / `swift test`.
- **B — web:** `apps/web/**`. Runs typecheck, vitest, `node --test scripts/serve.test.mjs`, build, prettier.
- **C — deploy:** `scripts/tiger_provision.py`, `server/Dockerfile`, `server/.dockerignore`, `docs/tiger-setup.md`, a section in `docs/architecture.md`, short links in root `README.md`, root `.env.example`.
- Coding standard: `docs/coding-standard.md` (file header `Purpose/Inputs/Outputs/Side effects`, `MARK: -` blocks). No commits, no `git stash`, no paid or live provider calls, no secrets in any file.
