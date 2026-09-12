# Track 16 — Build, hosting, and supply-chain configuration

**Codex continuation.** This report completes a missing Fable track after the user reported Claude account limits. It was produced by the existing Codex subagent `/root/symptom_entries`; no new Fable worker or Fable/Ultracode execution is claimed. Model/effort are inherited from the parent Codex task and were not independently selectable here.

**Snapshot:** `fable-audit-20260912-114322 @ cfe0997+wip`, source `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`. Only this frozen source, the audit packet, and saved evidence were read. `START-HERE.md`, checklist, assigned track instructions, finding schema, supervisor brief and Addendum 1, refreshed frozen specification, and handoff ledger were consulted. No application edits, Git operations, builds/tests, listeners, UI controls, credentials, or live services were used by this continuation. Existing runner outputs are attributed to their actual producer. Findings require independent coordinator validation.

## Result

Two findings survive: **RVA-16-001 (P2)**, contradictory Vercel root instructions split build/security settings from new pathname rewrites; **RVA-16-002 (P3)**, clean typecheck/tests require generated assets without preparing them. Full source/build evidence and minimal fixes are in `track-16-findings.json`.

The frozen browser production build and native/server builds pass in the actual audit runner. Local wrapper routing/security tests pass. This does not establish a functioning Vercel deployment, hosted API, real account flow, Tiger connection, provider entitlement, or Docker image. The refreshed specification makes accounts/external API configuration active **WIP**; it does not retroactively insert those implementations into this snapshot.

## Assigned inventory

- Root `vercel.json`; nested `apps/web/vercel.json`.
- `apps/web/package.json`, `package-lock.json`, `vite.config.ts`, `tsconfig.json`, `index.html`, `.prettierrc.json` and root ignore rules.
- `apps/web/scripts/prepare-assets.mjs`, `serve.mjs`, `serve.test.mjs`.
- Root `Package.swift`, server `Package.swift`/`Package.resolved`, and the generated Xcode project/scheme settings (read-only).
- Root scripts: `build_overview_packet.py`, `check_code_structure.py`, `check_optimization_fixes.py`, `check_provider_api.py`, `extract_palette.py`, `generate_project.py`, `mock_provider_server.py`, `run_server.py`, `test_client_server.py`. Launch/setup/generator boundaries were prioritized; document/palette scripts were inventoried, not exhaustively executed or semantically reviewed.
- `docs/deployment-vercel.md`, browser README, architecture/team/coding guidance, refreshed frozen specification and handoff. No actual `.env` or credential file was read.

## Checklist coverage

| Requirement | Status | Evidence and boundary |
| --- | --- | --- |
| A04 | Pass | Fresh audit logs reproduce clean install, production browser build, native/server build/tests and local HTTP checks. Initial clean browser checks fail before assets; the later pass is reported separately. Recursive Swift lint under the hidden worktree was voided and replaced with an explicit-file run, not counted as a full pass. |
| L01 | Defect | RVA-16-001: README lines 34/52 select incompatible roots; root config owns build/output/CSP, nested config owns new rewrites. Local four-route wrapper works; actual Vercel resolution/refresh remains unverified. `/app` is WIP, not a delivered-route regression. |
| L02 | WIP | `docs/deployment-vercel.md:28–32` correctly separates static frontend from Node/Vite proxy and Vapor. The frozen API client uses relative same-origin URLs; `VITE_REVA_API_ORIGIN`, external API/CORS integration, account backend and Docker/Tiger provisioning are not captured. They require the later completed delta, not a claim that frontend environment keys create a backend. |
| L03 | Pass | `serve.mjs:48–80` validates targets and route/method allowlists; body acceptance precedes upstream effects at 84–103/166–177; 178–193 refuses redirects and filters response headers; 224–237 confines real paths and sets type/CSP. Seven fresh Node tests exercise authorities/traversal/methods/bodies/headers/redirect/static/HEAD boundaries. Actual PDF/OCR under CSP and every timeout behavior are not established by those seven tests. |
| L04 | Defect | RVA-16-002 is the clean standalone-check failure. `npm ci` and production build themselves pass. Native/server compile passes, but no Release archive, physical signing, live database, Linux container, or registry-outage portability test was performed. |
| A03 | Pass | Scope was reconciled against the supervisor addendum/current spec: heart palette and browser are current; accounts, `/app`, hashed sessions and hosted API-origin work are active WIP; custom document encryption/MyChart/cloud-task alternatives are not missing delivered dependencies. Gemini model availability remains a separate H01 uncertainty. |
| N01 | Pass | Existing runner tests assert actual wrapper HTTP forwarding/rejection and state/provider contract outcomes using synthetic or mock boundaries. Gated and missing runtime evidence is explicit. Clean check ordering is a real reproducible coverage/setup issue, not a reason to discard passing production tests. |

## Reused execution evidence

| Evidence log | Observed outcome |
| --- | --- |
| `r1-04-npm-ci.log` | Clean install succeeds; 69 packages added. Cache-backed installation does not prove registry availability under a fresh machine/network. |
| `r1-19-npm-audit.log`, `r1-19-npm-ls.log` | Runner reports zero known advisory vulnerabilities at that time and matching top-level dependency pins. This is not a source-code or future-vulnerability guarantee. |
| `r1-06-typecheck.log`, `r1-07-vitest.log` | Fresh standalone checks fail because ignored `public/demo` JSON does not exist. |
| `r1-09-web-build.log`, `r1-06b-typecheck-after-assets.log`, `r1-07b-vitest-after-assets.log` | Build generates assets and succeeds; subsequent typecheck and all 77 browser tests pass. |
| `r1-08-serve-test.log` | Seven wrapper tests pass against a mock upstream on isolated ports; exact four application routes serve the index. |
| `r1-18-xcodebuild.log` | Generic iOS Simulator build succeeds for arm64/x86_64; no simulator installation or native UI run. |
| `r1-11-swift-build-server.log`, `r1-12-swift-test-server.log` | Server builds; 31 tests pass, real PostgreSQL test skipped because its environment gate is unset. |
| `r1-10-swift-test-root.log`, `r1-16-client-server.log` | 43 root tests pass with one gated skip; that local URLSession/Vapor test separately passes under the dedicated runner. |
| `r1-13-smoke.log`, `r1-14-postgres-failure.log`, `r1-15-provider-api.log` | Local HTTP owner/conflict/original/restart checks, safe unavailable-Postgres failure, and unconfigured-provider/auth routes pass; no paid calls. |
| `r1-20-package-resolved-pins.log` | 30 server pins, including Vapor 4.122.1, PostgresNIO 1.33.1, SwiftNIO 2.102.0 and SwiftCrypto 4.5.2. |
| `r1-22-post-run-hash-check.log` | Runner reports all 267 captured hashes and captured patch intact after its execution; no unexpected untracked source. This continuation performed no new Git integrity check. |

## Hosting and build conclusions

The root Vercel setup uses `npm ci --include=dev --prefix apps/web`, `npm run build --prefix apps/web`, and output `apps/web/dist`. The asset script intentionally reads the sibling native fixture tree and copies package OCR files locally (`prepare-assets.mjs:18–30`). The production output contains index, hashed bundles, fictional originals/manifest, and local English worker/core/language assets. The 50.7 MB raw artifact size is largely optional OCR runtime variants, not a measured first-page payload or a supply-chain defect.

Local Node hosting is materially stricter than simply forwarding arbitrary `/v1` requests: the frozen wrapper uses a fixed validated loopback origin and an explicit current-route/method allowlist, validates complete bounded request bodies before upstream effects, strips cookies/unsafe headers, refuses upstream redirects, confines static files via realpath and an extension/directory allowlist, and installs a finite request/upstream deadline. Vite development uses a loopback-only target but is not the deployable backend.

Root CSP currently permits same-origin/blob resources, workers and WASM, but no external API origin. Adding a future `VITE_REVA_API_ORIGIN` without reconciling `connect-src` and server exact-origin CORS would not enable hosted requests. That is a **WIP integration requirement**, not a proven failure of absent account code. The nested config has no CSP at all. No “all five hosted routes work” conclusion is justified from the four-route local wrapper or screenshot matrix.

The native generator uses deterministic path-derived project IDs, discovers supported source/resource extensions, and declares separate Debug (`-Onone`) and Release (`-O`) settings. Its scheme contains no UI/unit test target; root Swift package tests and the device harness are separate evidence. Generator import-time writes are documented and were not executed by this reviewer. Ignore rules cover .env/credential files, build outputs, node_modules, public demo/OCR copies, logs, and worktrees; ignored artifacts were not inspected for secrets.

## Required follow-up evidence

Independent validation should reproduce the clean asset ordering from the saved logs or a fresh isolated copy and confirm the contradictory root guidance against both configs. Deployment follow-up needs one chosen root and a preview exercising pathname refresh, security headers, missing API/asset handling, local OCR/PDF workers, and eventually `/app`/external API behavior at a completed account checkpoint. Actual hosting, credentials, account provisioning and live database/provider calls were not attempted. No source fix or deployment is authorized by this report.
