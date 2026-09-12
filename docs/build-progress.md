# Reva build progress and revision history

## Current objective

Implement and verify the native Swift hackathon prototype against [completion criteria](completion-criteria.md). The latest user authorizes frequent checkpoint commits and pushing the completed work. Isolated worktrees should be used for later code reviews and targeted revisions. Never rewrite checkpoint history to conceal changes.

## Decisions and corrections

| Date / stage | Decision | Evidence / effect |
| --- | --- | --- |
| Sep 12 — planning | Apple Health is primary visual reference; One Medical excluded | User design feedback; style plan and reference sheet updated |
| Sep 12 — build start | User supplied a new Ivory/Gold/Slate/Teal/Aqua/Sky palette | Supersedes all earlier A–D palette candidates; exact pixel extraction saved in design/palette.json |
| Sep 12 — build start | Native Swift client, offline-capable demo; future Tiger PostgreSQL persistence | External provider configuration remains empty; simulate cloud jobs honestly |
| Sep 12 — toolchain | Xcode 26.4 (17E192), iOS 26.4 simulator available | xcodebuild and simctl inspected; iPhone 17 / 17 Pro / 17e devices available |
| Sep 12 — completion gate | Criteria written before app implementation | /Users/tempadmin/goals.txt and docs/completion-criteria.md |
| Sep 12 — review access | Claude desktop displays Fable 5.1 Extra; click automation returned noWindowsAvailable | No review has been submitted yet. Browser review route remains to be checked. |
| Sep 12 — source control | Commit checkpoints and push when complete | Explicit latest user authorization; isolated review worktrees planned |

## Checkpoints

Record each meaningful commit with scope, verification, and follow-up below. Git commit history remains the authoritative edit history; this log explains why changes were made.

## Completion audit

All 19 gates require matching implementation and execution evidence. Planning and palette extraction are complete; no app was built before the criteria were written. The user added an as-built stack visualization (`docs/architecture.md`) to be produced immediately before the final push.

## Review log

Claude review rounds, material findings, decisions, fixes, and retests will be recorded in docs/reviews/. Primary agent reviews all contributions before integration.

## Usage accounting

At goal start: Codex weekly 64% used, 36% remaining; one reset credit available. No reset consumed in this goal yet. The user authorizes that single remaining reset at eligibility and asks to preserve at least 50% after it, beginning convergence near 75% remaining.


## Native implementation checkpoint — September 12, 2026, 02:48 CDT

- Xcode 26.4 opened `/Users/tempadmin/Documents/Reva/Reva.xcodeproj` in its native project window. iPhone17 simulator boot/install/launch succeeded (bundle health.revamed.Reva). Integrated 17-file app build passed, log `/private/tmp/reva-app-build.log`.
- Primary wrote Core domain, atomic local repository, deterministic report relevance/excerpts, source-version signature, idempotent booking confirmation, URLSession boundary, AppStore, selected-palette native screens, record intake/review, visit/report export, booking and recording UIs, settings. Initial six core tests pass. UI and end-to-end verification still pending.
- Dataset contributor delivered nine coherent fictional records, three visits, 11 importable sources, source hashes and exact per-page text, sample transcript and demo script. Primary inspected schema, IDs and expected evidence; final integration acceptance ongoing.
- Device contributor supplied native import/OCR/scanner/audio/PDF adapters; strict compiler checks and isolated runtime QA underway.
- Backend contributor delivered Vapor + PostgresNIO server, schema, owner isolation, state revisions/tombstones, local file persistence and attachment support. Eight local tests and real HTTP/restart checks reported passed; primary code review and client integration pending. Live PostgreSQL test remains deferred.
- Claude Desktop Fable5.1 Extra architecture review completed in `local_3c7583ff-a1c1-44ed-a2f1-a225a45f2e72`, project Reva; UI showed 4% of5h usage. Findings accepted: honest local labels, deterministic authority, page text/provenance, interrupted booking recovery, explicit recording end state, fixture expectations, testable transport, derived dark tokens. Specific decisions recorded in implementation contract.
- No external API activated; root `.env` still empty. Final architecture visualization remains intentionally deferred until immediately before final push.

## Reviewed integration checkpoint — September12, 07:08CDT

- Checkpoint `eb2ec3a` saved the native journeys, source fixtures and Swift backend. Worktree `.worktrees/implementation-review` on branch `review/implementation` fixed review at that commit; Claude's reports02/03 are preserved under docs/reviews.
- Primary fixed header-heavy excerpts and implant page selection; every scenario's exact inclusion/exclusion/page/phrase test now executes in Swift. Canonicalized date signatures and unified visit/report questions and notes. Added explicit developer conflict resolution, safe fallback MIME metadata and truthful pull wording.
- Primary inspected and applied Claude's bounded worktree patch for record metadata provenance and PDF navigation after layout. Source corrections without page segmentation now cite “record text” instead of inventing a page number.
- Reviewed build succeeded. All24 current root local tests pass; one real-server test skips without its explicit environment. Eight server tests pass; live PostgreSQL test skipped as documented. The separately launched real-client/server test passed authentication, owner separation, snapshot domains, nine original attachment bytes, CAS and deletion/tombstone recovery.
- Manual simulator route verified queued→proposed→confirmed booking (no call), disabled repeated start, explicit fictional transcript→save memory, and survival across termination/reinstall/relaunch:10records,3visits,1confirmedbooking,1sample recording attached to its original completed visit with noaudio. Summary shows savedmemory afterrelaunch.
- Physical device capture and provider/database credentials remain manual exceptions. Current core UI import/source/export/appearance walkthrough is still underway.

## Acceptance fixes checkpoint — September 12, 07:27 CDT

- `7d0f585` preserved the reviewed evidence, question authority, metadata provenance and server conflict fixes.
- Primary found and fixed document calendar dates shifting in the editor (UTC date-only handling) and a blank PDF export sheet (item-driven presentation). Running app now shows April18 consistently and opens the six-page PDF plus native share actions. Export text/layout inspected; screenshot and PDF retained under docs/verification.
- Independent acceptance audit found summary-cutoff relevance, missing transcript corrections/backlinks, and omitted summary/date search. Full source text now participates in relevance and deeper passages can be quoted; the new long-import regression and all26 local core/transport tests pass (one gated real-server test skips in the default suite).
- Transcript contributor implemented text-only corrections with timestamps/speakers preserved, atomically refreshed saved memories, separate manual notes, stable memory identity and source navigation. Primary read the entire patch.17 AppStore persistence checks and full app typecheck pass; integrated Xcode build succeeds. Manual transcript UI check follows this checkpoint.
- Simulator verified fictional visit creation and title edit, complete stored fields, recording consent screen with disabled start before agreement, imported text record, source version staleness, question edits and regenerated brief. Final appearance/reset/review checks continue.

## Two-hour MVP / API integration checkpoint — September12,08:10CDT

The user's deadline changed at07:28CDT. docs/mvp-goal.md and /Users/tempadmin/goals.txt replace the exhaustive loop with MVP + API readiness + three-person collaboration + final diagram/push. Heavy repeated review is deferred to manual feedback.

- Split UI into Features/Records, Preparation, Visits, Shared; AppStore into foundation plus Records/Visits/Bookings/Recordings/Sync/Providers extensions. Shared Core contracts remain coordinated by the integration captain. docs/team-workflow.md gives three owners, branches/worktrees and bounded starter tasks.
- Added real server-only Gemini Developer API summary/preparation, Whisper1 multipart transcription, and ElevenLabs/Twilio outbound/poll adapters. Keys stay server-side, provider use requires a private token mapping, and actual calls additionally require environment enablement plus per-call review/consent. Durable fsynced call intents block replay/uncertain redials. Polling never confirms appointments automatically.
- Native ProviderClient, service discovery/settings, upload summarization, AI-assisted briefs with exact local source citations, saved-audio transcription, and separate real-call review/status surfaces compile in the integrated app. Optional model/provenance fields preserve backward compatibility. Native fixture UI verified configuration discovery, summary saving/model label, and structured preparation with two exact source links; no AI service ran in these labeled fixture checks.
-35 root tests executed:34 local/mocked pass,1 explicitly gated live-server test skipped in default run.29 server local/mocked tests pass,1 live PostgreSQL test skipped. Real HTTP provider smoke verifies all six auth boundaries, exact disabled status and four503 unconfigured responses. No paid calls or keys used. Earlier actual native persistence-client/server test remains passed.
- The user rejected derived dark colors during verification. Removed adaptive substitutions and dark selection; current MVP stays light with exact Ivory canvas, Sky surfaces, Teal actions and Ivory action text. All6 source colors remain exact in design/palette.json and Theme.swift. Earlier dark screenshot is historical and not the shipped design.
- New launcher scripts/run_server.py safely reads a user-filled root.env without shell evaluation; current .env remains0bytes. Environment examples/documentation contain placeholders only.
