> The [project overview packet](project-overview-packet.md) preserves the `d0af1df` handoff baseline, including worktree history. The current source map and [coding standard](coding-standard.md) below include the subsequent code-organization revision.

# Three-person MVP workflow

Follow the [revised MVP goal](mvp-goal.md), [MVP API contract](task-specs/mvp-api-contract.md), and [snapshot contract](implementation-contract.md). The two-hour MVP was delivered on September 12, 2026; subsequent changes follow the user's manual feedback. Preserve the working local demo and configurable API paths; the earlier exhaustive task list does not add release requirements to follow-up work.

These are folder ownership boundaries inside the existing app target. Screens and editors now have separate files, including visit list/detail/editing and report views. Each file has a responsibility contract and named logical sections; follow the [coding standard](coding-standard.md).

The user reaffirmed the exact palette after reviewing a dark screenshot: the app now stays **light only**, with Sky canvas, Ivory cards/button text and Teal actions. Preserve all six original hex values in `Features/Shared/Theme.swift`; do not restore adaptive dark substitutions. The [style plan's current authority block](reva-style-plan.md) overrides its historical alternatives.

## Owners

Assign names to Persons 1–3 before branching. The current primary is integration captain; Person 1 takes that role after handoff unless the team explicitly chooses someone else. Captain is a coordination role, not a fourth person.

| Owner | Exclusive feature files | Supporting files and tests |
| --- | --- | --- |
| **Person 1 — records and preparation** | `apps/ios/Reva/Features/Records/**`, `Features/Preparation/**` | `State/AppStore+Records.swift`, `State/AppStore+Visits.swift`, `State/AppStore+Symptoms.swift`, `State/AppStore+AI.swift`; `Device/DocumentImportService.swift`, `Device/DocumentScanner.swift`, `Device/ReportPDFRenderer.swift`; new focused tests in `Tests/RevaCoreTests/RecordProviderTests.swift` |
| **Person 2 — booking and visit memory** | `apps/ios/Reva/Features/Visits/**` (individual booking, live-call, recording and transcript screen/editor files) | `State/AppStore+Bookings.swift`, `State/AppStore+Recordings.swift`, `State/AppStore+LiveCalls.swift`, `State/AppStore+Transcription.swift`, `Device/AudioServices.swift`; new focused tests in `Tests/RevaCoreTests/VisitProviderTests.swift` |
| **Person 3 — server and providers** | `server/**`, including provider routes/adapters, local/PostgreSQL stores, SQL, server tests and setup guide | `.env.example`, `server/.env.example`; provider-facing changes to the API contract, agreed with both client owners before implementation |
| **Integration captain — shared files** | `apps/ios/Reva/Core/**`, `State/AppStore.swift`, `State/AppStore+Sync.swift`, `State/AppStore+Providers.swift`, `Features/Shared/**`, `RevaApp.swift`, `Info.plist` | Root `Package.swift`, existing shared Core tests (including `ProviderClientTests.swift`), `scripts/**`, `Reva.xcodeproj/**`, `demo/**`, bundled `Resources/**`, shared contracts, README and final delivery docs |

App-relative paths in the table start at `apps/ios/Reva/`. New test filenames are reserved ownership slots, not claims that those files already exist. `AppStore+Visits.swift` owns visit CRUD/preparation; booking mutations are in the separate `AppStore+Bookings.swift`. Do not concurrently edit different sections of the same file. `Core/ReportEngine.swift` and `Core/BookingEngine.swift` now hold separate pure engines. `Core/ProviderContracts.swift` contains shared provider wire values; `ProviderClient.swift` contains transport. Changes to these shared contracts still go through the captain.

## Keep shared changes small

1. Before changing a shared DTO, persistence field, endpoint or error shape, post the exact proposed signature/JSON, owner and affected callers. The captain updates `Models.swift`/`ProviderContracts.swift`; Person 3 updates the server contract and implementation. Keep persisted additions backward-decodable and preserve IDs, source versions and timestamps.
2. Feature owners use the existing AppStore mutation boundary and provider entry points. Do not write snapshot files directly, duplicate transport DTOs, introduce a second state owner, or add provider secrets to views. Shared `AppStore+Providers.swift` owns client creation and service discovery; operation-specific `+AI`, `+Transcription` and `+LiveCalls` files have the feature owners above.
3. Use exact local source text/page references for brief evidence. Provider-selected IDs must resolve to submitted candidates. AI overview/questions remain reviewable; a provider failure preserves the user's records, edits and audio.
4. Booking demo and configured outbound calling remain distinguishable. A call status is not an appointment confirmation. Keep the API contract's consent, server enable flag and durable owner/request receipt behavior; do not automatically retry an uncertain call.
5. Provider mocks use synthetic inputs and intercept outbound transport. Root `.env` stays empty and ignored. Account/agent/phone/database setup and credentialed smoke tests are manual; no paid request or real call is part of this development checklist. See the contract for exact provider behavior instead of assuming model capabilities or speaker diarization.

## Branches and worktrees

The captain first commits the folder split and shared contract baseline, and shares that commit SHA. Each feature starts from that same checkpoint. Review `git status --short` before branching: uncommitted work is not included in a new worktree. Commit intended baseline changes explicitly; leave unrelated work intact.

On one machine with a shared clone, run from the agreed integration checkout:

```sh
git status --short
git worktree list
reva_mvp_base=$(git rev-parse HEAD)
git worktree add -b mvp/records-preparation ../Reva-records-preparation "$reva_mvp_base"
git worktree add -b mvp/visit-memory ../Reva-visit-memory "$reva_mvp_base"
git worktree add -b mvp/server-providers ../Reva-server-providers "$reva_mvp_base"
```

Use an existing matching worktree if already present; do not force branch/path replacement. Each person opens only their assigned checkout. On separate machines, fetch the published baseline into each person's clone and create the corresponding branch at that exact SHA instead. Share that branch's commits through the normal remote; worktrees themselves are local.

Commit only owned paths after `git diff --check` and reviewing `git diff`. Send the captain the branch/SHA, changed files, exact checks/results, setup needed, and any shared-file request. Do not reset another checkout, force-push shared history, or merge another person's unfinished branch into a feature branch. The captain merges reviewed branches one at a time with `git merge --no-ff <feature-branch>` from the integration branch; any conflict returns to the file owner for a deliberate resolution.

The captain owns the simulator walkthrough. Contributors use isolated test data and build directories; simultaneous runs of the same app bundle can overwrite the demo state being inspected.

## Integration checklist

- [ ] Review the contribution against its owned files and agreed JSON. Record implementation status separately from mocked or live verification.
- [ ] Run `python3 scripts/check_code_structure.py` and the formatter/linter commands in [coding-standard.md](coding-standard.md); review comment accuracy and cohesion.
- [ ] Regenerate after source/resource changes with `python3 scripts/generate_project.py`. It discovers files recursively. Do not manually edit `project.pbxproj` or commit competing generated project changes from feature branches; the captain generates the final project after merging.
- [ ] Run the checks affected by the change, then one integrated pass from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -j 6
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path server -j 6
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path server -j 6
python3 scripts/test_client_server.py
xcodebuild -project Reva.xcodeproj -scheme Reva \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

- [ ] Brief simulator check: import/review → saved record → relevant brief/source/PDF; separate booking demo and provider setup state; sample transcript correction → saved memory/backlink; relaunch. Inspect new provider controls with missing configuration and mocked success/failure as available. Device input and live credentials remain separately reported.
- [ ] Confirm `.env` is zero bytes and ignored, no source artifacts/secrets entered the diff, and README/provider configuration matches the final code. Update the progress log with actual outcomes, not only test names.
- [ ] Captain completes the as-built architecture document immediately before the final commit/push, updates links, pushes reviewed commits, and verifies remote HEAD. Do not reopen the superseded broad audit.

## Three small starter tasks per owner

Provider adapters and native entry points are now implemented and tested with mocks; credentialed live checks remain manual. Choose one small follow-up per person after reading the latest progress entry. These are bounded handoff tasks, not another mandatory completion loop.

| Owner | Starter task | Done when |
| --- | --- | --- |
| Person 1 | Check the imported-record summary action's missing-setup and failure paths. | Missing setup/error retains the local excerpt and edits; returned summary is labeled with its actual origin/model. |
| Person 1 | Exercise AI preparation against the two fictional visit goals. | Candidate IDs are validated, local evidence/pins remain correct, editable questions survive the selected flow, and exported content matches the displayed brief. |
| Person 1 | Tighten one source-review issue found in the short demo. | Import, edit, stale brief and original page still work; add a focused regression only for a consequential logic failure. |
| Person 2 | Check saved-audio transcription UI around the shared API method. | Only actual saved audio can be sent; progress/errors are visible; relative offsets survive and no unsupported speaker roles are invented. |
| Person 2 | Check configured-call start/status UI alongside the demo. | Explicit consent/setup is required; repeated or uncertain requests reuse the receipt; status never fabricates a confirmed appointment. |
| Person 2 | Verify corrected transcript → memory → source navigation after relaunch. | Corrections preserve timestamps/separate notes, update the existing memory once, and keep the source link or an honest missing-source notice. |
| Person 3 | Extend a provider mock test only for a newly observed consequential failure. | Missing configuration, malformed output, invalid selection IDs and upstream failures produce the contract's safe outcomes without live requests. |
| Person 3 | Verify durable outbound intent and receipt behavior. | Duplicate, uncertain and restarted requests cannot cause a second automatic call; another owner cannot read the receipt. |
| Person 3 | Finish configuration and manual setup handoff. | Actual environment variables, provider setup, limits and optional Tiger path match code; a credentialed smoke procedure is documented without claiming it ran. |

Existing evidence is in [build-progress.md](build-progress.md), [verification](verification/README.md), and the feature [task specifications](task-specs/). Use the latest execution entry when an earlier review still describes a subsequently fixed failure.


## Profile and symptom follow-up ownership

Records/preparation owns `Core/SymptomEntry.swift`, `Features/Records/SymptomEntryDetailsView.swift`, `Features/Records/SymptomEntryEditorView.swift`, and `State/AppStore+Symptoms.swift`. The integration captain owns the Medical profile feature (`Features/Profile/**`, `State/AppStore+Profile.swift`), root tab routing, Settings, and palette roles. Profile extension fields and `MedicalRecord.symptomEntry` are optional Codable properties; coordinate changes to `Core/Models.swift`. Symptoms use existing record storage, source versions, and preparation providers. The backend preserves these additional snapshot fields without a new endpoint. Profile edits are quick-reference data and do not automatically rewrite historical source documents or feed the current records-only preparation contract.
