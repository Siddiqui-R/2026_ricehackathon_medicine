# Validator 18 — Independent data, functionality and quality adjudication

Author: Codex continuation (`/root/audit_browser_finish`), 2026-09-12. User explicitly requested takeover after Claude exhausted its limits. Audited **fable-audit-20260912-114322 @ cfe0997+wip** only. The frozen current-spec addendum determines scope; later account/Tiger application changes were not mixed into these findings.

Independently adjudicated **all 64 findings** from original Fable tracks **01–06** and Codex tracks **14–16**. Track15 supplied an empty findings list with measurement limitations. I did **not** independently validate my own07/08 reports; those belong to the other validator. Per-finding status, rationale, exact source/evidence references and duplicate mapping are in `18-dispositions.json`. Original reviewer files remain unchanged.

## Outcome and priority

22 entries are confirmed (19 canonical after duplicates), 30 suggestions, 3 evidence gaps, 3 WIP items, 3 candidates and 3 rejected/closed claims. Confirmed means source proof unless expressly backed by saved runtime logs; it does not imply every issue was reproduced on an iPhone or against a live provider. No P0/P1 issue survives this validator's assigned scope. Cross-track server/provider/security issues remain the other validator's responsibility.

The strongest canonical P2 issues are:

- Native record edits can erase a newly arrived AI summary (04-005, **record arm only**) and recording notes can erase a newly arrived transcript (05-001).
- A startup repair write failure hides an already loaded valid snapshot and offers fictional reset as the only recovery control (03-001).
- Native raw-string date sorting can show the wrong next visit when offset and UTC strings mix (04-001).
- Mixed-page native OCR skips the raster body after a short text header (05-004); compare the separately validated browser counterpart07-001 before grouping the repair.
- Failed native audio finalization leaves a contradictory paused/dead-end state (05-002); successful finalization followed by metadata failure has no save retry path (05-008).
- Arbitrary excerpt truncation can display partial numeric/unit content (02-002); fixture-marker stripping also applies to non-demo documents (02-005).
- Tablet browser icon navigation loses its accessible text names (14-001).
- Captured Vercel guidance selects two incompatible configuration roots (16-001); a specific hosted404 is **not** established by this audit.

The clean browser typecheck/test prerequisite failure is independently corroborated from saved Fable logs (16-002, P3). The production build passes because prebuild generates assets; standalone checks in a clean checkout can fail until that preparation happens.

## Corrections, rejected claims and deduplication

- **05-005 rejected as written:** `AVAudioPlayer(contentsOf:)` exceptions flow through catch unchanged (`AudioServices.swift:400,417-420`). The reviewer incorrectly said all unsupported-codec errors map to the app's missing/damaged message. Unsupported codec/device playback remains unverified, not disproven.
- **03-007 closed:** fresh Fable runner logs do exist and pass all six optimization groups plus the real isolated native-client/local-Vapor round trip. A reviewer running before those logs existed could not know that; final coverage must use the later evidence.
- **02-001 downgraded:** an explicit UTC `Z` instant plus a separately named IANA zone is not incorrect timing. Local-friendly formatting is a readability improvement.
- **02-003 downgraded:** choosing the last tied page is deterministic and grounded. No requirement establishes that the first tied page is always clinically superior. Keep a tie-policy/testing suggestion.
- **04-005 narrowed:** native `RecordEditorView` stores the complete record in `@State`, so the stale-summary overwrite is source-confirmed. `VisitEditorView.existing` is a non-State prop supplied by a reactive sheet closure; its specific stale-nil-report UI claim cannot be confirmed without SwiftUI behavior evidence. A model/store race harness alone is insufficient to prove that view timing. The residual Visit concurrency concern is02-008 candidate.
- **03-003 corrected:** a first seed save with missing `state.json` does **not** immediately overwrite the backup; `LocalRepository.save` writes backup only when an old active state exists. A later save may overwrite it. Keep a recovery suggestion.
- **04-003 downgraded:** retaining an instant while changing its displayed zone can be legitimate picker semantics. Browser parity/default-zone clarity is a product-policy suggestion rather than proven mis-scheduling.
- **04-009 remains an evidence gap:** fixed sizes and absent explicit accessibility modifiers alone do not prove VoiceOver failures or clipping; some native controls infer labels.
- **Known attachment retention/independent publication** (03-004,06-001,06-009) remains documented tradeoff/improvement scope. Do not prescribe deleting all unreferenced originals immediately without accounting for other clients and backups.
- **01-001 →16-001** (one configuration conflict, reduce P1 toP2, remove hosted404 prediction); **02-007 →04-001** (one native date ordering bug); **05-006 →04-008** (one PDF palette inconsistency). **02-008** is associated with04-005 but retains a candidate disposition because the visit arm is not independently proven.

## Evidence actually inspected

I read all input finding JSON, then independently read cited production branches and shared call sites in the frozen source. Key modules include native `AppStore`, `+AI`, `+Visits`, `+Records`, `+Recordings`, `+Sync`, `LocalRepository`, `ReportEngine`, `Models`, `BookingEngine`, record/visit/recording editors, import/scanner services, `AudioServices`, `ReportPDFRenderer`, native theme/root/screens; browser App/navigation/style tokens, store/repository/API/test-fixture contracts; and both Vercel configs/build scripts/docs. Every original finding's primary source path and line was checked. Supporting report claims were challenged when they exceeded that source.

Saved runtime logs independently re-read:

- `evidence/r1-06-typecheck.log` — exit1, missing generated demo fixture imports.
- `evidence/r1-07-vitest.log` — exit1, five failed files before asset generation.
- `evidence/r1-06b-typecheck-after-assets.log` — exit0.
- `evidence/r1-07b-vitest-after-assets.log` —77 tests pass in7 files.
- `evidence/r1-17-optimization-checks.log` — exit0; R1/R2/R3/R5/R6/R9 PASS.
- `evidence/r1-16-client-server.log` — exit0; real isolated native URLSession/local Vapor test1/1.

`runner1-summary.json` corroborates stage1 counts and gates. `r2-ui-matrix.jsonl` contains76 static records, no recorded overflow or unlabeled inputs by its own inventory. That inventory uses DOM text and does not establish computed accessible names; it does not refute the hidden tablet-label bug. It also does not establish full OCR/booking/transcript/print journeys or native rendering. No new browser/simulator/UI/build/port/provider/database execution was performed by this validator. The root coordinator subsequently supplied a separate production-state harness, inspected in the addendum below.

Static color arithmetic was independently repeated directly from frozen exact sRGB tokens using channel linearization and relative-luminance weighting (0.2126,0.7152,0.0722):

| Pair | Ratio | Consequence |
|---|---:|---|
| Selected ink `#342B2C` / deep red `#8C2F3B` |1.691728938:1| Confirm14-002 selected-text legibility defect. |
| Heart red `#B84250` / petal `#FAE6E5` |4.453113357:1| Confirm04-007 low-priority small-text token inconsistency; theme itself reserves deep red for this pairing. |

Fictional fixture source was read to verify02-004: the completed nausea/palpitations concern contains “patient-reported”; the unrelated ear source also says the patient reported resolved discomfort. Both terms pass the current generic filter. This source-level intersection confirms over-inclusion without claiming clinical validation or a new runtime benchmark.

## Recommended coverage corrections

- **A03/L01:** mark configuration consistency Defect, canonical16-001; hosted route/refresh behavior remains Unverified. Preserve WIP account/app route boundary; current-spec docs override historical cloud plans.
- **A04/L04/N01:** acknowledge successful actual runner builds and warmed checks; preserve the clean-command prerequisite defect16-002. Historical pass counts do not replace saved logs.
- **C06:** UTC-plus-zone wording alone is not a defect; preserve accurate stored occurrence instant/day and treat localized wording as a suggestion.
- **D03/D05/E03:** mixed-page extraction omission and excerpt truncation/marker stripping are defects. First-vs-last tied page choice alone does not fail grounding.
- **E01/E04:** native date ordering and confirmed stale RECORD-save overwrite are defects. Keep unverified native Visit editor timing separate; browser notes-concurrency07/08 findings require the other validator.
- **F01:** startup repair failure handling is a defect; missing-active-with-valid-backup recovery remains a documented source gap/suggestion rather than observed data loss.
- **J01/J03:** native finish/save recovery and transcript lost through note-only save are defects. Real mic/codec/hardware interruption paths remain Unverified. Reject05-005's message-mapping assertion.
- **K01:** native UI constants match approved palette; PDF output still uses teal04-008. Native visual render not yet captured.
- **K04:** browser tablet names and selection colors are defects. Native VoiceOver/DynamicType behavior remains Unverified; static matrix is not a screen-reader test.
- **M01/M02:** do not retain03-007. Actual six-group regression harness passed; large-workload latency/PDF performance/native camera memory remain unmeasured. Avoid unconditional “inefficient” claims.
- **N03/N04:** merge only canonical issues; preserve all rejected/candidate/WIP/suggestion dispositions, exact scope and evidence in the final packet.

## Complete disposition index

| Finding | Status | Severity | Canonical/related finding |
|---|---|---|---|
| RVA-01-001 | confirmed | P2 | RVA-16-001 |
| RVA-01-002 | suggestion | P3 | — |
| RVA-01-003 | WIP | P3 | — |
| RVA-01-004 | WIP | P3 | — |
| RVA-01-005 | suggestion | P3 | — |
| RVA-01-006 | evidence-gap | P3 | — |
| RVA-01-007 | suggestion | P3 | — |
| RVA-02-001 | suggestion | P3 | — |
| RVA-02-002 | confirmed | P2 | — |
| RVA-02-003 | suggestion | P3 | — |
| RVA-02-004 | confirmed | P3 | — |
| RVA-02-005 | confirmed | P2 | — |
| RVA-02-006 | confirmed | P3 | — |
| RVA-02-007 | confirmed | P2 | RVA-04-001 |
| RVA-02-008 | candidate | P2 | RVA-04-005 |
| RVA-02-009 | suggestion | P3 | — |
| RVA-02-010 | suggestion | P3 | — |
| RVA-02-011 | suggestion | P3 | — |
| RVA-02-012 | suggestion | P3 | — |
| RVA-03-001 | confirmed | P2 | — |
| RVA-03-002 | suggestion | P3 | — |
| RVA-03-003 | suggestion | P3 | — |
| RVA-03-004 | suggestion | P3 | — |
| RVA-03-005 | suggestion | P3 | — |
| RVA-03-006 | suggestion | P3 | — |
| RVA-03-007 | rejected | P3 | — |
| RVA-03-008 | suggestion | P3 | — |
| RVA-04-001 | confirmed | P2 | — |
| RVA-04-002 | candidate | P2 | — |
| RVA-04-003 | suggestion | P3 | — |
| RVA-04-004 | confirmed | P3 | — |
| RVA-04-005 | confirmed | P2 | — |
| RVA-04-006 | confirmed | P3 | — |
| RVA-04-007 | confirmed | P3 | — |
| RVA-04-008 | confirmed | P3 | — |
| RVA-04-009 | evidence-gap | P3 | — |
| RVA-04-010 | suggestion | P3 | — |
| RVA-04-011 | suggestion | P3 | — |
| RVA-04-012 | suggestion | P3 | — |
| RVA-04-013 | suggestion | P3 | — |
| RVA-04-014 | suggestion | P3 | — |
| RVA-05-001 | confirmed | P2 | — |
| RVA-05-002 | confirmed | P2 | — |
| RVA-05-003 | candidate | P2 | — |
| RVA-05-004 | confirmed | P2 | — |
| RVA-05-005 | rejected | P3 | — |
| RVA-05-006 | confirmed | P3 | RVA-04-008 |
| RVA-05-007 | suggestion | P3 | — |
| RVA-05-008 | confirmed | P2 | — |
| RVA-05-009 | evidence-gap | P3 | — |
| RVA-05-010 | suggestion | P3 | — |
| RVA-06-001 | suggestion | P2 | — |
| RVA-06-002 | rejected | P3 | — |
| RVA-06-003 | suggestion | P3 | — |
| RVA-06-004 | suggestion | P3 | — |
| RVA-06-005 | suggestion | P3 | — |
| RVA-06-006 | suggestion | P3 | — |
| RVA-06-007 | WIP | P2 | — |
| RVA-06-008 | suggestion | P3 | — |
| RVA-06-009 | suggestion | P3 | — |
| RVA-14-001 | confirmed | P2 | — |
| RVA-14-002 | confirmed | P3 | — |
| RVA-16-001 | confirmed | P2 | — |
| RVA-16-002 | confirmed | P3 | — |

## Continuation evidence addendum

After this validator's initial source adjudication, the root coordinator supplied `evidence/codex-takeover/provider-context-repro.txt` and `ProviderContextRepro.swift`. I independently read the result and relevant assertions. Compiler and run both exited0, with toolchain cache/event-stream warnings that did not prevent the successful run. The code uses the frozen production state/domain implementations, synthetic fixtures and a controlled provider transport double; it does not use live providers, login UI, real patient data or a simulator.

- **06-002 closed/rejected as an outstanding gap:** lines73–81 compare all three actual production Swift ReportEngine signatures to browser goldens and pass.
- **04-001 now reproduced:** lines83–93 prove the production parser's correct chronological relationship and the production store's incorrect string-sorted result (08:45Z before10:00+02:00/08:00Z). Summary UI consequence remains source-proven.
- **03-001 now reproduced:** lines95–108 make only startup repair storage fail with a synthetic blocking filesystem entry. The original profile remains loaded while startupError is set. Selection of RootView's recovery branch and its reset control are source-proven; actual UI presentation was not exercised.
- **02-002 now reproduced:** Swift lines110–114 and log line15 show the production 1800-character excerpt ending ` dose: 10` when the synthetic source ends ` dose: 100 mg`, with no omission marker. This executes the production domain helper; browser equivalent and displayed quotation consequences remain source-proven.
- **02-005 now reproduced:** Swift lines115–118 and log line16 show an ordinary `Medication: synthetic A` line preceding `Source date:` disappearing from the production excerpt; only the following plan remains. The original text remains stored. Browser equivalent and the separate demo-trailer-marker branch remain source-proven.
- Provider identity findings in the same harness are owned by validator19; they are not double-adjudicated here.

This closes the original03-007 and06-002 evidence gaps without inventing UI coverage. All19 canonical confirmed findings remain; counts are22 confirmed entries (including3 duplicates),30 suggestions,3 evidence gaps,3 WIP,3 candidates,3 rejected/closed.
