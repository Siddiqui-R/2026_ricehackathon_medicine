# Optimization review and proposed fixes

Reviewed September 12, 2026, at commit `1f1d90c` after pulling `origin/main`.

Implementation follow-up: R1, R2, R3, R5, R6, and R9 have now been changed and passed
focused compiled Swift regression checks. R4 is partially improved; its network
streaming work remains open. R7/R8 remain measurement-gated and unchanged.
The existing local `.gitignore` edits and ignored credentials were preserved.

The findings below retain their original source references at `1f1d90c`. The
implementation status and verification table supersede the original proposals.

## Implementation and compatibility results

Each implemented change was tested before proceeding to the next. R1, R2, R3,
R6, and R9 first failed their new behavioral check against the old implementation
and passed after the corresponding fix. R5 passed equivalent-behavior checks
before and after removing the unnecessary sorting.

| Item | Decision / compatibility check | Result |
| --- | --- | --- |
| R5 | Search unsorted snapshot arrays; preserve sorted list projections, returned records, and nil for missing IDs. | Implemented; focused checks passed. |
| R1 | Add state/connection generations; preserve ordinary pull/push, reject stale completion, and report edits made during a captured push. Same wire schema and revision contract. | Implemented; delayed pull, probe, and push checks passed. |
| R3 | Apply only the latest discovery result for the captured connection; ordinary discovery still works. | Implemented; connection switch and older-failure-after-newer-success checks passed. |
| R6 | Build one upload per filename, preserving the old loops' last-write metadata precedence (audio wins a shared record/audio name). No cross-push cache. | Implemented; deduplication, metadata, failed upload, and explicit retry checks passed. |
| R9 | Check existing server byte/count budgets before network upload, without truncating sources or changing the wire payload. | Implemented; exact/over-limit ASCII, multibyte, record-count and total-byte checks passed. Rejected input made zero HTTP requests. |
| R2 | **Revised proposal:** retain filenames and reject different bytes under an existing original's name. New files stage one at a time and roll back if the pull fails. No schema or attachment-ID migration. | Implemented; real temporary-file checks passed for collisions, identical sources, new sources, failed snapshot save, and backup preservation. |
| R4 | Remove the all-files-in-memory dictionary through R2's sequential staging. Do not replace HTTP transports without platform/cancellation tests. | Partial; no device peak-memory measurement or streaming-cap claim. |
| R7 | Moving persistence off the main actor changes ordering and publication semantics; no target-device evidence currently justifies that rewrite. | Deferred; current synchronous persistence retained. |
| R8 | Existing local mode is deliberately bounded; another adapter/queue is unnecessary without measured load. | Retained as-is; Postgres remains the existing scale-up option, not activated. |

R2 intentionally changes one unsafe outcome: a same-name/different-bytes pull now
stops with an explicit conflict instead of replacing an original referenced by the
active snapshot or backup. Resolve it by importing the changed original under a
new filename at its source, then syncing again. Identical existing files and new
files continue to work. Automatic conflict resolution was not added.

### Reproducible checks

Installed Swift 6.3.3 and the Windows Visual Studio C++ build prerequisites using
the [official Swift installation route](https://www.swift.org/install/windows/).
The Swift installer also installed its Python 3.10 dependency; the repository's
verification script was run with the existing Python 3.13 interpreter.

```powershell
python scripts/check_optimization_fixes.py
python scripts/check_code_structure.py
```

`check_optimization_fixes.py` compiles production Models, SymptomEntry,
LocalRepository, ProviderContracts, AppStore, Records/Sync/Providers extensions,
and ProviderClient in two focused executables. The state suite substitutes network
clients and, on Windows, Combine's observation wrapper. The provider suite runs
the actual ProviderClient with HTTP intercepted by URLProtocol; it substitutes
only the unrelated ServerClient constructor/filename helper to avoid CryptoKit.
Windows copies add FoundationNetworking imports. Production function bodies are
not rewritten. No live provider is contacted. Temporary test data is synthetic;
the server URL preference used by discovery is restored after successful runs.

These tests validate the changed logic, not SwiftUI observation delivery, real
endpoint/filename hashing, deployed-server compatibility, or an iPhone build.
The full native app and package suites still require the supported Apple toolchain.
The completed checkboxes below mean **implementation plus focused verification**,
not release approval or a guarantee that no regression is possible.

## Review method and limits

Applied the locally available Ponytail 4.9.0 `ponytail` and `ponytail-audit` skills
from the added `DietrichGebert/ponytail` marketplace. These are instruction-based
reviews, not an executable benchmark or automated vulnerability scanner.

Ponytail's simplicity pass favors existing code, native APIs, and the smallest
correct fix. Its audit excludes correctness and performance, so those findings
below come from a separate source review. The review covered the repository layout,
package dependencies, recent organization changes, and traced state, sync,
persistence, provider transport, and their relevant UI/test boundaries. It is not
an exhaustive correctness audit of every screen or a measured performance profile.

The newest changes organize and format existing behavior. Findings below apply to
the current code; they are not asserted to be regressions introduced by that commit.

| Check performed here | Result |
| --- | --- |
| `git pull --ff-only` | Initial pull updated `a29871e` to `1f1d90c`; refresh confirmed already up to date. |
| `python scripts/check_code_structure.py` | Passed: 71 production Swift files. |
| Python AST parsing of first-party `.py` files | Passed: 14 scripts, including the new verification runner; no script side effects during parsing. |
| Native toolchain | Swift 6.3.3 and swift-format installed; Xcode/iPhone SDK unavailable on Windows. |
| Focused compiled regression suites | Passed for R1/R2/R3/R5/R6/R9; state suite plus intercepted-HTTP provider suite. |
| Strict formatting | Passed for 86 Swift files on LF-normalized temporary copies. Raw Windows CRLF checkout triggers formatter whitespace diagnostics. |
| Live provider/database tests | Not run; no patient content or credentials sent to providers. |

R1/R2/R3/R6/R9 were reproduced in the focused Swift harness before fixing them;
none were reproduced on an iPhone here. Existing native test/build results in
[code organization verification](verification/code-organization.md) are historical
evidence and were not rerun here. Source line numbers below refer to `1f1d90c`.

## Ranked checklist

P1 means protect data or connection identity first. P2 means bounded-resource or
measurable performance work. P3 means optional work gated by an observed need.

| Done | ID | Priority | Problem | Smallest proposed fix |
| --- | --- | --- | --- | --- |
| [x] | R1 | P1 | In-flight sync can publish over newer local state or connection settings. | Captured generations reject stale completion. |
| [x] | R2 | P1 | Pull overwrites attachments before the snapshot commit succeeds. | Preserve existing files, reject byte conflicts, roll back new files on failure. |
| [x] | R3 | P1 | Service discovery can publish stale capabilities after settings change. | Bind discovery results to captured settings and the latest request. |
| [ ] | R4 | P2 | Pull retains every attachment in memory; several HTTP paths collect bodies before checking limits. | Stage bounded downloads and enforce byte limits during collection. |
| [x] | R5 | P2 | ID lookups sort full record/visit arrays unnecessarily. | Search the underlying snapshot arrays directly. |
| [x] | R6 | P2 | Every push uploads all referenced files, including repeated filenames. | Deduplicate within a push; cross-push caching remains deferred. |
| [x] | R9 | P2 | Valid imported text can exceed AI request budgets; preparation sends all readable records. | Check UTF-8 byte/count budgets before upload and explain how to reduce the request. |
| [ ] | R7 | P3 | Snapshot saves synchronously encode, validate, and write on the main actor. | Profile first; serialize expensive persistence off the UI actor if needed. |
| [ ] | R8 | P3 | Local server attachment operations rewrite the entire owner aggregate. | Keep for bounded demos; use the existing Postgres adapter for larger workloads. |

### R1 — Reject stale sync completion

**Evidence:** `apps/ios/Reva/State/AppStore+Sync.swift:24–73` awaits health and
transfers, then saves/publishes remote state and revisions without checking whether
local state or the selected connection changed. `SettingsView.swift:75` disables
only the developer controls during sync; connection fields, dismissal, and demo
reset remain usable. `AppStore.swift:88–119` permits mutations and reset during an
await. Provider operations have a separate busy flag and can overlap sync.

**Trigger and impact:** Start a slow pull, then restore the demo or edit a record
after dismissing Settings. Completion can overwrite those newer changes. Editing
the server URL/token during a request can also leave status/revision information
belonging to the old connection in the current UI.

**Proposed fix:** Add a small local state generation counter at successful mutation,
reset, and pull publication boundaries. Capture it and the URL/token identity at
sync entry. Before committing a pull, reject if either changed; before publishing
connection status/revisions, verify identity. A push should report that it uploaded
the captured snapshot if later local edits exist. Do not add an automatic merge
engine. UI disabling can supplement these checks but cannot replace them.

- [x] Delay a mocked pull, mutate local state, release the response, and assert the newer snapshot survives.
- [x] Change connection during push/probe/pull and assert old results cannot update the new connection's status/revision.
- [ ] Verify the actual Restore fictional demo UI while a pull is pending on an iPhone.
- [ ] Exercise overlapping provider save and sync; preserve both source checks and explicit conflict handling.

### R2 — Preserve attachment originals on failed pull

**Evidence:** `AppStore+Sync.swift:64–70` downloads into a dictionary, writes each
attachment, then saves the snapshot. `LocalRepository.swift:50–58` atomically
replaces a file at its existing filename. Atomicity applies to one file, not to the
whole pull. Server attachment identity is derived from filename in
`Core/ServerClient.swift:44–46`, so equal names can refer to different remote bytes.

**Trigger and impact:** A remote file has the same filename as a local source but
different bytes. If another attachment write or the final snapshot save fails,
the old snapshot remains active while one of its original files has changed.
The recovery checkpoint can reference that overwritten filename too.

**Implemented revision:** The original rename/remap proposal was rejected for this
pass because it changes filename-derived sync identities and complicates future
pushes. Preserve current filenames, compare downloaded bytes with existing local
or bundled originals, and stop on a conflict. Stage only new files and remove them
on unsuccessful completion. Commit the snapshot only after all files succeed and
R1's checks pass. Cleanup failure may leave an unreferenced file; it never justifies
overwriting or deleting an original.

- [x] Inject a download failure after one file is staged and a snapshot-save failure; verify originals/active state are unchanged and staged files are removed.
- [x] Pull different bytes under an existing filename; verify explicit rejection. Pull identical bytes and new filenames successfully.
- [x] Confirm the backup retains its previous snapshot and readable original bytes.

### R3 — Keep capability discovery tied to the requested connection

**Evidence:** `AppStore+Providers.swift:16–24` awaits discovery, assigns
`providerStatus`, and saves the then-current `connectionURL`. It captures no
identity and does not mark discovery busy. Settings clears flags on URL/token
change (`SettingsView.swift:89–96`), but an older response can repopulate them.

**Trigger and impact:** Check server A, switch to B before A responds. A's result
can label B as configured and enable controls based on the wrong service. Repeated
checks can finish out of order. Actual operation authorization still occurs on the
server; this finding does not assert that discovery bypasses it.

**Proposed fix:** Capture URL/token and a request generation when discovery starts.
Apply success or failure only if both still match. Save the captured URL on accepted
success. Disable duplicate discovery with a dedicated small state flag if useful;
avoid expanding the global provider busy flag into a new scheduler.

- [x] Release A's response after switching to B; A must not restore capability flags.
- [x] Complete two discovery requests out of order; the latest request remains authoritative even if the older request fails.

### R4 — Bound memory while receiving data

**Evidence:** `AppStore+Sync.swift:64–68` keeps all downloaded file bodies in a
dictionary. `ServerClient.swift:92` and `ProviderClient.swift:49` collect responses
with `data(for:)`. `VoiceTransport.swift:34` collects before the 4 MiB check at
line 85. `GeminiTransport.swift:39–40` does the same on FoundationNetworking,
although its Apple path already bounds streaming. Server owner attachments are
limited to 64 MiB/128 files in `server/Sources/RevaServer/Models.swift:127–128`.

**Impact:** A valid near-quota pull retains roughly the combined attachment payload
plus other app memory. Post-collection rejection does not cap peak memory for an
oversized response. No crash or timing threshold was measured here.

**Proposed fix:** Reuse R2's staging approach to process one bounded file at a time.
For network reads, apply endpoint-specific limits during collection using native
streaming/delegate APIs supported by each target. Reject oversized declared lengths
early, but also count actual bytes for chunked or misleading responses. Keep
redirect rejection, deadlines, cancellation, and no-retry behavior for calls.

**Partial implementation:** Sequential staging is in place and tested: a previous
file is on disk before the next mocked download is requested, and a failed later
download removes it. HTTP response collection itself is unchanged and still needs
the streaming tests below. No claim is made that total HTTP response memory is capped.

- [ ] Serve chunked responses beyond the limit with no Content-Length; verify early cancellation.
- [ ] Pull a synthetic near-quota dataset and measure peak memory on the target iPhone.
- [ ] Run transport tests on both Apple Foundation and the intended server platform.

### R5 — Remove sorting from identity lookup

**Ponytail tag:** `shrink` — remove unnecessary work at the shared lookup boundary.

**Evidence:** `AppStore.swift:67–79` sorts `records`/`visits`, then uses those
computed arrays for `record(id)`/`visit(id)`. Report rendering repeatedly invokes
record lookup for citations (`Features/Preparation/ReportView.swift:44,108,122`).

**Proposed replacement:**

```swift
func record(_ id: String) -> MedicalRecord? { snapshot?.records.first { $0.id == id } }
func visit(_ id: String) -> Visit? { snapshot?.visits.first { $0.id == id } }
```

Keep sorted projections for list presentation. Each lookup becomes a linear search
without a preceding sort. No cache, dictionary index, dependency, or new file is
needed. Add an index only if measurements still show lookup cost matters.

- [x] Verify existing IDs return the same values and absent IDs return nil.
- [x] Confirm record/visit list projections remain unchanged.

### R6 — Avoid repeated attachment upload within a push

**Ponytail tag:** `shrink` — use a local `Set<String>` rather than new sync machinery.

**Evidence:** `AppStore+Sync.swift:32–55` uploads sources in a record loop and audio
in a recording loop without deduplication. A filename referenced twice is uploaded
twice. Every new push also reuploads unchanged files. Each upload causes storage
and audit work in both backend adapters.

**Implemented fix:** Build a filename-to-content-type dictionary for the current
push and upload each entry once in sorted filename order. Later records override
earlier metadata and recording audio metadata wins, matching the previous loops'
final write. Missing-file failures still prevent snapshot publication.
Measure subsequent-push bandwidth before considering a server-verified
content hash/manifest. A local-only 'already uploaded' flag can be wrong after a
server reset or connection change and is not sufficient.

- [x] Multiple records and a recording sharing one source produce one upload with compatible final metadata and a valid snapshot push.
- [x] A failed upload prevents snapshot publication and a later explicit retry works.
- [ ] Measure unchanged second-push traffic before proposing a manifest protocol.

### R7 — Profile main-actor disk work before changing persistence

**Evidence:** `AppStore.swift:11,88–93` places synchronous repository saves on the
main actor. `LocalRepository.swift:36–47` validates/encodes the candidate, reads and
validates old JSON, and atomically writes backup and active state. Sync and
transcription also read attachment data from main-actor methods.

**Proposed fix:** Measure save and attachment-read latency at realistic dataset
sizes first. If UI stalls occur, move ordered persistence to a single owned worker
or actor and publish only after success. Do not wrap each save in an unrelated
detached task: writes could reorder and break the existing persistence invariant.
Keep validation, backup recovery, and failure-before-publication behavior.

- [ ] Profile save latency/UI responsiveness with synthetic large snapshots.
- [ ] If changed, verify rapid edits commit in order and failed writes never publish.

### R8 — Keep the local aggregate adapter within its intended scale

**Evidence:** `server/Sources/RevaServer/LocalFileStore.swift:40–70,109–128` reads and
rewrites one JSON owner document containing Base64 attachment bodies for attachment
mutations. The actor serializes work across owners. These limits are already
acknowledged in `server/README.md`; this is an optimization ceiling, not a newly
discovered correctness defect.

**Ponytail decision:** Keep the bounded local demo adapter. For larger or concurrent
use, configure and verify the existing `PostgresStore` before writing another
adapter, cache, or queue. Database deployment is a separate operational step and
was not performed in this review.

- [ ] Benchmark near-quota attachment updates and two-owner requests if local mode will serve that workload.
- [ ] Validate the existing Postgres adapter with the gated integration suite before relying on it.

### R9 — Check AI request budgets before uploading source text

**Evidence:** `Device/DocumentImportService.swift:75` permits 200,000 extracted
characters. `Core/ProviderClient.swift:70–116` encodes summary and preparation
requests without checking their text budgets. `State/AppStore+AI.swift:42–50`
selects every record with nonempty text. In contrast,
`server/Sources/RevaServer/Providers/GeminiModels.swift:18,54,66,75–77` permits
120,000 UTF-8 bytes per source, 100 preparation records, and 500,000 combined
source-text/summary bytes. The server also enforces field-specific byte limits.

**Trigger and impact:** A 150,000-character ASCII document is within the importer's
extraction budget but exceeds the summary endpoint's source-text budget. Five
110,000-byte source texts exceed the preparation total even with empty summaries.
Multibyte text can exceed a byte limit with fewer characters. The client uploads
requests that the server must reject, and the preparation UI offers no request
budget selection at this boundary. The server validates before its Gemini request,
so this does not assert a paid model call occurs for rejected input.

**Proposed fix:** Add a small pure validation helper at the provider request boundary
using `utf8.count` and record counts, matching the server contract. Reject before
network transmission and identify which source/limit needs attention. Preserve
the full imported document and existing server validation. Offer explicit local
preparation or a reviewed smaller source set; do not silently truncate text,
drop pinned sources, or add automatic chunking/model calls in this first fix.
Keep the byte contract documented and use matching boundary cases in client and
server tests rather than introducing a cross-package configuration framework.

- [x] Test exactly 120,000 and 120,001 source bytes, including multibyte text.
- [x] Test 100/101 preparation candidates and 500,000/500,001 aggregate bytes.
- [x] Verify rejected requests perform no HTTP upload; original fixture values remain untouched and the client performs no persistence.
- [ ] Verify any later source-selection UI preserves pinned sources or explicitly explains why the request cannot fit.

## Keep as-is / avoid speculative rewrites

- Keep the recent focused screen files, purpose comments, and MARK sections. They
  implement the documented project organization requirement; file count alone is
  not evidence of waste.
- Keep `RevaStore`: it has both local and Postgres implementations plus test value.
- Keep injectable provider transports: they support provider-free failure tests.
- Keep server dependencies for the implemented HTTP/database paths. No removable
  dependency was established by this review.
- Keep source validation, durable call receipts, no automatic call retry, review
  steps, and compare-and-swap checks. Shorter code must not remove these safeguards.
- Do not add Redis, an ORM, a generic repository layer, or a new state framework
  for the findings above.

Net: no defensible line-deletion estimate; 0 dependencies identified for removal.
The two Ponytail simplifications remove repeated work with little or no code-size
change. The data-protection proposals require small additional checks and staging.

## Suggested implementation order and completion gate

1. R1 and R3: capture identities/generations and add delayed-response tests.
2. R2 with R4: stage bounded downloads and verify failure recovery.
3. R5, R6, and R9: make the small lookup/upload changes and add AI budget preflight.
4. Measure R7/R8; implement only if the intended workload justifies it.

The root Swift package tests `Core`, not `State/AppStore`. The new standalone
`Tests/OptimizationChecks` harness compiles the selected State sources directly
with mock network clients and an injected temporary LocalRepository. The harness
uses Combine when available; its macOS execution and native target/UI verification
have not been performed in this pass.

- [x] Run the implemented behavioral checks with Swift 6.3.3 on Windows.
- [ ] Run `swift test -j 6` and `swift test --package-path server -j 6`.
- [x] Run strict formatting on LF-normalized copies and the production structure check from [the coding standard](coding-standard.md).
- [ ] Build the iPhone target; interactively verify pull, reset, connection changes, and attachment recovery.
- [x] Update this checklist with actual focused results and explicit remaining limits. No performance measurements are claimed.

Focused verification is complete for the six checked items. Full Apple-platform
build/UI checks and the remaining R4/R7/R8 work are still open. See Git history for
the implementation checkpoint; no provider activation or deployment is included.
