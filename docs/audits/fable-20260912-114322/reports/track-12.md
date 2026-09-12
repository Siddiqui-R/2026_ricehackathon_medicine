# Track 12 — Accounts, passwords and session boundaries

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip`, the frozen cfe0997 source plus captured WIP.

Reviewer: Codex continuation after explicit user authorization following Claude usage exhaustion. Read-only source review; no builds, UI, live calls, credentials, database or Git operations by this reviewer. Reused the shared Stage1 runner report; its model/transport tests are mocks and are not live provider validation.

## Conclusion and scope boundary

**Actual account implementation is WIP outside the captured snapshot. No account defect is filed merely because that future code is absent.** `track-12-findings.json` is intentionally an empty array. The existing static-token route/auth boundary is source-reviewed and backed by local mock/HTTP tests. It is not a verified login/session system.

Read the frozen context copies `evidence/context/accounts-and-tiger.md`, `reva-stack-spec.md`, `05-claude-project-handoff.md` and the supervisor addendum. These are specification/provenance, not executed code. The snapshot has no `/v1/auth/*`, bcrypt, account store, auth migration, session client, real login form or `/app` workspace; the account gate is honest placeholder UI. Its old internal comment calling accounts deferred does not override the newly active account scope.

## Inventory

Captured integration files inspected: `server/Sources/RevaServer/Configuration.swift`, `HTTP.swift`, `Models.swift`, `LocalFileStore.swift`, `PostgresStore.swift`, `Migrations/001_snapshot.sql`, `Providers/ProviderConfiguration.swift`; browser `src/main.tsx`, `src/landing/AccountGate.tsx`, `src/core/api.ts`; native `Core/ProviderContracts.swift` for the current bearer contract. No absent file was treated as reviewed implementation.

## Contract integration checklist for the next frozen delta

- Trusted identity: middleware must resolve every session to server-stored user ID, check expiry/revocation on every protected route and preserve explicit static-token behavior. Account IDs `u_` plus24 hex fit the current safe-ID and SQL constraints. Keep per-owner medical data separate even when a client-supplied profile.id disagrees.
- Passwords: validate 10–72 **UTF-8 bytes**, then use verbatim input and cost12 adaptive salted hashes on the thread pool. The browser's described minimum-character hint cannot replace server byte validation. Unknown-user dummy verification, invalid-password behavior, lockout and no-secret error/log handling need real request tests. No password code exists here, so none of those claims can pass on implementation evidence yet.
- Sessions: verify cryptographic token generation, hash-only persistence, expiration/revocation, twenty-session cap and concurrent login/password-change/account-delete semantics. Existing static-token dictionaries have no session expiry and should not be misreported as broken expiry support.
- Cross-account browser state: each account/demo needs separate IndexedDB and cancellation/generation protection across login/logout/storage events and pending sync/provider operations. The current single demo workspace cannot supply account isolation evidence. The native existing provider result issue RVA-10-001 should inform the shared future boundary.
- CORS and endpoints: exact origin validation, Vary, preflight methods/headers, exposed revision headers and frontend API-origin/CSP need review together in the new delta. Present browser RevaAPI is same-origin; absence of future external-origin CORS is WIP rather than a completed account bug.
- Deletion: contract deletes account and medical data while call receipts are intentionally independent to prevent redial. The user-facing retention contract needs to explicitly distinguish retained replay receipts from deleted medical state; verify no residual active sessions can recreate the account owner following deletion. Local account/owner multi-file writes require crash/failure policy; PostgreSQL account/state deletion needs a transaction. These are forward-looking integration checks, not proven defects in absent code.
- Deployment: account-enabled non-loopback startup must not activate paid providers via anonymous/public-demo calls. Preserve the current explicit provider authorization gates as identity rule changes. Any default open-signup behavior, signup capacity and password-cost resource control must be judged from actual landed code and test evidence, not inferred from this proposal alone.

## Checklist dispositions

| ID | Disposition | Evidence |
|---|---|---|
| G01 | Pass existing static tokens; WIP account-session identity | HTTP:16-25,104; local runner auth/owner tests. No session middleware captured. |
| G05 | WIP | Hashing/session/lockout contract exists only in context; no implementation/runtime evidence. |
| G06 | WIP | Demo/account storage and pending-work isolation not captured; native old-provider issue is RVA-10-001. |
| G07 | WIP | AccountGate/main.tsx are clear placeholders, not cosmetic authentication falsely accepted as real login. |
| G08 | WIP | No AccountStore/002 migration/owner joins in snapshot; track13 handles current base. |
| H04 | Pass existing server-only key boundary; WIP new session contract | Current ProviderConfiguration and secured group; future AuthAPI/session.ts absent. |

## Evidence requests

Review a **separately identified completed accounts checkpoint**, if provided by the coordinator. Do not mix the live checkout's uncommitted files into cfe0997+wip evidence. Required delta checks: synthetic signup/login/logout/expiry/revocation/password/delete cases, two accounts/demo switching under delayed requests, migration/restart and hosted API-origin routing. No live Tiger or provider credentials required for source/mock checks.
