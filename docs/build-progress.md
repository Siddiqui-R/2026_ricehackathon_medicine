# Reva build progress and revision history

## Current objective

Maintain the native/browser MVP and reconcile the active account/Tiger extension and independent audit against [the current project specification](reva-stack-spec.md). The original [completion criteria](completion-criteria.md) and dated entries below preserve earlier milestones. This collaborator retains the user's focused checkpoint/push workflow; Claude's concurrent application changes remain owned by its implementation workflow. Use isolated worktrees for reviews and targeted revisions, and never rewrite checkpoint history to conceal changes.

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

Git history preserves each checkpoint; the entries below explain their purpose.

| Commit | Checkpoint |
| --- | --- |
| `7725fc7` | Criteria, exact palette, stack/style planning and task list |
| `eb2ec3a` | Native journeys, fictional sources, device adapters and Swift backend |
| `7d0f585` | Reviewed source evidence, edit authority, metadata and transport fixes |
| `d9ec87c` | Transcript provenance, long-document retrieval, date and PDF presentation fixes |
| `8f52577` | Configurable provider APIs, three-person feature separation, user-corrected exact light palette |

The final documentation/verification commit follows creation of the requested as-built stack visualization.

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


## Final MVP verification — September12,08:17CDT

- Corrected palette visible in a fresh native launch; screenshot summary-exact-palette.png inspected. No adaptive dark colors remain in the shipped theme. Original palette.json unchanged.
- Native localhost fixture integration verified service discovery, summary-model provenance, and structured preparation with two source links. The fixture labels every response mock-transport-only; no live AI ran. Native default-server check then showed providers unconfigured, and connected AI remained disabled.
- Saved sample memory updated through its native action, persisted through relaunch, and “Open visit transcript” navigated back to the correct sample. Transcript correction fields/timestamps were inspected; the edit was canceled after a Computer coordinate-action failure. Actual correction persistence had17 passing isolated AppStore checks. No unobserved save is claimed.
- Explicit Restore fictional demo confirmation returned to the original nausea/palpitations visit and known records. Relaunch retained the reset. The app was returned to localhost8080 and clean synthetic data after provider-fixture QA.
- The remaining manual feedback scope includes physical capture/signing, live provider credentials/agent/number/database smoke checks, broader device/large-text visual polish and production operations. These are not represented as executed checks.

## Final stack document and delivery

Created docs/architecture.md after implementation and the bounded MVP verification, immediately before the final commit/push as requested. It diagrams native/client/server/Tiger/provider boundaries, document-to-brief, booking, recording/memory and three-person ownership. README links it. Final remote alignment is verified after push and reported in the delivery message; Git history supplies the final commit identity.


## Follow-up — medical profile, symptom entries, dashboard (September 12)

- User requested persistent health information on its own medical profile page, removal of Appearance and the “Your history stays with you” tile, a Recent records footer linking to the Records tab, an exact-palette background adjustment, and an intuitive symptom log.
- Added fourth Medical profile tab and Summary avatar routing. Profile overview/editor includes name/date of birth, allergies, medications, conditions, surgeries/implants, and care notes; settings now contains service/app controls. Optional profile fields preserve old snapshots.
- Added a structured User symptom entry, available from Summary and Records. Occurrence time/zone, optional severity, duration, details, possible triggers, and what helped persist as a self-reported record. Entry edits preserve identity and original creation time, use normal source versions, and remain available for search and visit preparation. Imported scanned material remains a separate source.
- Renamed only the untouched fictional diary label to “Scanned symptom note - date needs review”; original image, extracted text, uncertain date, and user-edited labels remain intact.
- Measured prior screenshot flat RGB values: cards (225,236,238) and canvas (250,244,244), exactly Sky and Ivory. Revised roles to an opaque Sky page background and Ivory cards; explicit sRGB tokens preserve all six supplied values. Palette choice was asked asynchronously; this is the stated default pending other feedback.
- Verification and checkpoint results are recorded in [profile-symptoms.md](verification/profile-symptoms.md). This follow-up adds no provider configuration or paid requests.

- Checkpoint `ffcbf6c`: implemented medical profile, symptom logging, navigation, and palette roles. Final native build succeeded; 43 core tests passed with one live-server gate skipped. Native save/edit/filter/view-all/relaunch checks passed. Temporary QA data removed through the app.
- Updated the as-built stack diagram immediately before the follow-up documentation commit and GitHub push.


## Project overview packet September 12

- Created `output/pdf/reva-project-overview-packet.pdf`, a seven-page teammate packet, with editable `docs/project-overview-packet.md` and a single-source ReportLab builder at `scripts/build_overview_packet.py`.
- Inspected actual Git worktrees at baseline `d0af1df`: clean main; historical implementation-review with 2 modified files/2 untracked reports; historical final-review with 1 untracked report. Neither review branch has commits absent from main. Proposed three-person branches are clearly identified as not yet created. No worktree was altered.
- Verified the technology/feature inventory against source and package locks. Distinguishes local behavior, configurable providers, manual setup, Medical profile quick-reference data, and symptom records that participate in preparation.
- Corrected stale README/team-guide palette roles and README root test count; preserved earlier test-run chronology. No application code changed and no tests or paid integrations were rerun for this documentation task.
- Rendered the PDF with Poppler and inspected all seven pages. Tables/diagrams fit, numbering is correct, and the final PDF contains no blank overflow page. QA renders remain ignored under output/qa.


## Code organization and writing standard — September 12, 09:30 CDT

- User requested functional code blocks and comments describing each chunk. Source checkpoint `30bd762` separates mixed screens/editors, pure booking rules, provider wire values, and AI/transcription/live-call state operations. Closely coupled private helpers keep their existing ownership.
- All 71 production Swift files now have Purpose/Inputs/Outputs/Side effects contracts and named logical sections. Test, package, Python and SQL boundaries are also documented. `.swift-format` expands compressed code and supplies a consistent four-space layout.
- Added a [project coding standard](coding-standard.md), a read-only structure check, and the current ownership map. The standard adapts clarity, bounded-work and explicit-boundary principles to Swift; it does not claim NASA certification.
- Verification: native simulator build passed; 43 root tests and 29 backend tests passed, with one gate skipped in each suite. Strict formatting lint, 71-file structure check, 13 Python syntax checks and Git whitespace check passed. See [code-organization verification](verification/code-organization.md) for exact scope and comparison evidence.
- Updated the current stack/source diagram before the documentation checkpoint and push. Historical review worktrees, fixtures, original palette, API configuration and the baseline overview PDF are preserved. No live API or new device/UI interaction was performed in this structural revision.


## Browser extension and selected palette — September 12

- User authorized a responsive browser client, with a desktop arrangement informed by MyChart, and explicitly confirmed that it should follow the newer heart-red palette.
- Preserved Claude Desktop's user-selected native palette/treatment patch, verified it against the actual theme, and formatted its long comment. Current authority is `design/palette.json`: blush ivory `#FBF7F5`, white cards, heart red `#B84250`, deep red `#8C2F3B`, petal `#FAE6E5`, linen `#DBCBC9`. The original six supplied colors remain in `design/palette-supplied.json` as provenance.
- Checkpoint `480bdae` adds WebM/Ogg upload/transcription MIME support across Swift server/native transport without changing original audio bytes. Root 43 tests passed (one explicit gate skipped), server 30 passed (one PostgreSQL gate skipped), and the native simulator build passed including the palette patch.
- Browser implementation and production UI verification continue in a separate checkpoint; no paid providers or actual clinic calls used.


## Responsive browser delivery — September 12, 10:35 CDT

- `678e742` preserves the selected native heart-red palette and outlined components. `2640360` adds the dedicated React browser UI, 77 passing browser regressions, and seven isolated production-wrapper HTTP checks. User explicitly selected the newer palette for both clients.
- Browser modules cover dashboard, records/local PDF+OCR intake, source review, symptom entries, Medical profile, visits/cited briefs, booking simulation/configured calls, recording/transcript memory and explicit server sync. Core DTOs and all three fixture report hashes match the actual Swift engine. IndexedDB mutations have cross-tab revision checks and atomic commit failure handling.
- Fixed queued visit edits, stale microphone permission callbacks, durable live-call UI state, matching report prose duplication, and header label accessibility during integration. Added a fixed-destination bounded production proxy; regression tests verify an absolute request cannot select another host. Provider keys remain server-only and no real call/paid request ran.
- Production browser verification covered PDF values/units and retained original, local image OCR with Needs review, page-two implant citation, simulated booking, transcript correction to saved memory, real unconfigured-service discovery, fixture reset and 25 responsive route/width combinations without overflow. Development symptom/profile saves survived reload. Exact tested and untested scope is in docs/verification/web-client.md.
- Captured desktop/phone screenshots, updated setup/three-person ownership/coding standard, and refreshed docs/architecture.md with the full native/browser/API/database/provider stack immediately before the documentation commit and push. The earlier seven-page packet and historical review worktrees remain preserved at their recorded baselines.


## Concurrent remote integration before push

- A final fetch found user commit `77c03da` (protect sync state and streamline source transfers), so delivery integrates it with a merge while retaining all checkpoints.
- Resolved the single native sync conflict by retaining the remote deduplicated upload map and our filename-based audio MIME selection. Provider budget checks, snapshot/connection guards, staged original-file protection and the expanded credential ignore rules remain intact.
- Re-ran the native package suite: 43 passed, one explicit gate skipped. The merged iPhone simulator build succeeded. Source responsibility checks still cover 71 Swift and 50 browser files. The remote focused optimization harness passed all six regression groups after adapting its network doubles to compile the exact production audio-type helper. The deduplicated upload regression covers M4A/WebM/Ogg MIME precedence, original bytes, failed push and explicit retry.
- The current full-stack document now records the native staging behavior and browser IndexedDB boundary. No review worktree was changed.


## Vercel 404 configuration fix — September 12

- User reported Vercel accepted the push but showed 404. GitHub confirmed Production deployment 6411370200 of dc25e87 as successful. The repository had neither a root web entry point nor Vercel build configuration.
- Added root vercel.json with explicit browser install/build/output paths and the local host's CSP, nosniff and referrer policy. Kept repository-root builds so native demo originals and local OCR model assets are available. Hash routes require no catch-all rewrite.
- Clean npm ci (including development build/OCR packages) and the exact production build command passed. Generated index, JS/CSS, demo/seed.json and OCR worker/model exist under apps/web/dist. Added docs/deployment-vercel.md and linked the browser guide.
- The unique deployment URL redirected to Vercel login. Computer access to Google Chrome was denied; no credentials or browser protections were bypassed. GitHub deployment status remains available for following the new build, and the public URL has been requested for visual verification.
- This fixes frontend publishing. Hosted provider/sync routes still require a separately deployed Swift backend; no local loopback proxy or provider key is silently exposed on Vercel.

## Independent Fable audit and specification reconciliation — September 12

- Checkpoint `475eee7`, pushed to `origin/main`, saves the 67-check audit packet, 19 worker task assignments, frozen-source manifest and separate Claude launch receipt. Snapshot `.worktrees/fable-audit-20260912-114322` preserves `cfe0997` plus captured WIP; 267 hashes were verified by Claude.
- Through Computer, created **Reva intensive code-review workflow** in Claude Desktop Code with Fable 5.1 / Ultracode. Actual workflow `reva-fable-audit-w1` (`wf_74d707c0-9d8`) launched the runner and six Wave A workers; later source waves and validators are queued. Review completion and findings remain pending in `docs/audits/fable-20260912-114322`.
- At the user's request, obtained a summary-only handoff from **Reva architecture review** while its three-track accounts/Tiger implementation continued. Reconciled the handoff with source and Git history; saved `docs/reviews/05-claude-project-handoff.md` with evidence boundaries and corrections to stale claims.
- Replaced the planning-only stack spec with the current product/technology specification, route/API/configuration maps, precise heart palette, account/Tiger requirements, verification gates and full-stack interaction diagram. Preserved the initial proposal and added explicit current-spec links to historical goal/contracts.
- Account/landing/Gemini/Tiger changes remain uncommitted WIP at this refresh. Existing browser/native tests do not establish new account or hosted deployment success. Application code, README/architecture/Tiger setup and examples remain with their implementation owners. No tests, credentials, live service calls or hosting changes were performed by this documentation task.


## Consolidated audit repairs — September 12, 2026

Three simultaneous Astra agents at xhigh repaired the 23 confirmed audit findings in isolated native, extraction and browser worktrees. The coordinator integrated checkpoints, ran native and browser builds plus real local client/server and OCR checks, preserved the shared checkout's unrelated work, and reconciled concurrent Windows repair commit `36c055d` without replacing its history. The [repair report](reviews/06-audit-repairs.md) records final evidence, stack boundaries, retained remote improvements and device/service limits. The [UI follow-ups](ui-todo.md) record the five subsequently implemented browser requests.


## Preserved concurrent integration — September 12, 2026

Saved the account/landing, Central-time, native glass-tab and streamlined record work in `e04b9bd`, then merged the incoming ElevenLabs documentation and original browser/native/evidence repair histories. Reviewed remaining worktree edits without replacing newer modules. The [integration report](reviews/08-preserved-integration.md) records checkpoint recovery, feature preservation and checks.

Fixed account attachment ownership/atomic audio saves, SQL migration comment splitting, local account-registry filename collision, and password/session races. Final checks passed: 197 browser tests, seven wrapper checks, 59 server tests, 57 core tests plus the real local client/server check, native state/audio and PDF/OCR harnesses, 24 Tiger mocks, browser/server/iOS builds, formatting and structure. Two live PostgreSQL gates were skipped. Simulator and production-browser navigation/original previews passed. No live provider, phone call or hosted deployment was performed.
