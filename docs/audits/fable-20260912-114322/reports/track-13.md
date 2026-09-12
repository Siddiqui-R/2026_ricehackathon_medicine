# Track 13 — Tiger PostgreSQL and identity persistence

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip`, the frozen cfe0997 source plus captured WIP.

Reviewer: Codex continuation after explicit user authorization following Claude usage exhaustion. Read-only source review; no builds, UI, live calls, credentials, database or Git operations by this reviewer. Reused the shared Stage1 runner report; its model/transport tests are mocks and are not live provider validation.

## Conclusion

The existing PostgreSQL adapter has coherent owner-locked transaction and migration structure under source review. **Successful real-database execution remains unverified (RVA-13-001)**. Account repositories/migration002/Tiger provisioning/Docker are WIP outside this snapshot. No current database implementation defect was established; the absence of future accounts code is not counted as one.

## Inventory and source proof

Reviewed full `server/Sources/RevaServer/PostgresStore.swift` (211 lines), `Migrations/001_snapshot.sql` (54), `Configuration.swift`, `Deadline.swift`, `server/Sources/Run/EntryPoint.swift`, `server/Tests/RevaServerTests/PostgresIntegrationTests.swift` and relevant `ServerTests.swift` configuration cases. Frozen accounts contract was read as a delta checklist.

- `Configuration.swift:71-117` validates PostgreSQL URL components, rejects unsupported query options and requires verified TLS except explicitly enabled loopback insecure tests. `sslmode=require` maps to the same system-trust TLS configuration as `verify-full`; it is not an insecure-TLS bypass. Maximum connections4, connect timeout5s and statement timeout15s are explicit.
- Migration001 is bundled, loaded from known application resources, and applied in an advisory-locked transaction; dynamic request data never constructs migration SQL (`PostgresStore:27-65`). The current maximum-version check intentionally refuses a database newer than version1. The planned ordered migration002 runner must be assessed after it exists, not reported as broken today.
- Runtime interpolation is PostgresNIO bind parameters; unsafeSQL is used only for checked-in migration statements. Read paths include owner predicates (69-75,140-145). Attachments have composite owner+ID primary keys and FK cleanup, audit rows are owner-scoped. `Validation.safeID` and SQL owner constraints agree.
- Every mutating transaction creates/locks one owner row before revision/quota checks (165-189), preventing concurrent same-owner oversubscription and lost CAS writes. Snapshot writes advance revisions, snapshot deletion clears attachments and retains monotonic tombstones. Attachment replacements/deletes are independent commits by design; reuse RVA-03-004 for the same-name/different-bytes risk instead of duplicating it.
- JSONB stores the complete aggregate, retaining profile/symptom/provider/audio fields without a brittle table mirror. Codable integer handling protects revisions; existing client round-trip evidence is local, not PostgreSQL. PostgreSQL's JSON text normalization is expected; original attachment BYTEA is separate and must remain byte-identical.
- `EntryPoint` starts client.run, gates listener startup on bounded migration, wraps subsequent DB access in BoundedStore, and cancels/shuts down on failures. Runner's unreachable-DB test verified nonzero exit in about20s, sanitized output and no local fallback. It does not establish successful TLS or migrations against a live database.
- SQL mutation metadata is limited to the newest128 entries per owner, with no patient prose in audit entries (`PostgresStore:198-209`, migration001:44-54). This is an implementation bound, not a compliance claim.

## Checklist dispositions

| ID | Disposition | Evidence and limitation |
|---|---|---|
| G04 | Unverified real execution; source-reviewed design Pass | RVA-13-001; Stage1 r1-12 skip, r1-14 failure-path pass. No live Tiger. |
| G08 | WIP | Account migration/repositories/joined deletion not in frozen source. |
| F03 | Unverified PostgreSQL round trip; local transport Pass elsewhere | Generic JSON/BYTEA source path coherent; dedicated DB gate not run. |
| F04 | Unverified DB concurrency execution; source CAS/locking Pass | Owner transaction row lock+bound writes; future account stale identity requires delta review. |
| F05 | Unverified DB bytes/quota execution; source owner/transaction constraints Pass | Attachment owner key, transactional quota, BYTEA and FK; separate-upload risk deduplicated to RVA-03-004. |
| G01 | Pass source owner predicates/static mapping; account identity WIP | HTTP trusted owner then SQL bound owner, no caller-selected namespace. DB behavioral isolation not executed. |

## Evidence requests

**ER-13-1 / RVA-13-001:** If the coordinator has a disposable local PostgreSQL runtime available, run the existing opt-in test with synthetic credentials and record schema version, migration replay, exact data/bytes, CAS/tombstones and cleanup. Add a narrow same-owner concurrency/quota test only if required to resolve a specific doubt. Otherwise retain Unverified without touching live Tiger or provisioning infrastructure.

Future account delta: capture migration002 plus repositories/configuration/auth together; verify both local and PostgreSQL delete-user/session changes atomically preserve intended ownership behavior. Live Tiger deployment, certificate trust and production account access need their own evidence.
