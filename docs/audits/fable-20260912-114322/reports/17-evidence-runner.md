# Track 17 — Shared evidence runner, Stage 1 (toolchain, static checks, installs, builds, test suites, smoke scripts)

- Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip` (worktree `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`, detached HEAD `cfe09971443989396b8ef6a14cdf935adba86ddd`).
- Runner: Claude Fable 5.1 (`claude-fable-5-1`) subagent dispatched by the supervisor workflow; Stage 1 ran 2026-09-12 17:04–17:15 UTC (12:04–12:15 local).
- Evidence: `evidence/commands.jsonl` (34 records, `stage: runner1`) and one `evidence/<id>.log` per command. All commands were executed through the sanitizing helper described below; nothing in this report is quoted from memory or from historical pass counts.
- Scope of this stage: everything in the runner packet except UI journeys and reviewer-requested measurements, which belong to Stage 2 (placeholder heading at the end).

## 1. Method and isolation (what was actually done)

**Helper.** `scratchpad/runner/run_cmd.py` (session scratchpad, not in the repository) runs every child with a *fresh* environment containing only `PATH=/Users/tempadmin/.nvm/versions/node/v24.14.1/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, `HOME`, `TMPDIR`, `USER`, `SHELL` (values copied by name only), `LANG=en_US.UTF-8`, `LC_ALL=en_US.UTF-8`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, `CI=1`, `NO_COLOR=1`, plus explicit `--env KEY=VALUE` extras (none were needed for any command). Nothing else from the inherited environment is copied and the inherited environment is never printed. The child is started with `start_new_session=True`, stdout+stderr stream to `evidence/<id>.log`, `wait(timeout=deadline)` enforces the deadline, and the whole process group is `SIGTERM`ed then `SIGKILL`ed on timeout (exit 124). Implementation note: `Popen`+`wait(timeout)` is used instead of `subprocess.run(timeout=)` only because `run()`'s `TimeoutExpired` does not expose the pid needed for `killpg`; the semantics requested by the packet are otherwise identical.

- `r1-00-helper-selftest` (`true`, exit 0), `r1-00-helper-envkeys` (child `env | cut -d= -f1`: only `CI DEVELOPER_DIR HOME LANG LC_ALL NO_COLOR PATH PWD SHELL SHLVL TMPDIR USER _` — `PWD`, `SHLVL`, `_` are added by `/bin/sh` itself), `r1-00-helper-timeout` (`sh -c 'sleep 30 & sleep 30; wait'` with a 2 s deadline: exit 124, no stray `sleep` processes afterwards).
- Note: on the sanitized `PATH`, `python3` resolves to Xcode's `/Applications/Xcode.app/Contents/Developer/usr/bin/python3` (**3.9.6**), not `/usr/local/bin/python3`; every Python launcher below ran under 3.9.6.

**Launcher inspection before execution.** I read every launcher in full before running it: `scripts/check_code_structure.py`, `scripts/check_optimization_fixes.py`, `scripts/test_client_server.py`, `scripts/check_provider_api.py`, `scripts/run_server.py` (not run), `server/scripts/smoke.py`, `server/scripts/check_postgres_failure.py`, `apps/web/scripts/serve.mjs`, `apps/web/scripts/serve.test.mjs`, `apps/web/scripts/prepare-assets.mjs`, `apps/web/package.json`, `apps/web/vite.config.ts`, `apps/web/tsconfig.json`, `vercel.json`, `apps/web/vercel.json`, `Package.swift`, `server/Package.swift`, `.swift-format`, `.gitignore`, `Reva.xcodeproj/xcshareddata/xcschemes/Reva.xcscheme`, the env gates in `Tests/RevaCoreTests/LiveServerTests.swift:68-81` and `server/Tests/RevaServerTests/PostgresIntegrationTests.swift:15-24`. Isolation facts relied on:
  - `smoke.py`, `check_postgres_failure.py`, `check_provider_api.py`, `test_client_server.py` each strip `REVA_*`/`DATABASE_URL` (and `check_provider_api.py` also `GEMINI_*`/`OPENAI_*`/`ELEVENLABS_*`) from their own environment, bind an ephemeral `127.0.0.1` port via `socket.bind(("127.0.0.1", 0))`, use `tempfile.TemporaryDirectory`, synthetic tokens, `REVA_STORAGE=local`, and stop their child in `finally`. `check_postgres_failure.py` points a synthetic `DATABASE_URL` at unreachable `127.0.0.1:1`. None of them touch 8080/5173/4173 or a provider.
  - `serve.test.mjs` copies `serve.mjs` into a temp dir, listens on ephemeral ports and a mock upstream, and passes only `PATH/HOST/PORT/REVA_API_ORIGIN` to the child.
  - `check_optimization_fixes.py` writes only `build/optimization-checks/` and runs the compiled harness against `demo/seed.json`.
  - `prepare-assets.mjs` (via `prebuild`) rewrites only the git-ignored `apps/web/public/demo` and `apps/web/public/ocr`.
  - `xcodebuild` used `-destination 'generic/platform=iOS Simulator'`, `CODE_SIGNING_ALLOWED=NO`, `-derivedDataPath build/FableAuditDerivedData`; no simulator was booted, installed to, or attached.
- Not run, by rule: `generate_project.py`, `generate_fixtures.py`, `render_fixtures.py`, `extract_palette.py`, `build_overview_packet.py`, `swift-format format`, `scripts/run_server.py`, `npm run dev`, `npm run serve` (the last three would target 8080/5173/4173 or real `.env`).
- Concurrency: `r1-04`, `r1-10`, `r1-11` overlapped; `r1-17` overlapped `r1-11`; `r1-16`, `r1-18`, `r1-12` overlapped each other. Wall-clock durations below are therefore under CPU contention on a 14-core M4 Pro and are not benchmark numbers. `r1-12` was deliberately started only after `r1-16` released `server/.build/debug/RevaAPI` so a test-time relink could not replace a binary that a smoke script was executing.

## 2. Toolchain and host (`evidence/r1-01-toolchain.log`)

| Item | Observed |
| --- | --- |
| Host | macOS 26.6.2 (25G83), Darwin 25.6.0 arm64, Apple M4 Pro, 14 cores, 48 GiB RAM (51,539,607,552 bytes), 1.1 TiB free on `/System/Volumes/Data` |
| Xcode | Xcode 26.4 (17E192); SDKs iOS 26.4 / iOS Simulator 26.4 / macOS 26.4 |
| Swift | `swift-driver 1.148.6 Apple Swift version 6.3 (swiftlang-6.3.0.123.5 clang-2100.0.123.102)`, target `arm64-apple-macosx26.0` |
| swift-format | 6.3.0 at `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format` (not on the packet's PATH; invoked by absolute path) |
| Node / npm | v24.14.1 / 11.11.0 (nvm) — satisfies `engines.node >=22.12.0` |
| Python | 3.9.6 (Xcode's `python3` on the sanitized PATH) |
| git | 2.50.1 (Apple Git-155); worktree HEAD `cfe09971443989396b8ef6a14cdf935adba86ddd` (detached) |
| Other session's listeners (documented by `lsof -sTCP:LISTEN` only, never connected to) | `RevaAPI` PID 50539 on `127.0.0.1:8080`; `node` PID 74003 on `127.0.0.1:5173`; `node` PID 86045 on `127.0.0.1:4173` |
| Booted simulator (read-only `simctl list devices booted`; not touched) | iPhone 17 Pro `45A0D099-630E-42BC-9982-329F78A07F1A`, iOS 26.4 |
| Pre-run build outputs in the worktree | none (`node_modules`, `dist`, `public/demo`, `public/ocr`, `.build`, `server/.build`, `build` all absent) |

## 3. Per-command results

Verdicts: **pass** = command exited 0 and its own success criteria were observed in the log; **FAIL** = reproduced failure (exact text in §4); **void** = the command ran but cannot be used as evidence (§4.2); **unverified** = not run or skipped (§5). All logs live in `/Users/tempadmin/Documents/Reva/docs/audits/fable-20260912-114322/evidence/`.

| id | command (cwd = frozen worktree) | exit | wall s | verdict | key numbers |
| --- | --- | --- | --- | --- | --- |
| r1-00-helper-selftest | `true` | 0 | 0.008 | pass | helper works |
| r1-00-helper-envkeys | `env \| cut -d= -f1 \| sort` | 0 | 0.021 | pass | 13 env names, none REVA_/GEMINI_/OPENAI_/ELEVENLABS_/TIGERDATA_/DATABASE_URL |
| r1-00-helper-timeout | `sleep 30 & sleep 30; wait` (2 s deadline) | 124 | 2.005 | pass | process group killed; no stray `sleep` |
| r1-01-toolchain | `sh toolchain.sh` (versions, git, lsof, simctl list, SDKs) | 0 | 1.587 | pass | see §2 |
| r1-02-structure-check | `python3 scripts/check_code_structure.py` | 0 | 0.129 | pass | "Structure check passed: 71 Swift and 53 browser source files have contracts and named sections." |
| r1-03-swift-format-lint | `swift-format lint --strict --recursive --configuration .swift-format apps/ios/Reva server/Sources Tests server/Tests Package.swift server/Package.swift` | 0 | 0.036 | **void** | 0 diagnostics but only the 2 explicit `Package.swift` files were visited (§4.2) |
| r1-03-swift-format-probe | same tool on a scratch file with deliberate violations | 1 | 0.041 | pass (tool sanity) | 6 diagnostics (`OrderedImports`, `DoNotUseSemicolons`, `Spacing`) |
| r1-03b-swift-format-lint-explicit | `(find … -name '*.swift'; Package.swift; server/Package.swift) \| xargs swift-format lint --strict --configuration .swift-format` | 0 | 2.201 | **pass** | 86 files, **0 diagnostics** (0 in the WIP-diff files `ProviderConfiguration.swift`, `GeminiProviderTests.swift`; 0 historical) |
| r1-03c-swift-format-recursive-probe | lineLength=40 scratch config: (a) `--recursive` dirs vs (b) explicit list vs (c) `--recursive` on a copy outside the hidden path | 0 | 1.375 | pass (tool behaviour) | (a) 17 diagnostics in 2 files; (b) 11,483 diagnostics in 86 files; (c) 5,785 diagnostics |
| r1-04-npm-ci | `npm ci --include=dev --prefix apps/web` | 0 | 2.778 | pass | "added 69 packages, and audited 70 packages in 3s … found 0 vulnerabilities" (2.8 s implies the local npm cache served the tarballs; lockfile integrity was still verified by `npm ci`) |
| r1-05-format-check | `npm --prefix apps/web run format:check` | 0 | 3.454 | pass | "All matched files use Prettier code style!" |
| r1-06-typecheck | `npm --prefix apps/web run typecheck` (clean tree, before any build) | 1 | 1.710 | **FAIL** | 7 TS errors, all rooted in missing generated `public/demo/*.json` (§4.1) |
| r1-07-vitest | `npm --prefix apps/web test` (clean tree) | 1 | 2.251 | **FAIL** | "Test Files 5 failed \| 2 passed (7)", "Tests 25 passed (25)" — 5 files could not load (§4.1) |
| r1-08-serve-test | `node --test apps/web/scripts/serve.test.mjs` | 0 | 0.397 | pass | "tests 7 / pass 7 / fail 0", duration_ms 315.8; ephemeral ports, mock upstream |
| r1-09-web-build | `npm --prefix apps/web run build` (= `prebuild` assets + `tsc -b && vite build`) | 0 | 5.777 | pass | "✓ 1927 modules transformed", "✓ built in 2.03s"; see §6 |
| r1-06b-typecheck-after-assets | re-run of r1-06 after r1-09 generated `public/demo` | 0 | 1.222 | pass | `tsc -b` clean |
| r1-07b-vitest-after-assets | re-run of r1-07 after r1-09 | 0 | 2.256 | pass | "Test Files 7 passed (7)", "Tests **77 passed (77)**", "Duration 1.10s"; per file: visitDates 18, useVisitRecorder 7, api 9, domain 12, visitEdits 6, repository 7, store 18 |
| r1-10-swift-test-root | `swift test -j 4` (root `RevaCore`) | 0 | 30.056 | pass | XCTest "Executed 44 tests, with 1 test skipped and 0 failures"; 43 passed across DomainTests 9, FixtureEvidenceTests 4, MedicalProfileTests 3, ProviderClientTests 8, SymptomEntryTests 6, TransportTests 13; skipped = `LiveServerTests.testNativeURLSessionClientAgainstLocalVapor` (env gate, exercised in r1-16); Swift Testing "0 tests in 0 suites"; 0 compiler warnings |
| r1-11-swift-build-server | `swift build --package-path server -j 4` (first build, fetches pinned deps) | 0 | 326.406 | pass | "Build complete! (325.44s)", 2832 build steps, **0 `warning:` lines** in the whole log |
| r1-12-swift-test-server | `swift test --package-path server -j 4` | 0 | 27.435 | pass | Swift Testing "Test run with **31 tests in 4 suites passed** after 0.276 seconds", **1 skipped**: `realDatabaseRoundtripAndMigrations()` (`REVA_TEST_DATABASE_URL` unset); suites: "Reva HTTP and persistence", "Gemini providers — mocked HTTP only", "PostgreSQL integration — dedicated database only", "Voice provider adapters — mocked transport only"; XCTest "Executed 0 tests"; 0 warnings during test build |
| r1-13-smoke | `python3 server/scripts/smoke.py` | 0 | 1.196 | pass | "PASS: real HTTP auth, owner isolation, conflict, bytes, process restart, deletion and tombstone checks" |
| r1-14-postgres-failure | `python3 server/scripts/check_postgres_failure.py` | 0 | 20.536 | pass | "PASS: PostgreSQL unreachable exits 1 in 20.4s; credentials redacted; no local files" |
| r1-15-provider-api | `python3 scripts/check_provider_api.py` (imports `test_client_server` from `sys.path[0]`; no PYTHONPATH needed) | 0 | 0.733 | pass | "PASS: real HTTP provider status, all six route auth checks, and four unconfigured 503 responses; no provider credentials or outbound calls." |
| r1-16-client-server | `python3 scripts/test_client_server.py` | 0 | 2.113 | pass | `LiveServerTests.testNativeURLSessionClientAgainstLocalVapor` "passed (0.270 seconds)"; "PASS: native ServerClient ↔ real local Vapor API"; script-internal `swift test -j 6 --filter LiveServerTests` |
| r1-17-optimization-checks | `python3 scripts/check_optimization_fixes.py` | 0 | 29.178 | pass | 6 PASS lines: R5, R1, R3, R6, R2, R9 (StateChecks + ProviderChecks compiled with `swiftc -swift-version 5`); wrote only `build/optimization-checks/` |
| r1-18-xcodebuild | `xcodebuild -project Reva.xcodeproj -scheme Reva -destination 'generic/platform=iOS Simulator' -derivedDataPath build/FableAuditDerivedData CODE_SIGNING_ALLOWED=NO build` | 0 | 21.796 | pass | "** BUILD SUCCEEDED **"; 69 `SwiftCompile` per slice for arm64 and x86_64; **1 warning** total: `appintentsmetadataprocessor … warning: Metadata extraction skipped. No AppIntents.framework dependency found.` (informational, not a source diagnostic); 0 `error:` |
| r1-19-npm-audit | `npm audit --prefix apps/web --json` (registry advisory metadata only) | 0 | 0.672 | pass | vulnerabilities total 0 (info/low/moderate/high/critical all 0); dependencies prod 19, dev 92, optional 59, total 122 |
| r1-19-npm-ls | `npm ls --prefix apps/web --depth=0` | 0 | 0.455 | pass | 15 top-level packages exactly as pinned in `package.json` (`@types/node@24.13.4`, `fake-indexeddb@6.2.5`, `prettier@3.9.6`, `vitest@5.0.0` resolve the caret ranges) |
| r1-20-package-resolved-pins | `python3 pins_summary.py` (read-only parse of `server/Package.resolved`) | 0 | 0.201 | pass | resolved v3, **30 pins**; `vapor 4.122.1`, `postgres-nio 1.33.1`, `swift-nio 2.102.0`, `swift-nio-ssl 2.37.4`, `swift-crypto 4.5.2`, `async-http-client 1.36.1` … (full list in log) |
| r1-20-show-dependencies | `swift package show-dependencies --package-path server` | 0 | 0.679 | pass | 247-line tree from the resolved checkouts |
| r1-21-dist-inventory | `python3 dist_inventory.py` (read-only) | 0 | 12.942 | pass | see §6 |
| r1-22-post-run-hash-check | `hash_check.py; git status --short; git status --short --ignored; git diff --stat` | 0 | 0.609 | pass | "manifest entries=267 ok=267 mismatch=0 missing=0", "patch sha256 match: True"; see §7 |
| r1-23-final-process-check | `lsof … LISTEN; pgrep …; ls $TMPDIR/reva-*; cmp current-diff .audit-source-delta.patch` | 0 | 0.366 | pass | no runner listeners; diff "identical"; one transient `swift-build` PID observed (§8) |
| r1-24-final-process-recheck | `pgrep …; ps -p 37138; lsof cwd in worktree; lsof LISTEN` | 0 | 0.674 | pass | PID 37138 exited; no process has a cwd inside the frozen worktree; no helper processes |

## 4. Failures and voided evidence

### 4.1 Reproduced failure: `npm run typecheck` and `npm test` fail on a clean checkout until the generated demo assets exist

- Trigger: fresh `npm ci` (r1-04), then `npm --prefix apps/web run typecheck` (r1-06) or `npm --prefix apps/web test` (r1-07) **before** `npm run assets`/`npm run build` has ever run.
- Exact failing text (`evidence/r1-06-typecheck.log`):
  ```
  src/core/__tests__/domain.test.ts(6,22): error TS2307: Cannot find module '../../../public/demo/expected-evidence.json' or its corresponding type declarations.
  src/core/__tests__/domain.test.ts(32,83): error TS2345: Argument of type '(scenario: any) => Promise<void>' is not assignable to parameter of type '(...args: any[] | [any]) => Awaitable<void>'.
  src/core/__tests__/domain.test.ts(36,35): error TS7006: Parameter 'id' implicitly has an 'any' type.
  src/core/__tests__/domain.test.ts(37,35): error TS7006: Parameter 'id' implicitly has an 'any' type.
  src/core/__tests__/domain.test.ts(38,36): error TS7006: Parameter 'check' implicitly has an 'any' type.
  src/core/__tests__/fixtures.ts(5,22): error TS2307: Cannot find module '../../../public/demo/seed.json' or its corresponding type declarations.
  src/core/__tests__/fixtures.ts(6,24): error TS2307: Cannot find module '../../../public/demo/sample-transcript.json' or its corresponding type declarations.
  ```
  and (`evidence/r1-07-vitest.log`) `Error: Cannot find module '../../../public/demo/seed.json' imported from …/apps/web/src/core/__tests__/fixtures.ts` (4×) and `… '../../../public/demo/expected-evidence.json' imported from …/domain.test.ts` (1×); summary `Test Files  5 failed | 2 passed (7)`, `Tests  25 passed (25)`.
- Root cause (source-proven): `apps/web/src/core/__tests__/fixtures.ts:5-6` and `apps/web/src/core/__tests__/domain.test.ts:6` import from `public/demo/`, which is generated by `apps/web/scripts/prepare-assets.mjs` (copy of `apps/ios/Reva/Resources`) and git-ignored (`.gitignore` line `apps/web/public/demo/`). `apps/web/package.json:9-19` wires `predev` and `prebuild` to `npm run assets` but has no `pretest`/`pretypecheck` hook (lines 16-17 are bare `tsc -b` / `vitest run src`). The TS2345/TS7006 errors are secondary: with the JSON module unresolved, `evidence` is `any`, so `it.each(evidence.scenarios)` picks the variadic overload.
- After r1-09 generated the assets, both commands pass unchanged (r1-06b exit 0; r1-07b 77/77). `apps/web/README.md:13-15` does document `npm ci`, `npm run assets`, `npm run dev` before the check commands at lines 23-26, so this is an ordering trap rather than a broken test; the Vercel path (`vercel.json` `buildCommand: npm run build --prefix apps/web`) is unaffected because `prebuild` runs first.
- Disposition for reviewers (tracks 15/16, checklist A04/L04/N01): `candidate`, P3, owner Captain (shared scripts/config). Smallest fix candidates: add `"pretest": "npm run assets"` and `"pretypecheck": "npm run assets"` (or import the fixtures from `../../../../ios/Reva/Resources/…` directly as `domain.test.ts` already does for the native goldens elsewhere). Regression check: clean clone → `npm ci` → `npm test` passes without a prior build. The runner does not file findings; this is recorded here for the source reviewers/validators.

### 4.2 Voided evidence: `swift-format lint --recursive` silently linted nothing inside this worktree (tooling caveat, not a project defect)

- r1-03 (the packet's exact command) exited 0 in 0.036 s with no output. Probe r1-03c with a scratch configuration (`lineLength: 40`, otherwise the repository `.swift-format`) shows why: (a) passing the directories with `--recursive` produced 17 diagnostics touching only `Package.swift` and `server/Package.swift` (the two files named explicitly); (b) passing the same 86 files explicitly produced 11,483 diagnostics in 86 files; (c) `--recursive` on a copy of `apps/ios/Reva` placed outside any hidden path produced 5,785 diagnostics. swift-format 6.3.0's directory traversal therefore skipped every directory under `/Users/tempadmin/Documents/Reva/.worktrees/…` (a path with a hidden `.worktrees` component). Any future audit or CI step that lints a hidden-path checkout with `--recursive` will report a false clean result; the main checkout at `/Users/tempadmin/Documents/Reva` is not a hidden path, so the project's documented command is not itself affected.
- Valid lint result is r1-03b (explicit file list, repository configuration, `--strict`): **0 diagnostics in 86 files** (71 under `apps/ios/Reva`, `server/Sources`, `Tests`, `server/Tests` plus the two manifests), so there is nothing to separate between the WIP-diff files (`server/Sources/RevaServer/Providers/ProviderConfiguration.swift`, `server/Tests/RevaServerTests/GeminiProviderTests.swift`) and historical files: both sets are clean. No `swift-format-ignore` directives exist in the tree (grep count 0).

### 4.3 Nothing else failed

Every other command exited 0 with its own PASS/succeeded text present in its log. No command hit its deadline (only the deliberate helper self-test did).

## 5. Skipped, unverified, and explicitly not covered in Stage 1

| Item | Status | Reason / what would be needed |
| --- | --- | --- |
| `PostgresIntegrationTests.realDatabaseRoundtripAndMigrations` | unverified (skipped by its `.enabled(if: REVA_TEST_DATABASE_URL != nil)` gate) | Packet instructed leaving `REVA_TEST_DATABASE_URL` unset; no local ephemeral PostgreSQL was provisioned or probed for; live Tiger stays unverified (checklist G04 real-DB path). Only the fail-closed path (r1-14) is verified. |
| `LiveServerTests` inside r1-10 | skipped by env gate, then **verified** in r1-16 | — |
| Native app execution, `xcodebuild test`, simulator/UI, device hardware | unverified | Scheme has no test targets (`Reva.xcscheme` `TestAction` lists no testables); the only booted simulator belongs to the other session; Stage 2 may cover browser UI only. |
| Browser UI journeys at 375/390/768/1024/1440/1920, focus/Escape/labels/zoom, print artifacts | not started (Stage 2) | See placeholder section. |
| Reviewer-requested measurements (startup/search/relevance/serialization/OCR/recording) | not started (Stage 2) | No `## Evidence requests` sections existed yet at Stage 1 time. |
| Vercel hosted behaviour (`/`, `/demo`, `/login`, `/signup` on a deployment) | unverified | No deployment is permitted; the local wrapper routes are verified by r1-08 (`/`, `/demo`, `/demo/`, `/login`, `/signup` served as `text/html`), and the built `dist` exists (r1-09/r1-21). |
| Exact ephemeral port numbers used by the smoke/integration scripts | not recorded | The scripts bind port 0 internally and do not print the port; their own cleanup stopped every child (r1-23/r1-24 show no runner listeners). |
| Registry reachability | not independently proven | `npm ci` finished in 2.8 s, consistent with the local npm cache; `npm audit` did reach the advisory endpoint (a JSON report came back). |
| Wall-clock durations | indicative only | Several commands ran concurrently (§1). |
| `scripts/run_server.py`, `npm run dev`, `npm run serve`, generators, `swift-format format` | not run by rule | Would read `.env`, bind 8080/5173/4173, or write tracked files. |

## 6. Artifacts produced (all git-ignored build outputs inside the frozen worktree, plus evidence logs)

- `apps/web/node_modules/` — 69 packages installed by `npm ci` (122 total incl. optional per `npm audit` metadata).
- `apps/web/public/demo/` — 15 files, 816,719 bytes (copy of `apps/ios/Reva/Resources`); `apps/web/public/ocr/` — 14 files, 47,773,887 bytes (`worker.min.js` 111,307; six `tesseract-core*.wasm` 2.86–3.46 MB each; six `*.wasm.js` 3.90–4.70 MB each; `eng.traineddata.gz` 2,952,873).
- `apps/web/dist/` (r1-09, inventoried in r1-21): **36 files, 50,729,813 bytes raw, 21,108,783 bytes gzip(6) in-memory**. By directory: root 2 files 995 B; `assets` 5 files 2,138,212 raw / 633,329 gzip; `demo` 15 files 816,719 / 703,849; `ocr` 14 files 47,773,887 / 19,770,956. `dist/ocr` and `dist/demo` are byte-identical to the generated `public/` copies (0 missing, 0 hash mismatches).
  - Main assets (raw bytes; gzip via `gzip -c | wc -c` as the packet specified; Vite's own reported gzip in parentheses): `assets/index-DmnkhT8m.js` 390,616 → 116,014 (116.93 kB); `assets/index-C3ywBgcB.css` 34,014 → 7,846 (7.85 kB); `assets/pdf-Bhi43J5Z.js` 430,931 → 127,567 (129.03 kB); `assets/pdf.worker.min-Dswkl-cV.mjs` 1,265,413 → 374,803; `assets/src-DbcVaO1z.js` 17,238 → 7,196 (7.30 kB). `dist/index.html` 800 bytes, references only `/assets/index-DmnkhT8m.js` and `/assets/index-C3ywBgcB.css`; `theme-color` `#B84250`.
- `apps/web/tsconfig.tsbuildinfo` (from `tsc -b`; ignored by `*.tsbuildinfo`).
- `.build/` (root package: RevaCore + RevaCoreTests debug), `server/.build/` (checkouts of the 30 pinned packages, `debug/RevaAPI`, test bundle), `build/optimization-checks/` (copied sources, `ServerClient+AudioMetadata.swift`, `StateChecks`, `ProviderChecks` executables), `build/FableAuditDerivedData/` (`Build/Products/Debug-iphonesimulator`, arm64 + x86_64 slices).
- Evidence: `evidence/commands.jsonl` (34 records) and 34 `evidence/r1-*.log` files listed in §3; `evidence/runner1-summary.json` (machine-readable copy of this report's tables).
- Scratch helpers (outside the repository, not evidence): `run_cmd.py`, `toolchain.sh`, `dist_inventory.py`, `hash_check.py`, `pins_summary.py`, `probe-linelength40.json`, `lint-probe*/`, `current-diff.patch`.
- Pre-existing in `evidence/` and not touched by the runner: `00-snapshot-verification.log` (supervisor) and `evidence/context/` (supervisor handoff copies created 12:12 local).

## 7. Source integrity after all runs (`evidence/r1-22-post-run-hash-check.log`, `r1-23-final-process-check.log`)

- All **267/267** `snapshot-manifest.json` SHA-256 hashes match the worktree files; 0 mismatches, 0 missing.
- `.audit-source-delta.patch` SHA-256 matches `patchSHA256` (`ae939f8a…480687`), and `git diff` of the working tree is **byte-identical** (`cmp` → "identical", 25,480 bytes) to that captured patch: 13 files changed, 60 insertions(+), 26 deletions(-), the same file list as the supervisor's pre-run status.
- `git status --short` is identical to the pre-run snapshot (13 ` M` tracked files; untracked `.audit-source-delta.patch`, `apps/web/src/landing/`, `apps/web/src/styles/landing.css`, `apps/web/vercel.json`). **No unexpected untracked files.**
- Ignored entries that now exist (expected build outputs only): `.build/`, `apps/web/dist/`, `apps/web/node_modules/`, `apps/web/public/demo/`, `apps/web/public/ocr/`, `apps/web/tsconfig.tsbuildinfo`, `build/`, `server/.build/`.
- The live main checkout was not read except `docs/task-specs/accounts-and-tiger.md` (not needed for Stage 1; not read). No `.env`, keychain, credential, or patient storage was read. The only credential-like strings encountered are the scripts' own synthetic test tokens/URLs (e.g. `check_postgres_failure.py`'s deliberately fake `DATABASE_URL`), which the script asserts are redacted from server output (r1-14 PASS).

## 8. Processes, ports, and cleanup

- Every command ran in its own session (process group); the helper sends `SIGTERM` to the group after a normal exit and `SIGTERM`→`SIGKILL` on deadline. No deadline was hit outside the self-test.
- Listeners created by the runner: only the scripts' own ephemeral `127.0.0.1` listeners (r1-08 wrapper + mock upstream + trap; r1-13 RevaAPI ×2 restarts; r1-15 RevaAPI; r1-16 RevaAPI), each stopped by the script's `finally`/`t.after` cleanup. r1-14 started RevaAPI, which exited by itself (exit 1) without listening. Port numbers were not printed by the scripts (§5).
- Final verification (r1-23 at 17:13:17 UTC, r1-24 at 17:14:50 UTC): no runner-owned LISTEN socket; no `RevaAPI`, `StateChecks`, `ProviderChecks`, `serve.mjs`, `xcodebuild`, `xctest`, `vitest`, or `run_cmd.py` process of mine; no process has a cwd inside the frozen worktree; `$TMPDIR/reva-*` is empty. r1-23's `pgrep` matched one transient `swift-build` process (PID 37138, no cwd resolvable); by r1-24 it had exited (`ps -p 37138` empty). I did not signal it, because its ownership could not be established and it disappeared on its own within ~90 s of r1-12 finishing.
- Pre-existing processes observed and **not touched**: `RevaAPI` 50539 (:8080), `node` 74003 (:5173), `node scripts/serve.mjs` 86045 (:4173) — the other Reva session — plus unrelated user processes (Degree Planner `cspserve.mjs` nodes on :51000/:8897/:8961/:8801, Python/Electron listeners, Spotify, rapportd, ControlCenter, Adobe). The many `/tmp/reva-*` files listed in r1-23 predate this run (newest 12:09 local `reva-web-dev.log` is the other session's Vite log) and were not created or modified by the runner.

## 9. Checklist IDs this evidence supports (for coverage.csv; dispositions are the reviewers'/validators' to set)

- **A01/A04**: r1-01 (snapshot identity), r1-22/r1-23 (hashes, patch, status) — reproduced builds/checks rather than historical counts.
- **B01**: r1-02 structure check pass (71 Swift + 53 browser files); r1-03b lint clean (86 files).
- **L03**: r1-08 wrapper suite 7/7 (fixed loopback destination, route/method allowlist, traversal/symlink refusal, body limits, redirect refusal, CSP headers, app routes).
- **L04**: r1-04 clean pinned install (0 vulnerabilities), r1-09 web build, r1-11 server build (0 warnings), r1-18 native simulator build (1 informational warning), r1-19/r1-20 dependency surface (15 top-level npm, 30 Swift pins).
- **L01** (partial, local only): r1-09 `dist` layout and r1-08 route serving; hosted Vercel behaviour unverified.
- **G01/G02/G03** (partial): r1-13 smoke (401, owner 404s, 409 CAS, exact bytes, restart durability, tombstones), r1-12 server suites, r1-16 native client round trip.
- **G04** (partial): r1-14 fail-closed/redaction/no-fallback; real DB path unverified.
- **H04** (partial): r1-15 (providers unconfigured → 503, 401 on all six routes, token absent from bodies, no receipts).
- **N01** (inventory input): unit/integration counts — web 77 (7 files) + wrapper 7; root Swift 43 passed/1 skipped (44); server 31 passed/1 skipped; optimization harness 6 PASS groups; LiveServerTests 1.
- **M01/M02** (input only): r1-21 bundle sizes; r1-17 reproduces the previously fixed sync/collision/dedup/budget checks (R1, R2, R3, R5, R6, R9). No timing benchmarks were taken in Stage 1.

## Stage 2 (UI journeys and measurements)

_Placeholder — Stage 2 will append its own section here (browser journeys at 375/390/768/1024/1440/1920, focus/Escape/labels/zoom checks, print artifacts where tools permit, and bounded measurements requested by source reviewers)._
