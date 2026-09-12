# Validator 19 — independent adjudication of tracks 07–13

**Codex continuation after the user reported Claude account limits.** This is not Fable execution. Model and effort were inherited from the coordinator. The coordinator assigned tracks 07–13 to this validator; findings 14–16 authored by this agent were excluded and assigned to validator 18. No application source, Git state, configuration, credentials, ports or UI controls were changed, and no build, test or live provider call was run by this validator.

The source of truth is `fable-audit-20260912-114322 @ cfe0997+wip`, frozen at `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`, base commit `cfe09971443989396b8ef6a14cdf935adba86ddd`. Source paths and line numbers below and in the JSON refer to that frozen tree. Evidence paths refer to this audit directory. Later account, Docker and Tiger work remains an uncaptured or unfinished delta rather than a delivered defect.

## Dispositions

All **13 findings** supplied by tracks 07–13 have one disposition in `19-dispositions.json`: **4 confirmed defects** (3 P2, 1 P3), **3 evidence gaps** (1 P2, 2 P3), and **6 suggestions** (all P3). Tracks 09 and 12 supplied empty finding arrays; this does not imply exhaustive behavioral verification. No P0 or P1 finding is confirmed in this subset.

| ID | Disposition | Priority | Validated scope |
| --- | --- | --- | --- |
| RVA-07-001 | Confirmed | P2 | Mixed PDF header causes scanned body to bypass OCR without incomplete warning. Source proof; original remains available. |
| RVA-07-002 | Confirmed; lowered | P3 | Each failed import retry can retain another unreferenced original key. Storage/quota cost not measured. |
| RVA-08-001 | Confirmed | P2 | Open notes editor can clear questions generated after it opened because its baseline follows live props. |
| RVA-10-001 | Confirmed | P2 | Suspended native provider results can publish after identity/workspace changes; controlled transport reproduction supports two paths. |
| RVA-10-002 | Evidence gap | P3 | Mocked structural checks do not establish actual model semantic fidelity or hostile-document behavior. |
| RVA-10-003 | Suggestion | P3 | Some transport byte caps are checked after collection; no memory failure was observed. |
| RVA-11-001 | Suggestion; lowered | P3 | Preserve the documented persistent call-receipt directory when deployment work proceeds. |
| RVA-11-002 | Suggestion | P3 | An uncertain native call can show a blank Conversation line. |
| RVA-11-003 | Suggestion | P3 | Silent busy return is a latent API clarity issue; reachable current UI failure not established. |
| RVA-11-004 | Suggestion | P3 | Carry reviewed consent/name explicitly through the boundary; current UI already gates consent. |
| RVA-11-005 | Evidence gap; narrowed | P3 | Full native booking journey remains unexecuted; new poll and startup-repair failure evidence partially fills the original gap. |
| RVA-11-006 | Suggestion | P3 | Focused missing provider guard cases; existing call transcript truncation is already tested. |
| RVA-13-001 | Evidence gap | P2 | Successful real PostgreSQL migration/persistence was not run; additional concurrency/deployment checks also remain. |

## Consequential confirmed mechanisms

**RVA-10-001:** `AppStore.swift:25–49` advances connection generation, but `AppStore+AI.swift:12–30` only checks record text/version and `AppStore+LiveCalls.swift:48–61` writes the current booking by ID after awaiting. Settings permits connection edits and sync while a provider operation is active. The coordinator's `evidence/codex-takeover/ProviderContextRepro.swift` compiles unchanged production state code with a controlled provider double. I inspected its assertions and successful `provider-context-repro.txt` (compiler exit 0, run exit 0), then independently SHA-256 compared all 13 production inputs with the frozen source and `snapshot-manifest.json`; all matched.

The harness confirms a summary begun under A saving after the token switches to B, and an A call transcript saving into a replacement B snapshot with the same stable booking ID. The replacement uses production mutation directly; it does not execute a real sync pull. Real transport authentication, live providers, login UI and timing were not tested. This is a client publication defect, not proof of a server authorization bypass or duplicate call. Shared IDs are an explicit precondition for the second result. Source shows analogous missing guards elsewhere; only the named summary and poll paths were reproduced for this finding. Compiler cache warnings did not change either successful exit; the earlier failed attempt is preserved separately.

**RVA-08-001:** `VisitBrief.tsx:196–201` permits the editor to open during first preparation and keeps the same editor mounted when its visit prop advances. `209–210` retains the original form values, but `221–224` compares against the updated prop, so `228–235` can replace generated questions with the untouched original empty field. The same-store publication path is explicit in `core/store.ts:304–316`. This was independently source-validated; no DOM-level race reproduction is claimed. A stable opening baseline and changed-field merge already exist in the separate `visitEdits.ts:64–87` helper.

**RVA-07-001:** `extractDocument.ts:289` makes character count the sole gate to raster OCR. A sufficiently long embedded header bypasses the body image entirely. Nonempty text avoids the empty-page flag at `308–311` and OCR warning at `362–372`; `ImportDialog.tsx:142` then permits ready status after review. The original is retained, limiting severity. Synthetic mixed-PDF execution remains absent. Native RVA-05-004 shares the mechanism but retains its own ID because it needs a different source fix and regression check.

**RVA-07-002:** `ImportDialog.tsx:125–147` commits an original under a fresh UUID before publishing its record; its catch at `152–159` neither removes nor reuses the key. `repository.ts:177–185` confirms a separate committed transaction. Another tab advancing CAS can make the later snapshot publication fail repeatedly. This proves logically unreachable attachment keys from failed attempts, not physical duplication, quota exhaustion or an outage; priority is P3. It is separate from the documented server attachment staging tradeoff in RVA-06-001. Validator 18/reviewer 07 agreed with this narrowed scope.

## Claims that must remain limited

- **Calls and consent:** Receipt storage is deliberately local even with PostgreSQL snapshots. `server/README.md:98,100` explicitly requires persistence across redeploys. Discarding that directory is a deployment precondition failure, not evidence that completed restart protection is broken. An absolute path alone cannot guarantee persistent storage. Current native and browser flows do not resubmit the old request ID; server replay rejects differing input. The current native editor requires consent, so a literal `true` in its downstream payload is not evidence of a reachable consent bypass.
- **Coverage:** The original RVA-11-005 statement that only compile evidence existed is superseded in part. The coordinator harness now exercises native polling and a startup-repair failure path. It still does not cover the complete simulation, normal repair, call submission/uncertainty UI or native journey. The saved browser UI matrix covers browser presentation, not these native transitions. Existing voice tests at `VoiceProviderTests.swift:412–442` already verify bounded call transcript truncation; proposed additional transcription bounds tests concern a different path.
- **Models and database:** Gemini validation establishes shape, source-ID constraints and safe failures, not clinical entailment. Real model fidelity remains unexecuted. PostgreSQL's dedicated test is gated at `PostgresIntegrationTests.swift:15`; source and unreachable-DB failure evidence do not establish a successful database run. Its present body covers basic migration replay, CAS, ownership, bytes and tombstones, while concurrent quotas, restart durability and deployment TLS require additional checks.

## Evidence and scope controls

I independently read the relevant frozen branches, all 07–13 findings, runner summary/raw logs and the coordinator reproduction source/output. Existing shared evidence supplies browser unit tests, local/mocked server tests, native compile results and UI captures; these are attributed to their runners and are not new executions by this validator. No missing evidence was converted into a deployment failure, no physical storage or performance numbers were invented, and no unfinished account functionality was counted as delivered. No duplicate IDs were created or self-authored tracks 14–16 adjudicated. The machine-readable dispositions include precise triggers, impacts and evidence for every supplied finding.
