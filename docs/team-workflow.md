> The [project overview packet](project-overview-packet.md) preserves the `d0af1df` handoff baseline, including worktree history. This current source map includes later organization, browser-client, and heart-palette revisions. Use the [browser setup guide](../apps/web/README.md) for browser commands and limits.

# Three-person MVP workflow

Follow the [revised MVP goal](mvp-goal.md), [MVP API contract](task-specs/mvp-api-contract.md), and [snapshot contract](implementation-contract.md). The two-hour MVP was delivered on September 12, 2026; subsequent changes follow the user's manual feedback. Preserve the working local demo and configurable API paths; the earlier exhaustive task list does not add release requirements to follow-up work.

These are folder ownership boundaries across the native app, browser app, and Swift server. The browser is a dedicated React/TypeScript interface sharing Swift JSON/API contracts; SwiftUI remains the iPhone interface. Screens, editors, and platform adapters have separate files. Each file has a responsibility contract and named logical sections; follow the [coding standard](coding-standard.md).

Both interfaces stay **light only** with the current [heart palette](../design/palette.json): canvas `#FBF7F5`, white surfaces/button text `#FFFFFF`, actions `#B84250`, deep-red labels `#8C2F3B`, soft fills `#FAE6E5`, and decorative outlines `#DBCBC9`. Native `Features/Shared/Theme.swift` and browser `src/styles/tokens.css` own the roles. Earlier teal/Sky and reserved dark values are historical or future material, not active appearance options.

## Owners

Assign names to Persons 1–3 before branching. The current primary is integration captain; Person 1 takes that role after handoff unless the team explicitly chooses someone else. Captain is a coordination role, not a fourth person.

| Owner | Exclusive feature files | Supporting files and tests |
| --- | --- | --- |
| **Person 1 — records, profile, native preparation** | Native `Features/Records/**`, `Features/Preparation/**`, `Features/Profile/**`; browser `apps/web/src/features/records/**`, `apps/web/src/features/profile/**` | Native `State/AppStore+Records.swift`, `+Visits.swift`, `+Symptoms.swift`, `+AI.swift`, `+Profile.swift`; `Device/DocumentImportService.swift`, `DocumentScanner.swift`, `ReportPDFRenderer.swift`; focused source/profile tests. Browser extraction and original-preview helpers stay in Records. |
| **Person 2 — visits, booking, visit memory** | Native `Features/Visits/**`; browser `apps/web/src/features/visits/**`, including browser visit preparation/print | Native `State/AppStore+Bookings.swift`, `+Recordings.swift`, `+LiveCalls.swift`, `+Transcription.swift`, `Device/AudioServices.swift`; browser recorder/date/edit helpers and their colocated tests. |
| **Person 3 — server and providers** | `server/**`, including provider routes/adapters, local/PostgreSQL stores, SQL, server tests and setup guide | `.env.example`, `server/.env.example`; provider-facing changes to the API contract, agreed with both client owners before implementation |
| **Integration captain — shared files** | Native `Core/**`, `State/AppStore.swift`, `+Sync.swift`, `+Providers.swift`, `Features/Shared/**`, `RevaApp.swift`, `Info.plist`; browser `src/core/**`, `src/components/**`, `src/styles/**`, `App.tsx`, `main.tsx`, Dashboard and Settings | Root `Package.swift`, shared Core tests, `scripts/**`, generated Xcode project, fictional fixtures/resources, shared contracts and delivery docs; browser package/lock/config, `scripts/**`, core tests, and setup guide. |

Native-relative paths start at `apps/ios/Reva/`; browser-relative shared paths start at `apps/web/`. Person 1 owns native visit CRUD/preparation in `AppStore+Visits.swift`; Person 2 owns browser preparation beside the rest of its Visits UI. Coordinate those behavior changes explicitly. Do not concurrently edit different sections of the same file. Native `Core/ReportEngine.swift`, `BookingEngine.swift`, and `ProviderContracts.swift` separate pure rules and wire values; browser `core/domain.ts`, `symptoms.ts`, `validation.ts`, `mutations.ts`, and `api.ts` mirror their applicable contracts. Shared changes go through the captain.

## Keep shared changes small

1. Before changing a shared DTO, persistence field, endpoint or error shape, post the exact proposed signature/JSON, owner and affected callers. The captain updates native `Models.swift`/`ProviderContracts.swift` and browser core values/validation; Person 3 updates the server. Keep persisted additions backward-decodable and preserve IDs, source versions, page evidence, and timestamps. Review [browser compatibility](../apps/web/src/core/COMPATIBILITY.md) before changing report signatures or source ordering.
2. Feature owners use AppStore on native and `useReva()`/the shared store in the browser. Do not write snapshots directly, duplicate DTOs, introduce a second state owner, or put provider secrets in views or browser environment variables. Native provider extensions own their operation; browser `core/store.ts` owns serialized mutations, conflict checks, and provider publication. Request an exact shared-store signature instead of editing another owner's file.
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

The captain owns integrated simulator and browser walkthroughs. Contributors use isolated test data, build directories, browser profiles/origins, and unused ports; simultaneous runs of the same app bundle or browser origin can alter the demo being inspected. Browser revisions reject unseen competing writes, but that is not a substitute for isolated test workspaces.

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
- [ ] For browser or shared-contract changes, run the browser checks from the repository root:

```sh
npm --prefix apps/web ci
npm --prefix apps/web run typecheck
npm --prefix apps/web test
npm --prefix apps/web run format:check
npm --prefix apps/web run build
```

- [ ] Browser check at desktop and narrow widths: search/review filter → intake/cancellation → source edit → symptom/profile → cited brief/page link/print → recording/transcript memory → reload. Check same-origin local-server configuration and explicit revision conflicts with fictional data. Browser permission/codec behavior, real device capture, and paid provider checks require their own reported evidence.
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

Person 1 owns both native and browser symptom/profile screens and native profile/symptom mutations. The captain owns shared `Core/SymptomEntry.swift`, `Core/Models.swift`, browser core equivalents, root routing, Settings, and palette roles. Profile extension fields and `MedicalRecord.symptomEntry` are optional persisted properties. Symptoms use existing record storage, source versions, and preparation providers; the backend preserves these snapshot fields without a new endpoint. Profile edits are quick-reference data and do not rewrite historical source documents or feed the current records-only preparation contract.
