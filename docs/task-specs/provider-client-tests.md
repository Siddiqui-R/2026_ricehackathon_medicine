# Provider client transport tests

Written before implementation, September 12, 2026. Bounded ownership: new `Tests/RevaCoreTests/ProviderClientTests.swift` and this specification only. Read the current `Core/ProviderClient.swift`, domain models, `ServerClient.swift`, existing URLProtocol tests, and [MVP API contract](mvp-api-contract.md). Do not modify production code or run the package while the primary integrates it.

## Test boundary

Exercise the actual `ProviderClient` with an ephemeral URLSession whose URLProtocol intercepts every request. A locked handler registry keyed by a unique synthetic bearer token isolates concurrent tests. Unregistered requests fail locally. Use reserved `.test` URLs, synthetic text/audio bytes and stub model names; no provider/network/configuration activation occurs.

Eight focused cases cover:

1. Provider status: GET path under a server prefix, exact bearer header, empty request body, independent configured flags/model decoding.
2. Summary: exact record ID/title/full Unicode text and JSON keys; response origin/model preserved; source value unchanged.
3. Preparation: selected candidate IDs, full text, source versions and edited questions map exactly; no extra patient/profile/source fields are transmitted by this DTO.
4. Audio: raw bytes, M4A/WAV/MP3 MIME mapping, safe filename metadata, zero/fractional recording-relative timestamp decoding; empty/over-limit audio fails before transport.
5. Call start: exact reviewed fields, explicit consent and stable request ID across explicit attempts; no client-created appointment or automatic retry.
6. Call status: request ID in the owner-scoped server route, transcript/status decoding, unsafe path rejected before transport.
7. Errors: safe configured 503 reason and generic 401 fallback, no raw HTML/body/token leakage, one request per failed operation.
8. Malformed success responses: invalid JSON, missing required fields and malformed timestamp types fail with the supported user-facing error rather than being accepted.

This transport boundary decodes segment timestamps; it does not know the source recording duration. Semantic timestamp validation, candidate membership validation, configured-call consent enforcement and durable replay handling also require their server/AppStore checks. These tests must not be described as live provider or simulator verification.

## Execution handoff

The primary runs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 6` after the file is ready, or selects `--filter ProviderClientTests` for a focused diagnosis. No build or test execution is performed in this bounded authoring task. Report any source mismatch to the primary instead of weakening the contract or editing shared code.

## Authoring result

All eight XCTest cases are written. Audio checks include exact acceptance at 16 MiB and rejection at one byte over the limit, before transport. Call checks preserve a false consent value for server rejection rather than silently authorizing it. Malformed response cases exercise all five response DTO families.

Read-only integration inspection found source-duration checks in `AppStore+Providers.swift` and provider-relative duration/order checks in `VoiceTranscription.swift`; the client tests intentionally verify decoding rather than duplicating those layers. No production source changes, build, test execution, provider request, commit, or push was performed. The primary's integrated test run remains the execution evidence.
