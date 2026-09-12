# Native client / local server integration verification

Owner: backend contributor. Authorized scope for this follow-up is only `Tests/RevaCoreTests/LiveServerTests.swift`, `scripts/test_client_server.py`, and this packet. Do not modify Core, UI, backend source, root configuration, shared build files, or commits.

## Objective and real boundary

Exercise the actual `apps/ios/Reva/Core/ServerClient.swift` URLSession implementation and `AppSnapshot` Codable models against the already compiled local Vapor API. Existing transport tests use URLProtocol fixtures; this separately gated test must perform real localhost HTTP requests. It must use only the repository’s explicit synthetic seed and source files and a temporary server data directory.

## Acceptance checks

1. Normal root `swift test` remains independent: XCTest skips this test unless explicitly given a dedicated local-server URL and integration token.
2. The harness launches `server/.build/debug/RevaAPI` on a dynamically selected loopback port with explicit token-to-owner mappings and a temporary local data directory; it strips inherited Reva/database settings and never writes any `.env`.
3. The real client decodes healthy local status and missing-state 404 revision zero.
4. Decode/validate the full fictional seed, push it with revision zero, pull it with equal domain content, update it, and prove a stale revision is mapped to `ServerFailure.conflict` without changing server content.
5. Upload actual bundled synthetic source bytes with the app’s SHA256-of-filename ID and safe metadata filename transformation; download exact original bytes and verify server response metadata. Use a second owner to prove state/attachment isolation.
6. Exercise attachment delete, state delete, missing snapshot tombstone revision, rejected pre-delete stale write, and successful subsequent write using the tombstone revision.
7. The harness runs root `swift test --filter LiveServerTests` with explicit environment, forwards meaningful output, and reliably terminates its child server on success/failure/interruption. It must not start external services or contact a hosted database.

## Implementation notes

The test uses ephemeral URLSession configuration with no URLProtocol mock and the client’s production methods. It must not infer a live Tiger connection from local success. Full seed equality tests the app/server JSON boundary including records, visits/reports, bookings and recordings present in that fixture. Source metadata can be inspected with an ordinary URLSession GET because `ServerClient.attachment` intentionally exposes bytes only. Read fixtures from the repository path derived from `#filePath`; ensure flat filenames stay inside the synthetic fixture directory.

## Verification status

Specification written before implementation. Root build may be changing under the primary agent; report actual execution results and any compile blockers without modifying files outside this scope.

## Implemented and executed — September 12, 2026

Implemented the single gated `LiveServerTests.testNativeURLSessionClientAgainstLocalVapor` XCTest and `scripts/test_client_server.py` harness. The test uses the actual app `ServerClient`, an ephemeral URLSession with no URLProtocol fixture, the full synthetic `demo/seed.json`, every source referenced by its nine records, and `demo/sample-transcript.json`. After proving unmodified seed equality, it adds a generated report, a clearly synthetic draft booking, sample recording/transcript, Unicode notes and an extra visit question, then verifies complete `AppSnapshot` equality across push/pull.

The harness selects an ephemeral loopback port, generates two random token mappings in memory, launches the prebuilt API with temporary state, checks live readiness, and executes the root Xcode Swift test filter. No token is printed or saved in a configuration file. Its `finally` cleanup terminates the server and Swift test process groups; termination escalates to SIGKILL only for a child which fails to exit within eight seconds. SIGINT and SIGTERM enter that cleanup path. The temporary directory, state, and server log are removed on exit. Missing server binary produces an actionable build instruction instead of creating a substitute server.

`python3 scripts/test_client_server.py` **passed**, running one real XCTest with zero failures in 0.160 seconds (incremental root build 1.06 seconds). The command used the existing compiled backend and the installed Xcode toolchain; the execution log is `/tmp/reva-client-server-integration.log`.

With all four `REVA_*LIVE*` integration settings explicitly unset, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 6 --filter LiveServerTests` **passed with one skipped test**, proving ordinary test runs do not require a backend. The skip evidence is `/tmp/reva-client-server-skip.log`. The final harness Python source also passed syntax compilation after the SIGTERM cleanup handler was added.

Verified: healthy local status; actual 401 authentication mapping; missing-state revision zero; unmodified seed and all populated domain roundtrips; successful update; stale 409 with unchanged server content; nine original PNG/PDF/text source-byte roundtrips with SHA256 filename IDs; Unicode logical filename transformed into a safe `X-Filename` header; stored content type and metadata; other-owner attachment/state isolation and harmless other-owner deletion; attachment removal and repeat deletion; state removal clearing all sources; tombstone revision 3; rejected pre-delete revision 2; successful post-delete write at revision 4. Root `.env` was checked at zero bytes and was never written by this task. No Core, UI, server, build configuration, or commit changes were made.

This verifies the native transport against the functioning local Vapor adapter. It does not execute Tiger/PostgreSQL or any provider integration.
