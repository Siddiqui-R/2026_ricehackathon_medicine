# Supervisor brief for all audit workers (read first)

Written by the audit supervisor (Claude Fable 5.1, this chat) on 2026-09-12 before dispatching workers.

## Snapshot identity (verified by supervisor)

- Frozen worktree: `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322` (detached HEAD at `cfe09971443989396b8ef6a14cdf935adba86ddd`).
- Snapshot kind: committed base `cfe0997` + captured tracked diff (13 modified files) + 4 first-party untracked files (`apps/web/src/landing/AccountGate.tsx`, `apps/web/src/landing/Landing.tsx`, `apps/web/src/styles/landing.css`, `apps/web/vercel.json`).
- Supervisor verification: all 267 manifest SHA-256 hashes match the worktree; `.audit-source-delta.patch` SHA-256 matches `patchSHA256`; no `.env`, `node_modules`, `.build`, or patient data present in the snapshot. See `evidence/00-snapshot-verification.log`.
- Cite this snapshot as: `fable-audit-20260912-114322 @ cfe0997+wip` in every finding's `snapshot` field.

## What the captured WIP diff contains (so you classify it correctly)

The captured diff (`.audit-source-delta.patch`, 305 lines) is limited to:
1. Gemini default model rename `gemini-2.5-flash` → `gemini-3.8-flash` (+ `gemini-3.5-flash-lite` alternative) in `ProviderConfiguration.swift`, `GeminiProviderTests.swift`, README/docs/env examples/overview packet.
2. Browser pathname routing in `apps/web/src/main.tsx`: `/` → `Landing`, `/login` + `/signup` → `AccountGate` (a static explanation page, **not** a form), `/demo` → workspace; legacy `/#/…` forwarded to `/demo#/…`.
3. `apps/web/scripts/serve.mjs` + `serve.test.mjs`: the four app routes serve `index.html`.
4. `apps/web/vercel.json` (new, nested): rewrites `/demo`, `/login`, `/signup` → `/index.html`. Root `vercel.json` (committed) sets framework/install/build/output and CSP headers. Both exist in the snapshot.
5. `apps/web/README.md`, `docs/architecture.md`, `server/README.md` doc updates.

**The snapshot contains NO real account code.** There is no `/v1/auth/*`, no bcrypt, no session store, no `002_accounts.sql`, no `src/core/session.ts` or `auth.ts`, no `/app` route, no `Dockerfile`, no `tiger_provision.py`, no `docs/tiger-setup.md`. Those are specified by the concurrent implementation contract below and are **WIP / not yet captured**. Report them as `WIP` (status) — never as a defect of a completed path, and never as "excused by auth deferral". Where the *existing* code will need to change for that contract (e.g., identity rule, CORS, bearer middleware, migration runner), you may record a `candidate` or `suggestion` describing the integration risk, clearly tagged as forward-looking.

## Concurrent implementation contract (provenance)

- File: `/Users/tempadmin/Documents/Reva/docs/task-specs/accounts-and-tiger.md` (untracked in main checkout; NOT in the frozen snapshot; read it read-only from that path). Written 2026-09-12 as "implementation contract v1" for the other Claude session ("Reva architecture review"). It specifies: `u_`+24hex user IDs; `rs_`+43 base64url session tokens stored as SHA-256; bcrypt cost 12 via Vapor `Bcrypt` on `app.threadPool`; password 10–72 bytes; `REVA_ACCOUNTS`, `REVA_SIGNUP`, `REVA_SESSION_DAYS`, `REVA_ALLOWED_ORIGINS`; routes `POST /v1/auth/signup|login`, `GET /v1/auth/session`, `POST /v1/auth/logout|logout-all`, `PUT /v1/auth/password`, `DELETE /v1/auth/account`; login lockout 8 failures/15 min; `AccountStore` protocol; `accounts.json` local store; `002_accounts.sql` with `reva_users`/`reva_sessions`; web `/app` route, `session.ts`, `auth.ts`, account-mode `RevaStore` with per-user IndexedDB DB name and 1.5 s debounced auto-push; Tiger provisioning script; Dockerfile.
- Tracks 12 and 13: audit the **existing** token/owner/identity/Postgres code paths that the contract will build on, and evaluate the contract itself for security/consistency risks with the existing code (as `suggestion`/`candidate` with status `WIP`), but do not fabricate defects in code that does not exist.

## Product requirements to carry into every track

SwiftUI iPhone app; responsive React/TypeScript browser; Vapor Swift server. Manual medical uploads (PDF/text/image) and camera/OCR; preserved originals (bytes, filename, MIME, SHA-256, pages) and per-document summaries; relevant, source-grounded pre-visit reports with exact quotations/page links; medical profile and symptom entries; recording/transcription/visit memory; appointment booking simulation plus configured ElevenLabs/Twilio call adapters; explicit persistence/sync with CAS revisions; provider secrets server-only, plug-and-play provider adapters; heart-red/ivory light palette (canvas #FBF7F5, white #FFFFFF, accent #B84250, deep red #8C2F3B, petal #FAE6E5, linen #DBCBC9); desktop responsiveness; accessibility; Vercel/build correctness; three-person modular ownership; Purpose/Inputs/Outputs/Side-effects file contracts + `MARK:` sections; cleanliness and *measured* efficiency.
Excluded from MVP (do not report as missing features): MyChart/FHIR import, custom password-derived document encryption, automatic clinic confirmation, live cellular-call capture, production certification, the old proposed Cloud Storage/Cloud Tasks/Identity Platform/Document AI/SwiftData/50 MB architecture. Ordinary secure password hashing for the new accounts work IS in scope (as WIP contract review).

## Isolation rules (enforced)

- Another live session owns: `RevaAPI` on `127.0.0.1:8080`, Vite dev on `127.0.0.1:5173`, `serve.mjs` on `127.0.0.1:4173`, and the booted `iPhone 17 Pro` simulator (`45A0D099-…`). Never connect to, stop, or reuse them. Never boot/install on any simulator.
- Only the evidence runner (track 17) runs builds/tests/listeners/UI. Runner listeners use fresh ephemeral loopback ports, temp data dirs, synthetic tokens, and child environments with `REVA_*`, `GEMINI_*`, `OPENAI_*`, `ELEVENLABS_*`, `DATABASE_URL`, `TIGERDATA_*` removed (use `env -i` with an explicit allowlist; never print the inherited environment).
- Nobody reads `.env`, credentials, keychains, or real patient storage. Placeholder examples in `*.env.example` may be read.
- Nobody modifies the frozen worktree's tracked/captured files, the main checkout, or dependencies. Build outputs (`node_modules`, `dist`, `.build`, `build/`, `public/demo`, `public/ocr`) inside the frozen worktree are permitted temporary artifacts.
- Report-only writes: exactly your assigned files under `/Users/tempadmin/Documents/Reva/docs/audits/fable-20260912-114322/reports/` (and `evidence/` for the runner).

## Finding rules

- Use `finding-schema.json`. IDs: `RVA-<track>-<NNN>` e.g. `RVA-07-003`. `snapshot` = `fable-audit-20260912-114322 @ cfe0997+wip`. `file` is worktree-relative; `line` is a real 1-based line from the frozen file (verify with `sed -n`).
- `status` ∈ confirmed | candidate | rejected | WIP | evidence-gap | suggestion. A reviewer may set `confirmed` only when the source proof is unambiguous; otherwise `candidate` for validators.
- Every defect needs: trigger, expected, actual, impact, evidence (command/log path or exact source proof), confidence, smallestFix, regressionCheck, ownerTrack (Person 1 records/profile/native preparation; Person 2 visits/booking/memory; Person 3 server/providers; Captain shared core/styles/scripts/config).
- No finding quota. Say explicitly when nothing actionable survives. Separate `suggestion` (style/roadmap) from defects. Efficiency claims need a bounded measurement or a concrete asymptotic/resource argument.
- If a source unexpectedly contains a credential-like value: record location and type only; redact the value.

## Evidence directory conventions

Runner writes `evidence/commands.jsonl` (one JSON object per command: id, cwd, command, start, end, exitStatus, logPath, note) and `evidence/<id>.log`. Reviewers cite `evidence/<id>.log` where it exists at their time; otherwise list precise evidence requests in a `## Evidence requests` section of their report for the runner follow-up pass.

## Addendum 1 (2026-09-12, received mid-run from the user): refreshed specification and handoff ledger

The user's other collaborator captured the implementation chat's summary and refreshed the project spec while this audit runs. Frozen read-only copies (hashes in `evidence/context/SHA256SUMS.txt`, provenance in `evidence/context/CONTEXT-MANIFEST.json`):

- `evidence/context/reva-stack-spec.md` — the **current** product/stack specification (supersedes the older two-hour MVP goal, completion criteria and cloud proposal). Authority for scope questions in tracks 01, 12, 13, 14, 15, 16 and both validators.
- `evidence/context/05-claude-project-handoff.md` — provenance and tested-versus-WIP ledger for the concurrent accounts/landing/Tiger work (implementation workflow `wf_9f792746-fb6`, task `waq60gg6v`). Its "Work status and verification" table is the authoritative WIP boundary.
- `evidence/context/reva-stack-spec-planning.md` — the ORIGINAL proposal, preserved as history only. Its Cloud Storage/Tasks/Identity Platform/Document AI/SwiftData/50 MB items are NOT requirements (checklist A03).
- `evidence/context/accounts-and-tiger.md` — implementation contract v1 (already cited).

Rules for workers reading these:
1. Read the frozen copies above, not the live files under `/Users/tempadmin/Documents/Reva/docs`. The live-checkout application-file prohibition is unchanged.
2. Documentation commits/refreshes are NOT completion checkpoints for accounts. Main HEAD is still `475eee7` (docs only); account/landing/Tiger code is uncommitted WIP outside the frozen snapshot. Findings about it stay `WIP` with a delta-review note.
3. Spec decisions that now bind the audit: landing `/`, demo `/demo`, `/login`, `/signup`, `/app` are required routes (only `/`, `/demo`, `/login`, `/signup` exist in the snapshot as static/placeholder pages; `/app` and the real forms are WIP); bcrypt cost 12 / `rs_` hashed sessions / `REVA_ALLOWED_ORIGINS` exact-origin CORS / `VITE_REVA_API_ORIGIN` are contract items; Gemini default `gemini-3.8-flash` is in the snapshot's WIP diff but its availability is unverified (H01 must say so); Whisper `whisper-1` remains the transcription contract; ElevenLabs Qwen/temperature/10-minute settings are reported proposals, not repository-enforced.
4. Track 16 (and validator 19) must reconcile root `vercel.json` versus nested `apps/web/vercel.json`, pathname rewrites for the five routes, and CSP/external API origin (`VITE_REVA_API_ORIGIN`, `connect-src`) in the snapshot; the handoff notes the other session's suggested Vercel Root Directory `apps/web` conflicts with the committed repository-root build. Report this as a source-level configuration finding on the snapshot plus a delta item; no fixes are authorized.
5. The handoff's claimed early results (typecheck, 77 Vitest, 7 wrapper tests) are historical; only this audit's runner output counts as evidence (A04).
