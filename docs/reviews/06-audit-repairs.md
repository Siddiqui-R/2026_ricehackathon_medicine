# Reva audit repair log

## Scope

User authorization: fix all 23 confirmed audit findings using simultaneous Astra agents at xhigh effort, with precise changes and no unnecessary expansion. Baseline: `98261b86cb7f87920972873775074d34bfaaade4`. The [audit report](../audits/fable-20260912-114322/FINAL-REPORT.md) remains historical evidence of the frozen defects; this log records their repair and verification.

Unfinished account/Tiger work in the shared checkout is preserved separately. Repair branches start from the published baseline, and overlapping changes are reconciled explicitly. This work does not complete or release that unrelated account implementation.

## Parallel ownership

| Branch | Owner | Assigned findings |
| --- | --- | --- |
| `fix/audit-native-20260912` | Astra, xhigh | 10-001, 03-001, 04-001, 04-005, 05-001, 05-002, 05-008, 04-004 |
| `fix/audit-evidence-20260912` | Astra, xhigh | 02-002, 02-005, 02-004, 02-006, 05-004, 07-001, 04-006, 04-007, 04-008 |
| `fix/audit-browser-20260912` | Astra, xhigh | 08-001, 07-002, 14-001, 14-002, 16-001, 16-002 |
| `fix/audit-integration-20260912` | Coordinator | Independent review, integration, generated project membership, combined checks, WIP reconciliation and delivery |

The native owner controls shared AppStore methods and recording lifecycle. The evidence owner controls native/browser domain rules and extraction. The browser owner controls its editors, original-attachment transaction, accessible navigation and deployment/build instructions. Shared call-site/API changes are coordinated before integration.

## Checkpoints

- Created four isolated worktrees from the published baseline. The original audit worktree remains unchanged.
- Preserved a local binary patch and first-party untracked-file backup of the shared checkout before repairs; ignored credentials and local Claude workflow state are untouched.
- Reused separate filesystem clones of the audit's browser dependencies after verifying identical lockfiles. No dependency upgrade is part of these repairs.
- Agents make focused commits; the coordinator reviews and integrates them before the final test pass.

## Verification policy

Data-loss, async identity, extraction and CAS fixes require meaningful production-logic regression checks. Small palette/label changes receive targeted source/UI verification. The coordinator runs the combined native/browser builds and relevant suites after integration, avoiding competing global builds. Existing live user services are preserved.

Final results, commit references and any remaining device/live-service verification limits will be recorded below and in the per-finding status sheet.
