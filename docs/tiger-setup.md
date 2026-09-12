# Tiger Cloud setup: accounts and hosted persistence

**Status, September 12, 2026.** Written against the Tiger Cloud [REST quickstart](https://www.tigerdata.com/docs/get-started/quickstart/rest-api), the [service create reference](https://www.tigerdata.com/docs/reference/tiger-cloud-rest/resources/projects/subresources/services/methods/create), the Tiger CLI documentation, and the [accounts contract](task-specs/accounts-and-tiger.md). **Nothing in this guide was run against a live Tiger service, a deployed API host, or a built Docker image**; Docker is not installed on the authoring machine. The commands are what to run when you deploy, and the checklist records what to expect, not what was observed.

## What this deploys

Vercel serves `apps/web` as static files. A separately hosted container runs the Swift API from [`server/Dockerfile`](../server/Dockerfile); it is the only process that talks to PostgreSQL. Tiger Cloud hosts that PostgreSQL as a **free shared service** in `us-east-1`. With `REVA_STORAGE=postgres`, accounts, sessions, owner snapshots, attachments, and audit rows all live in that database.

```text
browser ── HTTPS ──▶ Vercel static site (VITE_REVA_API_ORIGIN baked into the bundle)
browser ── HTTPS + CORS ──▶ API host (Vapor, REVA_ALLOWED_ORIGINS) ── TLS ──▶ Tiger Cloud PostgreSQL
```

The [architecture section](architecture.md#accounts-and-tiger-persistence) has the flow diagrams. Prerequisites: a Tiger Cloud account and project, a container platform that terminates HTTPS in front of the API, and the Vercel project from [deployment-vercel.md](deployment-vercel.md). Use synthetic data only; this is a prototype, not a production medical deployment.

## 1. Create the Tiger Cloud service

All three options create the same thing: a plain PostgreSQL service (no add-ons), shared CPU and memory, region `us-east-1`, role `tsdbadmin`, database `tsdb`, TLS required. Tiger documents free services as beta and available only in `us-east-1`.

### Option A: Console

1. Sign in at `console.cloud.tigerdata.com`, open your project, and choose **New service**.
2. Pick PostgreSQL, the shared (free) compute size, region `us-east-1`, and name it (for example `reva-demo`).
3. Copy the password from the one-time credentials screen and the host/port from the connection panel. Assemble `DATABASE_URL` as shown below.

### Option B: Tiger CLI

```sh
curl -fsSL https://cli.tigerdata.com | sh
tiger auth login                                   # add --headless on a remote machine
tiger service create --name reva-demo --cpu shared --memory shared
tiger service list
tiger db connection-string <service-id> --with-password
```

The CLI stores the initial password in the system keyring at creation. `tiger db psql <service-id>` opens an interactive session and `tiger db query <service-id> -c "SELECT 1"` runs one statement; both are documented in the CLI README.

### Option C: `scripts/tiger_provision.py`

Create an API access key and secret key in the Console (project settings) and note the project ID. Export them in the shell that runs the script; never write them into a file in this repository.

```sh
export TIGERDATA_ACCESS_KEY=...     # shown once when created
export TIGERDATA_SECRET_KEY=...
export TIGERDATA_PROJECT_ID=...
python3 scripts/tiger_provision.py create --name reva-demo --dry-run   # prints the request; sends nothing
python3 scripts/tiger_provision.py create --name reva-demo             # creates the free shared service
python3 scripts/tiger_provision.py list                                # name, id, status, host; no passwords
```

What the script does (standard library only, unit-tested with a fake transport):

- `POST https://console.cloud.tigerdata.com/public/api/v1/projects/{project}/services` with HTTP Basic auth (`access key:secret key`) and body `{"name": "reva-demo", "cpu_millis": "shared", "memory_gbs": "shared", "region_code": "us-east-1"}`; no `addons`.
- Polls `GET .../services/{service_id}` every 10 seconds until `status` is `READY` (`QUEUED` and `CONFIGURING` are the states in between); `--timeout-minutes` defaults to 15.
- Prints `DATABASE_URL=postgresql://tsdbadmin:<password>@<host>:<port>/tsdb?sslmode=require` **once** to stdout as soon as the create response (or a later poll) contains the endpoint. Everything else goes to stderr with the access key, secret key, and password masked, including HTTP error bodies.
- Refuses any `--cpu-millis`/`--memory-gbs` other than shared, and any region other than `us-east-1`, unless `--allow-paid` is present. The default can never create a billable service.
- Exit codes: `0` ready, `2` usage or refused paid size, `3` missing `TIGERDATA_*`, `4` HTTP/API failure, `5` not `READY` in time (the URL line was still printed when the endpoint was known, because the password is returned only at creation), `130` interrupted.

Authentication note: the quickstart documents HTTP Basic with the access and secret key, which the script uses. The generated examples on the REST reference page show a bearer-style header instead. If the API answers `401` to Basic auth, compare with the current quickstart before changing the script.

### The connection string

```text
DATABASE_URL=postgresql://tsdbadmin:<password>@<service>.<project>.tsdb.cloud.timescale.com:<port>/tsdb?sslmode=require
```

- The server accepts only the `sslmode` query option and treats `require` exactly like `verify-full`: TLS with system trust and hostname verification. Never use `disable` for a hosted database.
- Percent-encode reserved characters in the password; the script does this automatically.
- The password is returned only at creation. Store it in the platform's secret manager. If it is lost, reset it in the Console (or with the CLI) and update `DATABASE_URL`.
- Free services can be paused by Tiger after inactivity; the first connection after a pause may fail while the service resumes. Check the service status in the Console or with `list`.

## 2. Run the API host

### Build the image

```sh
docker build -t reva-api ./server
```

[`server/Dockerfile`](../server/Dockerfile) is a multi-stage build: `swift:6.1-noble` runs `swift build -c release --product RevaAPI --static-swift-stdlib`, then the executable and every `*.resources` bundle (including `RevaServer_RevaServer.resources/Migrations/*.sql`, which the migration runner loads through `Bundle.module`) are copied into `swift:6.1-noble-slim` with `ca-certificates` for Tiger's TLS chain. The image runs as the non-root user `reva`, sets `REVA_HOST=0.0.0.0`, `REVA_PORT=8080`, and `REVA_DATA_DIRECTORY=/app/data`, declares `EXPOSE 8080`, and starts with `CMD ["./RevaAPI", "serve"]`. [`server/.dockerignore`](../server/.dockerignore) keeps `.build`, `.local-data`, env files, and logs out of the context. **The image has not been built locally.**

Any platform that builds a Dockerfile works (Fly.io, Render, Railway, Cloud Run, or a VM behind Caddy). The container serves plain HTTP, so the platform must terminate HTTPS in front of it; the browser client refuses a non-HTTPS API origin except loopback. If the platform injects a `PORT` variable, set `REVA_PORT` to the same value: the server reads only `REVA_PORT` and rejects Vapor `--port`/`--hostname` overrides. Local-file mode needs persistent storage at `/app/data`; PostgreSQL mode stores account, snapshot and original-file data in the database.

### Environment for the API host

| Variable | Value | Notes |
| --- | --- | --- |
| `REVA_STORAGE` | `postgres` | Required. There is no fallback to local files on failure. |
| `DATABASE_URL` | the line from step 1 | Secret. Only `sslmode` is accepted as a query option. |
| `REVA_HOST` | `0.0.0.0` | Set in the image; listen on every container interface. |
| `REVA_PORT` | `8080` | Set in the image; must match the port the platform routes to. |
| `REVA_ACCOUNTS` | `enabled` | Default. `disabled` removes `/v1/auth/*` and makes the bearer check accept static tokens only. |
| `REVA_SIGNUP` | `open` | Default. `closed` answers `403 Sign-up is closed on this server.`; log-in keeps working. |
| `REVA_SESSION_DAYS` | `30` | Session lifetime, 1–365. |
| `REVA_ALLOWED_ORIGINS` | `https://<vercel-domain>` | Exact origins, comma-separated; never `*`. Add preview domains explicitly. Invalid entries fail start-up. |
| `REVA_DATA_DIRECTORY` | `/app/data` | Set in the image. Call receipts; mount a volume. |
| `REVA_TOKENS` | optional JSON `{"<24+ char token>":"<owner-id>"}` | iOS developer path: a static token entered in Profile > Developer server connection, and the mapping that unlocks paid providers. Not needed for browser accounts. |
| Provider keys | optional | `GEMINI_API_KEY`, `OPENAI_API_KEY` as in [server/README.md](../server/README.md#configurable-mvp-providers). |

Identity rule: PostgreSQL mode (and any non-loopback listener) requires `REVA_TOKENS` **or** `REVA_ACCOUNTS=enabled`. With accounts enabled and no `REVA_TOKENS`, there is no public demo token and `/health` reports `isDemo: false`.

Local Docker example (replace every placeholder; on a platform, enter the same variables in its secret settings):

```sh
docker run --rm -p 8080:8080 \
  -e REVA_STORAGE=postgres \
  -e DATABASE_URL='postgresql://tsdbadmin:<password>@<host>:<port>/tsdb?sslmode=require' \
  -e REVA_ACCOUNTS=enabled -e REVA_SIGNUP=open -e REVA_SESSION_DAYS=30 \
  -e REVA_ALLOWED_ORIGINS='https://<vercel-domain>' \
  -v reva-data:/app/data \
  reva-api
```

### First run: migrations

On every start the server connects, takes advisory lock `727382019` inside a transaction, creates `reva_schema_migrations` if it is missing, reads the highest recorded version, and applies every newer migration in order: `001_snapshot` (`reva_owner_state`, `reva_attachments`, `reva_mutations`) then `002_accounts` (`reva_users`, `reva_sessions`, index `reva_sessions_user`). Each applied version is recorded in the same transaction. It then logs `Reva storage=postgres, demo=false` and starts listening. The `tsdbadmin` role owns the database and can create tables; least-privilege role separation is later work.

If the database is unreachable, TLS trust fails, the role cannot create tables, or the recorded schema version is newer than the binary knows, the process exits non-zero with `PostgreSQL startup/migration failed. Verify DATABASE_URL, TLS trust and database permissions.` and no local fallback. Restarting is safe: migrations already recorded are skipped.

## 3. Vercel web project

1. In the Vercel project, add the environment variable `VITE_REVA_API_ORIGIN=https://<api-host>` for Production (and Preview if previews should use the same API). Vite inlines it at build time, so **redeploy after changing it**. The value must be `https://...`; the client throws at start-up for anything else except a loopback `http://` origin used in local development.
2. Keep the build settings from [deployment-vercel.md](deployment-vercel.md). The pathname routes `/`, `/signup`, `/login`, `/app`, and `/demo` are served by the static site; `/demo` keeps working without an account. Direct loads of those paths need `rewrites` to `/index.html` in the `vercel.json` that Vercel actually reads, which is the one in the project's Root Directory (the repository root per that guide); a `vercel.json` under `apps/web/` is not consulted while the Root Directory stays at the repository root.
3. Content Security Policy: the checked-in `vercel.json` currently sends `connect-src 'self' blob:`. A cross-origin API host must be added there (for example `connect-src 'self' blob: https://<api-host>`), otherwise the browser blocks every request to the API even though CORS is configured correctly. `vercel.json` belongs to the web work; treat this as a deployment prerequisite.
4. `REVA_ALLOWED_ORIGINS` on the API must list the exact origin users open in the browser, including any custom domain.

## 4. Verification checklist

Run against your deployment with a throwaway email and synthetic data. `API` is the HTTPS origin of the API host. Expected values come from the contract and the server sources; they were not observed against a live Tiger service.

**Health.**

```sh
API=https://<api-host>
curl -sS "$API/health"
# {"status":"ok","storage":"postgres","isDemo":false}
```

**Sign-up (201).** Passwords are 10–72 bytes and may not equal the email.

```sh
curl -sS -i -X POST "$API/v1/auth/signup" -H 'Content-Type: application/json' \
  -d '{"email":"verify+1@example.com","password":"synthetic-check-2026","name":"Verification"}'
# HTTP/1.1 201 ... Cache-Control: no-store
# {"token":"rs_...","expiresAt":"...","user":{"id":"u_...","email":"verify+1@example.com","name":"Verification","createdAt":"..."}}
```

Repeating the same email answers `409 An account with this email already exists.`; a nine-character password answers `400`; `REVA_SIGNUP=closed` answers `403`.

**Log-in (200)** returns the same envelope. Capture the token for the next steps:

```sh
TOKEN=$(curl -sS -X POST "$API/v1/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"verify+1@example.com","password":"synthetic-check-2026"}' \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])')
```

A wrong password and an unknown email both answer `401 Email or password is incorrect.`

**Session.**

```sh
curl -sS -H "Authorization: Bearer $TOKEN" "$API/v1/auth/session"
# {"kind":"account","owner":"u_...","user":{...},"session":{"id":"...","createdAt":"...","expiresAt":"...","lastUsedAt":"..."}}
```

**State round trip.** The browser pushes an empty personal snapshot by itself the first time `/app` opens; this manual `PUT` only proves the route with a curl-sized snapshot.

```sh
curl -sS -i -H "Authorization: Bearer $TOKEN" "$API/v1/state"
# HTTP/1.1 404 ... X-State-Revision: 0
curl -sS -X PUT "$API/v1/state" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"baseRevision":0,"snapshot":{"schemaVersion":1,"profile":{"id":"verify","name":"Verification"},"records":[],"visits":[],"bookings":[],"recordings":[]}}'
# {"revision":1}
curl -sS -H "Authorization: Bearer $TOKEN" "$API/v1/state"
# {"revision":1,"snapshot":{"schemaVersion":1,...}}
```

A second `PUT` with `baseRevision: 0` answers `409` with `X-State-Revision: 1`.

**CORS preflight** from the Vercel origin.

```sh
curl -sS -i -X OPTIONS "$API/v1/auth/login" -H 'Origin: https://<vercel-domain>' \
  -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type'
# HTTP/1.1 204 ... Access-Control-Allow-Origin: https://<vercel-domain>  Vary: Origin  Access-Control-Max-Age: 600
```

An origin that is not listed receives no `Access-Control-Allow-Origin` header.

**Database rows** with `psql` (or `tiger db query <service-id> -c '...'`, or `tiger db psql <service-id>`).

```sh
psql "$DATABASE_URL" -c 'SELECT count(*) FROM reva_users;'                                   # 1
psql "$DATABASE_URL" -c 'SELECT version, applied_at FROM reva_schema_migrations ORDER BY version;'   # 1 and 2
psql "$DATABASE_URL" -c 'SELECT user_id, email, left(password_hash, 4) AS hash_prefix, created_at FROM reva_users;'   # hash_prefix $2b$ or $2a$; never a plaintext password
psql "$DATABASE_URL" -c 'SELECT count(*) FILTER (WHERE revoked_at IS NULL) AS live, count(*) AS total FROM reva_sessions;'   # 2 live after sign-up plus log-in
psql "$DATABASE_URL" -c 'SELECT owner_id, revision, octet_length(snapshot::text) AS bytes FROM reva_owner_state;'   # the u_... owner at revision 1
```

**Browser.** Open `https://<vercel-domain>/signup`, create a second throwaway account, and confirm you land on `/app`; reload and stay signed in; **Log out** returns to `/login`; `/demo` still runs the fictional data without an account; the landing page shows **Open your workspace** while a session is stored.

**Log out and clean up.**

```sh
curl -sS -i -X POST "$API/v1/auth/logout" -H "Authorization: Bearer $TOKEN"     # 204; the token now answers 401
TOKEN=$(curl -sS -X POST "$API/v1/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"verify+1@example.com","password":"synthetic-check-2026"}' \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])')
curl -sS -i -X DELETE "$API/v1/auth/account" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"password":"synthetic-check-2026"}'   # 204; user, sessions, snapshot, attachments, audit rows removed
psql "$DATABASE_URL" -c 'SELECT count(*) FROM reva_users;'                        # 0 once the browser account is deleted too
```

## 5. Operating notes

### Lockout

Eight failed log-ins for the same normalized email within 15 minutes answer `429` with `Retry-After`. The counter is an in-memory actor per API process, bounded to 10,000 emails; a successful log-in clears it, and a restart clears everything. Several replicas count separately, so the effective limit scales with the replica count. There is no unlock endpoint: wait for the window to pass or restart the process. An unknown email still costs one bcrypt verification so timing does not reveal whether the account exists.

### Sessions

- Tokens are `rs_` plus 43 base64url characters; the database holds only the SHA-256 hex in `reva_sessions.token_hash`. Expiry is `REVA_SESSION_DAYS` from creation; `last_used_at` is touched at most once per five minutes.
- At most 20 live sessions per user; the 21st revokes the oldest. Password change revokes every other session; `POST /v1/auth/logout-all` revokes all of them.
- Revoke everything during an incident, effective on each user's next request:

```sql
UPDATE reva_sessions SET revoked_at = now() WHERE revoked_at IS NULL;                      -- everyone
UPDATE reva_sessions SET revoked_at = now() WHERE revoked_at IS NULL AND user_id = 'u_...'; -- one account
```

- Optional housekeeping (rows are not needed after they expire or are revoked): `DELETE FROM reva_sessions WHERE revoked_at IS NOT NULL OR expires_at < now() - interval '30 days';`
- Closing the door: `REVA_SIGNUP=closed` stops new accounts while existing ones keep working. `REVA_ACCOUNTS=disabled` removes the auth routes and rejects session tokens entirely; in PostgreSQL mode it then requires `REVA_TOKENS`.

### Rollback

- `reva_schema_migrations` holds one row per applied version (`1`, then `2`). A binary that knows only version 1 refuses to start against a version-2 database with `Database schema is newer than this server.`, so rolling the image back to a pre-accounts build is not a plain redeploy.
- Preferred rollback: keep the current image and set `REVA_ACCOUNTS=disabled` (plus `REVA_TOKENS` for the iOS path). Account data stays intact; re-enabling restores it without migration.
- Full schema rollback destroys every account and session. Owner snapshots keyed by `u_...` IDs stay behind as orphans because `reva_owner_state` has no foreign key to `reva_users`; delete them explicitly if wanted. Take a backup or fork in the Tiger Console first, then:

```sql
BEGIN;
DROP TABLE IF EXISTS reva_sessions;
DROP TABLE IF EXISTS reva_users;
DELETE FROM reva_schema_migrations WHERE version = 2;
COMMIT;
```

  After this a version-1 binary starts normally, and a version-2 binary re-creates the two tables empty on its next start.

- Deleting the whole service (`tiger service delete <service-id>` or the Console) removes all data; free-tier backup and recovery options are whatever the Console shows for the service, so check them before relying on them.

## Boundaries

- No secret lives in this repository: the root `.env` stays empty in Git, `.env.example` files are documentation, and the Docker image bakes in no credential. Pass secrets through the platform's environment settings.
- Not verified in this build: Tiger service creation, the REST responses, the Docker image build, TLS to Tiger from the container, the Vercel-to-API CORS path, and every expected value in the checklist. The unit tests cover only the provisioning script against a fake transport.
- References: [Tiger REST quickstart](https://www.tigerdata.com/docs/get-started/quickstart/rest-api), [service create reference](https://www.tigerdata.com/docs/reference/tiger-cloud-rest/resources/projects/subresources/services/methods/create), [Tiger CLI](https://github.com/timescale/tiger-cli), [server guide](../server/README.md), [accounts contract](task-specs/accounts-and-tiger.md).
