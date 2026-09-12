# Track 17: shared evidence runner

Work only in `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`. Logs/artifacts belong in `/Users/tempadmin/Documents/Reva/docs/audits/fable-20260912-114322/evidence`. You are the only audit worker that runs builds, installs dependencies, starts local test listeners or uses simulator/browser UI. Do not contend with the active implementation session's running servers or simulator. Source reviewers submit focused requests to you.

Start by inventorying toolchain and reading every test launcher before executing it. Clear inherited REVA_*, GEMINI_*, OPENAI_*, ELEVENLABS_* and DATABASE_URL values for child processes without printing them; do not read .env or real credentials. Do not call a live provider/database or use an existing patient workspace. Temporary listeners must use unique loopback ports, fresh temporary synthetic storage and synthetic tokens. If a launcher targets existing 8080/4173 or loads real configuration, adapt invocation safely or mark unverified. Do not edit production source to make a check pass.

Run each applicable suite once; save exact command, cwd, start/end, exit status and log. Missing tool/setup and skips are Unverified, not passes. Re-run focused cases only for a new failure or independently validated finding. Enforce finite subprocess deadlines (normally 5 minutes web, 15 minutes Swift/Xcode, 2 minutes smoke; honor existing bounded integration timeout). Do not change system settings or ask another session to stop.

Candidate commands, after validating their isolation:

```sh
python3 scripts/check_code_structure.py
npm ci --include=dev --prefix apps/web
npm --prefix apps/web run format:check
npm --prefix apps/web run typecheck
npm --prefix apps/web test
node --test apps/web/scripts/serve.test.mjs
npm --prefix apps/web run build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 4
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path server -j 4
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path server -j 4
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 scripts/check_optimization_fixes.py
python3 scripts/test_client_server.py
python3 scripts/check_provider_api.py
python3 server/scripts/smoke.py
python3 server/scripts/check_postgres_failure.py
xcodebuild -project Reva.xcodeproj -scheme Reva -destination 'generic/platform=iOS Simulator' -derivedDataPath build/FableAuditDerivedData CODE_SIGNING_ALLOWED=NO build
```

Run swift-format lint in read-only mode using the repository configuration; separate introduced formatting regressions from historical style. Root Swift tests and server tests do not establish hardware or live provider/database readiness. Browser npm test excludes the separate wrapper suite.

Exercise supported isolated UI journeys at 375/390/768/1024/1440/1920 with matching heading waits and screenshots: landing/demo/login/signup, Overview, Records/import/symptoms/source/editor, Medical profile, Visits/brief/print/booking/transcript and Settings. Check focus/Escape/labels/zoom. Use only platform-supported browser/computer tools; do not bypass unavailable UI permissions. Do not reset the user's active browser/app data. If print/hardware/UI tools are unavailable, record exact unverified coverage.

Measure bounded synthetic startup/search/relevance/serialization/OCR/recording resource requests from reviewers; record sample size, time, memory where measurable, repeats and uncertainty. No huge stress traffic or unbounded fuzzing.

Output `reports/17-evidence-runner.md`, `evidence/commands.jsonl` and per-command logs. Notify coordinator early of material failures and provide source reviewers shared evidence paths.
