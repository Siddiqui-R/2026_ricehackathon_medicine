# Reva client integration verification specification

**Owner:** client-verification contributor. **Date:** 2026-09-12. **Status:** 17 tests authored; root suite currently blocked by an out-of-scope compile error. All request bodies and fixture data are synthetic.

## Scope and authority

The primary agent assigned a bounded verification task after dataset delivery. The contributor owns only `Tests/RevaCoreTests/TransportTests.swift`, `Tests/RevaCoreTests/FixtureEvidenceTests.swift`, this packet, and `docs/reviews/client-verification.md`. No Core, UI, backend, package, fixture, or shared progress edits; no commits or pushes. Material failures are reported to the primary agent rather than weakening expected evidence. No applicable AGENTS.md is present in this project's tree or previously checked ancestor paths.

Inputs read before authoring: `apps/ios/Reva/Core/ServerClient.swift`, `Models.swift`, `ReportEngine.swift`, `LocalRepository.swift`, `server/README.md`, `Package.swift`, existing `DomainTests.swift`, and `demo/expected-evidence.json`. The root Swift package builds the real Core directory with XCTest tests. The server's documented transport is authoritative for endpoint methods, headers, JSON shape, status behavior, attachment constraints, and revision semantics.

## Test design

`TransportTests.swift` injects an ephemeral URLSession using a custom URLProtocol. Every request is intercepted before networking. A test-specific token dispatches to an isolated handler registry, protected by a lock, so concurrently executed tests cannot consume one another's responses. Handlers inspect URL paths, methods, authorization, content type, attachment filename metadata, request bytes, and JSON shapes. They return controlled HTTP status/header/body data or transport errors. No actual service or account is contacted.

The meaningful transport cases are:

1. Pull decodes a representative fixture snapshot, validates it, and preserves its source-page metadata and relationships. Push sends precisely `{baseRevision, snapshot}` with the expected JSON/body headers; a subsequent pull roundtrip preserves the snapshot. Snapshot data stays unchanged on transport rejection.
2. Missing state (404) surfaces the `X-State-Revision` tombstone, including the zero/missing-header default. A 404 for an attachment remains a normal HTTP failure, not an empty-state instruction.
3. Stale writes (409) yield the explicit conflict error and do not silently retry with a different revision. Other error statuses remain failures. Successful status with malformed/unreadable state does not become usable saved data.
4. Source attachment upload/download preserves binary bytes including zero/non-UTF-8 bytes. Methods, MIME metadata, filename header, and stable ID path agree with the backend. Deleting attachment/state uses the documented endpoints and revision response.
5. URL validation accepts HTTPS and supported HTTP loopback addresses, and rejects non-loopback cleartext URLs, credentials, query/fragment, unsupported schemes, and empty tokens before any request. Host/port normalization and malformed URL cases are tested where they affect this boundary.
6. The upcoming primary-owned `ServerClient.attachmentID(for:)` helper must hash exact filename UTF-8 bytes with SHA-256 to a deterministic backend-safe ID; repeated names match, differing names differ, and traversal/unicode/long names cannot leak into endpoint path IDs. Filename metadata sent on upload must satisfy the backend's ASCII filename contract using the primary-owned fallback behavior.

`FixtureEvidenceTests.swift` loads the real `demo/seed.json` and `demo/expected-evidence.json` by repository-relative paths based on `#filePath`. It invokes the actual ReportEngine for every named scenario, asserts every `mustInclude` and `mustExclude`, and records selected evidence on failure. No synthetic replacements for the fixture expectations are permitted. Each source check requires a generated reference to the specified record and page, then verifies the expected phrase exists in that page's authored text. It also checks source-version/page bounds and that emitted excerpts derive from the referenced page. The separate pinning case proves explicit inclusion overrides baseline exclusion. The uncertain scan's review state/date/reference text and a visible generated review caveat are preserved.

Expected-source checks establish truthful page navigation; they do not require every phrase present in a full source page to be repeated in a concise excerpt. If the current brief's extraction contains mostly boilerplate and omits useful source content, record that separately as a concrete review observation for the primary agent.

## Execution and reporting

Write this specification before implementation. Run the root package with the requested command `swift test -j 6`, setting the Xcode developer directory as needed. An escalated execution request is appropriate for the installed Xcode/compiler caches and has been explicitly requested by the primary task. Record command, exit status, test count, all material failures, and fixes observed after primary-owned changes in `docs/reviews/client-verification.md`.

A failing assertion is evidence to investigate, not permission to relax the fixture. Compiler/test harness issues may be corrected inside the owned test files. App source failures belong to the primary agent. Avoid repetitive broad runs: one initial suite and a final run after material changes, with focused checks as needed. These tests demonstrate local client behavior under controlled responses; they do not prove TLS hosting, live Tiger connectivity, physical-device behavior, or actual server integration.
