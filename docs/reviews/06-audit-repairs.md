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

## Repair result

All **23 confirmed findings (14 P2, 9 P3)** have code repairs. The [per-finding checklist](audit-repair-status.csv) records their commits, executed checks and remaining verification limits. The original 74-item audit remains unchanged: this repair pass does not silently close its unverified candidates, manual gates or unrelated work in progress.

- [Native evidence](evidence/native-audit-repairs.md): asynchronous identity, field-specific editor merges, startup recovery, visit ordering, busy feedback and recording recovery.
- [Extraction evidence](evidence/extraction-audit-repairs.md): exact source passages, omission metadata, demo-wrapper boundaries, relevance/date logic, mixed PDFs, scan classification and palette.
- [Browser evidence](evidence/browser-audit-repairs.md): atomic record/original commits, concurrent brief editing, tablet accessible names, selection contrast and deployment/build configuration.

No dependency upgrade, new paid service, broad backend rewrite or account release is included. Older report citations without omission metadata request regeneration. The consolidated `source-rules-v2` signature also invalidates briefs generated with the old selection rules, including those with no citations; both clients use the same verified vectors.

## Combined verification

The integrated production code at `1f4b50e` passed the following checks; later checkpoints add evidence documents, the real-wire assertion and the user's queued UI feedback.

| Check | Observed result |
| --- | --- |
| Root `swift test -j 4` | 52 discovered, 51 passed, 1 opt-in localhost test skipped; zero failures |
| Native repair harness | All eight assigned findings; 60 stale-response cases plus normal controls; editor/save/audio recovery assertions passed |
| Optimization harness | Six groups passed; unchanged retry required system temporary-directory access |
| PDFKit/Vision harness | Real mixed header/raster extraction and the ten-page OCR cap passed |
| Browser typecheck, full tests, production build | Passed; 11 test files / 97 tests; 1,925 bundled modules with no build warning |
| Browser static-host tests | Seven passed |
| Browser build assets | All 15 native resource files byte-identical in built demo; local OCR worker/model/WASM present; temporary UI fixtures absent |
| Native Xcode build | Generic iOS Simulator, arm64 and x86_64, signing disabled: BUILD SUCCEEDED |
| Backend and real native client | Fresh backend build; localhost test passed separately, including full snapshots, new `excerptOmitted: true`, nine original files, auth, owner isolation, stale revisions and deletion tombstones |
| Structure / formatting | 71 Swift and 55 browser sources satisfy contracts/sections; 20 changed native Swift files and browser Prettier passed |

The backend's initially copied module cache rejected its old absolute worktree path. Removing only that integration-worktree cache and rebuilding resolved it. The Xcode build's App Intents metadata warning reflects the absence of an AppIntents framework dependency; it was not a compiler failure. Original user services were left running; the real-wire test owned and removed its temporary server/data.

Computer verification used the actual rendered browser editor at a measured 768-pixel viewport with controlled persistence/provider transport. It confirmed late generated questions survive notes-only edits, conflicting notes reject the entire save, all six rail actions retain accessible names, and selected text has 8.124:1 contrast. This pass did not verify other browser engines, physical microphone/camera behavior, real codec interruptions, a newly rendered UIKit PDF, hosted Vercel settings or paid providers. Browser OCR tests use real PDF.js with controlled recognition; native printed-text OCR was executed with real Vision. These results do not promise perfect OCR.

Local raw test logs are under `/private/tmp/reva-integrated-repair-checks` and the agent-specific `/private/tmp/reva-*` paths; the durable evidence is summarized in the versioned documents above.

## Stack and collaboration after repairs

The product architecture remains the [as-built stack](../architecture.md). The diagram below shows where the repaired boundaries sit. External adapters require configuration; this repair pass did not activate their services.

```mermaid
flowchart TB
  subgraph Native["iPhone · SwiftUI / feature modules"]
    NS["AppStore · workspace and connection generations"]
    NC["Codable domain · exact excerpts and citations"]
    NL["Atomic local snapshot + original files"]
    ND["PDFKit / Vision / VisionKit / AVFoundation / PDF export"]
    NS --> NC
    NS --> NL
    NS --> ND
  end
  subgraph Browser["Browser · React / TypeScript / Vite"]
    WS["RevaStore · serialized edits and stable editor baselines"]
    WC["Shared JSON contract · source versions and omission flags"]
    WL["IndexedDB · snapshot + original in one transaction"]
    WD["PDF.js / bounded Tesseract / MediaRecorder / print"]
    WS --> WC
    WS --> WL
    WS --> WD
  end
  V["Vercel root config · static web output and exact entry routes"] --> Browser
  NS -->|"URLSession / explicit sync and provider actions"| API
  WS -->|"Same-origin fetch / configured API routing"| API
  subgraph Backend["Swift / Vapor · authenticated owner boundaries"]
    API["State / originals / provider routes"]
    DB["LocalFileStore or PostgreSQL / revisions"]
    P["Validated provider adapters and durable call receipts"]
    API --> DB
    API --> P
  end
  DB -.-> Tiger["Tiger Data PostgreSQL"]
  P -.-> Gemini["Gemini · summaries and pre-visit preparation"]
  P -.-> Whisper["OpenAI Whisper · transcription"]
  P -.-> Calls["ElevenLabs / Twilio · calling"]
```

Three Astra agents at xhigh owned separate native, extraction and browser branches. A fourth worktree integrated their focused checkpoints and cross-reviews. Review caught an additional late audio callback that replaced terminal recovery guidance; its regression fails against the previous implementation and passes with the final guard. The separate worktrees remain available for targeted review; the frozen audit source was never edited.

## Shared checkout preservation and follow-ups

Before integration, a local backup captured the newest **59 tracked edits and 24 first-party untracked files**, including account/Tiger work and the user's separate demo/review-removal and native-tab changes. The backup is `/private/tmp/reva-before-integration-latest-20260912`; recovery stash `069e18c222d1c5da0c88ca7735c92dd157a1b93b` is retained. An earlier pre-repair backup also remains. Credentials, ignored files and `.claude` workflow state were excluded from stash operations and left untouched.

Main was fast-forwarded to repair checkpoint `9eeba19`, then the exact stash was applied. Overlaps are reconciled explicitly, preserving newer user intent while retaining the audited data-integrity repairs. The duplicate untracked `apps/web/vercel.json` is removed in favor of the root configuration; its prior contents remain backed up. Restored feature work stays uncommitted and is not silently included in the repair release.

The five annotated browser requests were subsequently authorized for immediate implementation and are completed in [UI follow-ups](../ui-todo.md): slogan, display-label cleanup, preparation action placement, profile subtitle and isolated demo-person switching.

## Concurrent remote checkpoint

Before pushing, the remote was found at `36c055d`, an independent Windows implementation of the same audit repairs published during this batch. Three owners compared that commit against the native/browser implementation already verified here. Both histories are retained, with one implementation per responsibility.

The comparison identified useful additions to carry forward: preserving an untouched questions array exactly, naming the tablet avatar link, regenerating unsafe legacy local summaries before AI input, granular native editor conflict/convergence checks and kind editing, sharing finalized audio when persistence cannot recover, prioritizing low-text OCR candidates, explicit incomplete coverage when browser PDF inspection fails, and invalidating older selection rules consistently across clients. Windows LF rules, dependency-directory ignores, the junction-based confinement fixture and the equality-only hash double for Windows state checks are also retained.

The consolidated implementation keeps the stricter fixture-footer/append preservation, omission metadata, legacy demo-summary classification, precise stopped-recorder guidance, real PDFKit/Vision regression and real rendered-browser checks developed in this batch. Duplicate excerpt/audio helper types and a second browser DOM test framework are not introduced. The [Windows checkpoint reference](../audit-repair-checklist.md) preserves its original evidence and test totals without presenting them as new results for this tree.

## Final focused gate

After consolidation, native regressions passed 72 stale-response cases, six cancellation paths, safe provider-input policies, field conflicts/convergence, and repeated audio-save failure retention. Source/fixture checks passed with real Swift `source-rules-v2` vectors; the real PDFKit/Vision fixture verified late-scan priority, numeric disagreements and the OCR cap. The consolidated iOS Simulator build passed. Browser production build passed with 1,928 modules. Existing browser checks passed apart from an initial new demo fixture page-count error; correcting its metadata made both targeted demo isolation/navigation tests pass.

Computer UI checks confirmed the exact slogan, cleaned profile/clinician labels, the action inside `.appointment-focus`, the removed profile subtitle, and switching Jordan → Maya → Alex. Actual measured widths of 774 and 390 pixels matched document scroll widths, with accessible switching on the compact rail and phone header. The temporary tab was closed, viewport reset and preview stopped. Demo database tests verified that switching/reopening and resetting one person retain other people's edits and original attachments. No further broad audit was run.

The final shared-checkout reconciliation preserved the account/Tiger, demo-review-removal and tab work as uncommitted changes. Focused compatibility checks passed: 55 browser tests across affected account/store/domain/demo boundaries, six native fixture checks, the 72-case native harness, and the browser production build. Actual Swift vectors were regenerated for the preserved local seed. Computer confirmed the existing port 4173 preview keeps the chosen demo when redirecting an old root bookmark to `/demo`. Recovery stash `89fac9f0fe2b9f8eee09762fa8c44b7c62219871` and backup `/private/tmp/reva-reconciled-wip-before-remote-20260912` remain local. Commit `658173b` contains the consolidated fixes and UI changes; `d316251` retains both repair histories.
