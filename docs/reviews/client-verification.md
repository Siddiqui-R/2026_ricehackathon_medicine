# Reva client verification review

**Date:** 2026-09-12. **Reviewer:** bounded client-verification contributor. **Data:** synthetic fixtures and intercepted requests only. **Status:** 17 tests authored; root execution blocked by an existing test compile error. Direct Core probe confirms expected record selections and exposes a source-page failure.

## Scope

Read the actual Core transport, model, report engine, and local repository, the backend HTTP contract, and checked-in evidence expectations. Added `TransportTests.swift` and `FixtureEvidenceTests.swift` under the root Swift package, following `docs/task-specs/client-verification.md`. No Core, UI, backend, fixture, or existing test file was edited by this contributor.

The fixture tests consume every inclusion/exclusion expectation, expected source page/phrase, pinning case, and review-needed scan case from `demo/expected-evidence.json`. The URLProtocol tests use isolated synthetic tokens and an ephemeral session to inspect all requests without network access. They cover full snapshot serialization, auth/content headers, revisions and response errors, exact binary bytes, attachment identity/metadata, URL validation, and deletion.

## Execution record

1. Ran `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 6` from the repository root with authorized compiler-cache access. Exit 1 during compilation. Newly added `TransportTests.swift` compiled. The existing `Tests/RevaCoreTests/DomainTests.swift:47` calls throwing `LocalRepository.load()` without `try` following the primary agent's concurrent repository edits. Reported the exact failure to the primary agent; this contributor did not edit the out-of-scope file. No assertion success is claimed from this attempt.
2. Executed a read-only direct Swift probe by passing the exact current `Models.swift`, `ReportEngine.swift`, and `ServerClient.swift` source contents to `swift -e`, followed by synthetic fixture loading and report/URL checks. Exit 0. Primary-care selected exactly `asthma`, `ecg`, `history`, `labs`, and `symptom-diary` record suffixes; orthopedics selected exactly `asthma`, `fibula-injury`, `history`, `leg-imaging`, and `tibia-procedure`. Both sets meet all declared inclusion/exclusion lists. The orthopedic procedure reference was **page 1**, violating the fixture's required **page 2** implant inventory. The laboratory reference was page 1 as expected. `http://[::1]:8080` produced host `::1` and was accepted. These are direct current-Core observations, not a successful root test-suite result.
3. An attempted supplemental ad-hoc XCTest interpreter runner could not load the Swift XCTest overlay/runner entry points outside SwiftPM and did not execute assertions. A preceding stdin compiler probe did not link a main function; the successful `swift -e` Core probe in item 2 superseded it. No generated runner source was added to the repository. The normal root suite remains the required verification path after the compile fix.

## Findings for primary-owned fixes

- **P1 - Root test suite compile blocker.** Restore `try` around the throwing `LocalRepository.load()` call in `Tests/RevaCoreTests/DomainTests.swift:47`. The constructor is now nonthrowing, but loading can still fail. This blocks execution of all newly authored transport and fixture tests.
- **P2 - Orthopedic report targets the wrong procedure page.** `ReportEngine.generate` chooses page 1 for `demo-record-tibia-procedure`; the explicit fixture source check requires page 2, which contains `Implant location: RIGHT TIBIA`. Improve source-page selection without changing the acceptance fixture. The new test reports actual reference pages and continues checking every scenario so one failure does not hide other selection errors.
- **P2 - Source excerpts omit useful source facts.** The direct probe's laboratory excerpt ends at `Collected September 7, 2026 at 08:15 America/Chicago. Reason documented in the order: review of`; it contains headers and no values. The procedure excerpt similarly stops at the first narrative sentence. `localExcerpt` currently takes eight nonempty lines, most consumed by repeated synthetic/patient/provider metadata. Select useful grounded source content while retaining exact values, units, uncertainty, negations, and page provenance.

## Integration observations

- The newly added primary-owned `attachmentID(for:)` and `attachmentMetadataName(_:)` helpers address the fixture-filename/backend-ID mismatch. Tests use independent fixed SHA-256 vectors, including composed/decomposed Unicode UTF-8, and verify that metadata matches the backend's ASCII rules. AppStore's use of those helpers remains a primary-owned integration check.
- Thirteen transport tests and four fixture tests are checked in as uncommitted working-tree changes. No expected-evidence source file was changed or weakened. Correct page navigation is asserted separately from how much source text a concise excerpt repeats.
- Root test results are still required before reporting all transport cases pass. Live API/Tiger, device capture, and UI navigation remain outside the scope of URLProtocol-based unit verification. No commit or push was performed.
