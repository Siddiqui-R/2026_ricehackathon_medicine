# Track 09 — Server routes and file storage

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip` (frozen worktree, not the active accounts implementation).

Reviewer: Codex continuation, explicitly authorized after the user reported Claude limits exhausted. This report is new Codex source review; it does not claim Fable execution or repeat the evidence runner's tests. Source files were read only. No builds, UI, ports, provider calls, credentials, database or Git operations were performed by this reviewer.

Evidence reused: `reports/17-evidence-runner.md`, `evidence/runner1-summary.json`, `evidence/commands.jsonl`. Stage 1 reports 31 server tests passed with the dedicated PostgreSQL test skipped; real local HTTP smoke, provider-route negative tests, native HTTP round trip, optimization harness and builds passed. Where raw log files are absent from the delivered audit directory, the runner report is the available record; these are runner-reported results, not this reviewer's new executions.

## Conclusion

No new actionable defect was established in the captured server route/local-store implementation. Owner selection comes from the authenticated bearer mapping; snapshot profile fields do not select storage identity. The separate attachment upload/snapshot CAS tradeoff is already recorded in `RVA-03-004` and should not become a duplicate finding here. New accounts/CORS/session support is WIP and belongs to track12.

## Inventory and source review

All assigned production files were reviewed: `server/Sources/RevaServer/Configuration.swift` (127 lines), `HTTP.swift` (179), `Models.swift` (212), `LocalFileStore.swift` (156), `Deadline.swift` (53). Consulted `server/Sources/Run/EntryPoint.swift` for assembly, provider route files for group authentication, and `ServerTests.swift`/`PostgresIntegrationTests.swift`/provider test suites for evidence coverage.

- `Configuration.swift:43-66` validates explicit private token/owner mappings and restricts public demo identity to loopback local mode. Invalid token headers fail in `HTTP.swift:16-25`; all `/v1` groups originate at line104. `/health` returns only storage/demo health.
- `HTTP.swift:43-81` maps expected failures, suppresses raw storage errors and applies `no-store`/`nosniff`. DTO decoding errors are converted to safe fixed reasons. Attachments permit only safe ID/flat ASCII filename/MIME and 16 MiB original data (`Models.swift:182-210`), with no request-controlled filesystem directory. Body limits are explicit per route.
- `Models.swift:144-178` intentionally validates structural envelopes (version1, nonempty profile, four arrays <=5000 objects, depth32, 4 MiB serialized size), not every clinical field. Both clients own detailed medical semantics. Generic Codable JSON preserves unknown optional fields and integers; do not label this documented boundary as missing clinical schema enforcement.
- `LocalFileStore.swift:40-49` refuses corrupt/oversized/incompatible persisted aggregates; it does not silently replace corrupt content. A missing owner is a new owner, distinct from a tombstone document. Actor isolation and nonblocking directory flock serialize process/actor writers (18,139-155). Snapshot revisions monotonically increase and deletes retain revisions (83-105).
- `LocalFileStore.swift:52-74` writes a 0600 temp file, synchronizes its contents, closes it, then renames. After the rename no fallible operation can report a false uncommitted result. Tests exercise process/store restart, not abrupt host power loss; directory-entry fsync is not present here, unlike the call receipt store. Do not promote ordinary restart evidence into a power-loss guarantee.
- Attachment quota mutation is serial with the original write; overwrite consumes no extra slot (109-121). The 64 MiB/128 original bound is consistent with the <=100 MiB on-disk aggregate read allowance after base64 overhead. Same-owner attachment mutations remain separate commits from snapshot CAS by design.
- `Deadline.swift:13-22` provides a cooperative 20-second database deadline; the underlying work must honor cancellation, as its header correctly states. `EntryPoint` applies it to migration and all DB operations via BoundedStore, with no local fallback. Blocking filesystem operations are local prototype scope; no hard real-time/disk-time guarantee was proved.

## Checklist dispositions

| ID | Disposition | Evidence and limit |
|---|---|---|
| G01 | Pass for captured static-token routes; account sessions WIP | HTTP:16-25,104 and every owner lookup; runner r1-13/r1-15 owner isolation/auth. Expiring sessions are not in this snapshot. |
| G02 | Pass for route/input/error bounds; provider collection limit qualified | HTTP/Models limits and malformed-input tests; r1-12/r1-13. Provider post-collection memory hardening is RVA-10-003; cooperative deadlines are not hard process deadlines. |
| G03 | Pass for tested local persistence/restart/CAS/tombstones | LocalFileStore and r1-12/r1-13; power-loss and injected disk failures remain unverified. |
| F04 | Pass at server CAS boundary | HTTP:50-53 and LocalFileStore:83-105; existing native provider identity defect candidate RVA-10-001 is a client publication issue. |
| F05 | Pass for owner scopes/bytes/quotas; documented separate-commit risk | LocalFileStore:109-133; r1-12/r1-13. Deduplicate server overwrite tradeoff to RVA-03-004. |
| L03 | Pass for API side; full proxy disposition delegated track16 | r1-08 reports 7 production-wrapper tests. This track inspected HTTP side; it did not repeat proxy implementation review. |

## Evidence requests

None is necessary to establish an additional local-store defect. Keep missing power-loss/disk-fault evidence explicit. The runner's existing local HTTP tests cover the present scope; PostgreSQL success remains track13's gap.
