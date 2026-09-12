> Superseded where scope conflicts by [the user’s two-hour MVP revision](mvp-goal.md). Remaining work follows that shorter delivery scope; this original checklist is retained for history and later manual feedback.

# Reva — complete implementation and verification task list

**Authority:** the user's active build goal and subsequent instructions.
**Product:** Reva, revamed.health; Swift iPhone first.
**Repository:** Siddiqui-R/2026_ricehackathon_medicine; local folder `/Users/tempadmin/Documents/Reva`.
**Purpose:** a functional, presentable hackathon prototype covering the whole stated patient journey, with live provider setup deferred.
**Ordering requested:** obtain Xcode access, write this complete list, then resume other work. Xcode's Welcome screen was inspected before this list was written.

The original completion criteria remain binding in [completion-criteria.md](completion-criteria.md). The combined criteria and this list are saved to `/Users/tempadmin/goals.txt`. The stack spec, selected palette, and style plan provide supporting detail; this list controls implementation sequence and explicit acceptance checks. A checked task must cite authoritative evidence in [build-progress.md](build-progress.md), not just a plan or agent's claim.

## A. Scope and operating rules

- Build the native Swift/SwiftUI iPhone product. A static mockup or browser-only substitute is insufficient. Browser wrapping is a later phase, not a required build in this goal.
- Use the exact supplied palette: Ivory `#FAF4F4`, Gold `#C8A07D`, Slate `#A2B7BC`, Teal `#0A5B6C`, Aqua `#6FABB6`, Sky `#E1ECEE`. Preserve the original values and distinguish any accessibility/dark-mode derived tokens.
- Follow Apple Health for visual hierarchy and native interaction. Guava may inform record workflows; MyChart may inform clinical vocabulary. One Medical is excluded as a visual reference.
- Manual upload only. No MyChart/Epic connection, HealthKit import, or custom password-based encryption system is required.
- Gemini is the intended cloud summarization/report connector; ElevenLabs plus the specified Gemini voice model/Twilio route is the intended booking stack. No real API credentials or paid services are activated now.
- Leave a root `.env` file exactly empty and Git-ignored. Keep examples and setup instructions separate. Do not embed secrets or pretend that unconfigured integrations have run.
- Prepare TigerSQL/Tiger Data PostgreSQL as the persistent server data store. Local demo persistence must work without its credentials. The server boundary and database schema must be real and testable, while live Tiger setup is deferred.
- The primary agent manages architecture, integration, material decisions, code review, and completion auditing. Subagents may implement bounded tasks with detailed written specs and clear file ownership.
- Use **Claude Desktop / Claude Code**, configured for **this project's folder**. Do not use the browser for Claude. Use Fable 5.1 at an available xhigh/Extra, max, or appropriately bounded ultracode setting; verify what the UI actually offers.
- Use Claude repeatedly for focused architecture and code reviews. Avoid unlimited ultracode workflows and repetitive low-value reviews. Verify a usage-limit/reset state before waiting; continue independent work while waiting. Re-read the same live task before retrying; do not duplicate an active review.
- GPT subagents, when needed, use GPT-6 Astra at xhigh or ultra. The parent manually reviews contributions. No autonomous handoff replaces the parent's ownership of the full context.
- Make frequent focused checkpoint commits, maintain detailed completed-work and edit-history logs, and use isolated Git worktrees for later reviews and targeted revisions. Push completed work to GitHub after final verification.
- Honor the user's request to surface access/setup needs early and act within the authorizations already given. Do not bypass security prompts or claim that future OS/provider prompts can be preapproved universally.
- The single remaining Codex usage reset is explicitly authorized when limits reach the reset tool's eligibility threshold. Use one stable idempotency key. After reset, begin reducing extra work around 75% remaining and preserve at least 50% remaining. Keep the full goal active if a resource constraint leaves work unfinished.

## B. Setup and readiness

### T01 — Xcode and simulator preflight

- [x] Inspect installed Xcode/Swift/iOS SDK and available simulators: Xcode 26.4, Swift 6.3, iOS 26.4 were found.
- [x] Open Xcode through Computer and inspect a usable window: Welcome to Xcode, Version 26.4.
- [ ] Open `Reva.xcodeproj` in Xcode and confirm its target/scheme are available.
- [ ] Finish the native preflight build and inspect its actual exit status/log.
- [ ] Boot an iPhone simulator, install the built app, launch it, and inspect the running interface.
- [ ] Establish a repeatable build/test/screenshot route and list device-only checks.
- **Evidence:** Xcode UI state, successful build log, installed bundle and launch output, simulator inspection.

### T02 — Claude Desktop project access and review setup

- [ ] Verify Code mode and primary working folder `/Users/tempadmin/Documents/Reva` with no unrelated project added.
- [ ] Resolve the Reva workspace-trust/setup prompt within the user's authorization; inspect the resulting project selection.
- [ ] Verify Fable 5.1 and the chosen available effort level, plus actual usage/reset information.
- [ ] Submit a bounded architecture review using project-local spec files.
- [ ] Record Claude review identifiers, requested scope, response, material findings, and follow-up.
- **Evidence:** desktop UI showing Reva, model/effort, a submitted task, and completed review output. Current desktop selection reached the Reva trust prompt; review completion is not yet proven.

### T03 — Git, dependencies, configuration, and worktrees

- [x] Verify GitHub push access with a dry run and Git dependency repository access.
- [x] Configure local commit identity from the authenticated GitHub account and make initial checkpoint `7725fc7`.
- [x] Create empty ignored `.env`, separate `.env.example`, and exact palette artifacts.
- [ ] Confirm app/core/server dependencies resolve without provider credentials.
- [ ] Ensure ignored build files, generated caches, local recordings, real records, and secrets stay out of commits.
- [ ] Create a dedicated review worktree from a meaningful implementation checkpoint; use it for later review and targeted fixes.
- [ ] Document checkpoint recovery, comparing revisions, and applying reviewed fixes without destructive resets.

### T04 — Detailed subtask packets and implementation contracts

- [ ] Write a shared domain/API/fixture contract before parallel implementation.
- [ ] Write one task spec per delegated area, naming paths, inputs/outputs, ownership, behavior, tests, and exclusions.
- [ ] Maintain a task-to-owner/checkpoint matrix in the progress log.
- [ ] Review each contribution against its packet and run integration checks before checkpointing.

## C. Native foundation and visual system

### T05 — Project skeleton and build configuration

- [ ] Maintain a reproducible Xcode project/generator, app target, appropriate minimum OS, bundle ID, simulator build scheme, and resource inclusion.
- [ ] Add necessary camera/microphone purpose strings and only the entitlements/background behavior actually used.
- [ ] Separate domain models, persistence, provider adapters, device services, reusable views, and feature screens.
- [ ] Keep startup deterministic with first-run seeded data and recoverable persistence errors.

### T06 — Exact palette and reusable interface components

- [x] Extract each swatch from the original sRGB PNG without resizing; all 1,600 pixels in each interior sample agree.
- [x] Save exact hex/RGB values, sample coordinates, and source hash in `design/palette.json`; save extraction script and usage roles.
- [ ] Implement named Swift color tokens, neutral text/surface tokens, status colors, and usable dark variants.
- [ ] Implement native large titles, semantic scalable typography, grouped cards/rows, source chips, status labels, section headers, primary/secondary actions, and empty/error states.
- [ ] Check contrast against actual surfaces and preserve large tap targets. Do not use Gold/Slate/Aqua as small low-contrast body text.

### T07 — App shell, onboarding, profile, and settings

- [ ] Build Summary / Records / Visits tabs, consistent navigation, and contextual sheets.
- [ ] Provide a short welcome/demo entry with “Making every appointment count” and clear fictional-data disclosure.
- [ ] Build profile/settings with demo identity, appearance preference, integration status, privacy/local-data explanation, and explicit demo reset.
- [ ] Support relaunch without repeated onboarding or loss of changes; do not imply live login exists when unconfigured.

### T08 — Summary dashboard

- [ ] Show the next appointment, purpose, provider/date, report state, and a working preparation action.
- [ ] Show actionable items needing review and a concise recent-records group.
- [ ] Provide Add Record and Add Visit routes and meaningful no-record/no-appointment states.
- [ ] Avoid invented health scores, unrelated wellness charts, and misleading medical-status badges.

## D. Domain, persistence, and document memory

### T09 — Shared domain model and local repository

- [ ] Define profile, medical record, source attachment, extracted text, structured summary, source reference, appointment, report/version, booking request/attempt, recording, transcript segment, and persisted app state.
- [ ] Preserve IDs, source dates versus upload dates, types, timestamps, provenance, and demo/real-local flags.
- [ ] Implement atomic local save/load, schema versioning, first-run fixture loading, explicit reset, and recoverable errors.
- [ ] Keep an explicit protocol/transport boundary for later Tiger-backed synchronization.

### T10 — Records list, search, and filters

- [ ] Show chronological records with useful title/type/date/provider and actual processing state.
- [ ] Search titles, summaries, tags, and extracted text; filter by record type.
- [ ] Open detail, support no-results/empty states, and avoid losing navigation after edits/deletions.

### T11 — Import from Files and Photos

- [ ] Import supported PDF, plain text, and document images with correct file access handling.
- [ ] Copy source bytes into app-owned storage; preserve filename, MIME/type, size, and identity.
- [ ] Validate unsupported, corrupt, missing, empty, and oversized inputs with actionable errors.
- [ ] Extract embedded PDF text / text files and run local OCR on images/scanned pages where supported.
- [ ] Make importing bundled synthetic samples an easy simulator fallback.

### T12 — iPhone camera scanning and review

- [ ] Integrate native multipage document scanning on supported devices, with cancel/error handling.
- [ ] Allow page preview and native retake/crop/reorder behavior available from the capture flow.
- [ ] Preserve scans as source images/PDF and route them through the same ingestion pipeline.
- [ ] Show source plus extracted text, uncertainty or unreadability, and a correction/rescan path.
- [ ] Explain simulator camera unavailability and offer sample import; do not fake camera capture.

### T13 — Automatic per-record memory and clean formatting

- [ ] Start local extraction/summary processing automatically after a usable upload.
- [ ] Generate a deterministic source-based local summary/excerpt with explicit demo/provider-unconfigured labeling; never pretend Gemini ran.
- [ ] Show staged processing, ready/partial/review-needed/failure states truthfully.
- [ ] Render consistent record headers, summary, relevant structured facts, notes, source access, and original text.
- [ ] Retain original wording for dates, values, units, doses, and negations; do not silently invent corrections.

### T14 — Record editing, deletion, and provenance

- [ ] Edit title/date/extracted text/notes with validation and persistence.
- [ ] Open originals and linked evidence at a useful page or text location.
- [ ] Delete selected records with confirmation and remove their future retrieval eligibility.
- [ ] Mark affected reports stale after source edits/deletion; show missing evidence rather than silently keeping unsupported content.

## E. Appointments and pre-visit reports

### T15 — Visit list and detail

- [ ] Separate upcoming and past visits with empty states and readable appointment metadata.
- [ ] Create/edit date, time/timezone, provider/clinic, visit type, concern, goal, and user questions.
- [ ] Validate required values and persist changes.
- [ ] Keep preparation, booking context, recording, transcript, and after-visit notes reachable from one visit detail page.

### T16 — Relevant history selection

- [ ] Implement a testable local relevance engine over summaries, structured tags, and original text.
- [ ] Use visit goal/type/concern and user-pinned records; include relevant active context such as medications/allergies/implants without blanket body-part exclusion rules.
- [ ] Reopen selected source content for the report rather than relying only on summaries.
- [ ] Ensure at least two fixture goals produce different, sensible evidence sets, including an older relevant procedure/implant case.

### T17 — Pre-visit report generation and editing

- [ ] Generate a concise visit goal, relevant history, supporting timeline/facts, suggested questions, uncertainty/gaps, and source list.
- [ ] Clearly label local/demo-generated output; distinguish source facts, user notes, and proposed discussion questions.
- [ ] Support editing questions/notes, pinning or including relevant records, and regeneration.
- [ ] Preserve user edits and identify stale versions after visit/source changes.
- [ ] Do not diagnose, prescribe, or represent missing documentation as proof of absence.

### T18 — Evidence navigation and PDF sharing

- [ ] Every displayed source reference resolves to the correct existing record and useful page/timestamp context.
- [ ] Export a formatted brief using native PDF rendering with clean page breaks, readable type, dates, and provenance.
- [ ] Present the native share sheet; no automatic clinician sending.
- [ ] Inspect an exported sample PDF visually and verify text is not clipped/missing.

## F. Automated booking prototype

### T19 — Booking request and authority review

- [ ] Collect clinic name/phone, appointment reason, allowed dates/times/timezone, provider/location preferences, and constraints.
- [ ] Show a concise review before the simulated request begins; label the flow as demo/no real call.
- [ ] Keep the future outbound call interface separate from the iPhone UI; provider keys remain server-side.

### T20 — Booking state machine and outcomes

- [ ] Implement draft/authorized/queued/calling/proposed/confirmed/needs-user/failed states where appropriate.
- [ ] Provide deterministic success and needs-help/failure demo paths.
- [ ] Confirm only within allowed demo constraints; save a coherent appointment with provenance.
- [ ] Repeated completion/callbacks do not create duplicate appointments or attempts.
- [ ] Unknown/failed attempts have edit/retry/help actions and never dial a real number.

### T21 — Future ElevenLabs/Twilio contract

- [ ] Define outbound request, provider IDs, tool/callback payloads, authentication expectations, idempotency, and reconciliation behavior.
- [ ] Document ElevenLabs model/configuration constraints and the distinction between call-loop speech and separate appointment transcription.
- [ ] Keep live connector state explicitly unconfigured with a useful setup guide; do not claim live booking verification.

## G. Recording, transcription, and post-visit memory

### T22 — Native recording controls and audio storage

- [ ] Ask microphone permission when starting actual capture; present consent acknowledgement.
- [ ] Start/pause/resume/finish with visible state and elapsed time; avoid accidental navigation loss.
- [ ] Handle unavailable/denied input, interruption, and save failures with clear recovery.
- [ ] Save captured audio locally and support playback/deletion; do not access arbitrary cellular-call audio.

### T23 — Transcript and sample-visit demonstration

- [ ] Include a clearly fictional sample recording/transcript flow usable without external transcription APIs.
- [ ] Distinguish bundled sample text from new microphone audio; new audio never receives an unrelated invented sample transcript.
- [ ] Render timestamped segments, speaker labels/roles, text correction, and playback positioning when matching audio exists.
- [ ] Preserve recording-relative offsets and avoid conflating speakers across chunks.
- [ ] Document local Whisper/Apple Speech and cloud transcription adapter choices without integrating unnecessary vendors.

### T24 — Post-visit summary and history integration

- [ ] Show what was discussed, documented next steps, and unresolved questions from the actual sample/entered transcript.
- [ ] Link statements to transcript segments, preserve edits, and attach the memory to the visit.
- [ ] Make the post-visit memory available to future visit preparation as an explicitly typed record.
- [ ] Keep tasks/medication instructions user-reviewable and avoid fabricating medical guidance.

## H. Tiger PostgreSQL server and configuration

### T25 — Swift backend and transport contract

- [ ] Implement a runnable Swift backend with health/status and domain persistence/synchronization endpoints needed by the prototype.
- [ ] Provide local development storage without credentials plus an explicit PostgreSQL mode; no silent fallback from a broken production database to demo data.
- [ ] Validate request sizes/types, authenticate the configured development/API boundary, and scope reads/writes to owner identity.
- [ ] Make errors predictable and actionable; keep API/model/phone keys out of the client.

### T26 — Tiger database schema and migrations

- [ ] Create versioned PostgreSQL schema for users/profiles, records and sources, summaries/facts/evidence, visits/reports, booking attempts, recordings/transcripts, and persisted state required by the chosen contract.
- [ ] Store prototype source attachments/audio in the agreed Tiger-compatible strategy, preserving ownership and source identity; document scaling limits.
- [ ] Add relationships/constraints/indexes, transactional writes, unique idempotency keys, and safe migration behavior.
- [ ] Prepare connection/TLS/configuration instructions and representative seed/import path. Do not claim live Tiger connectivity without credentials.

### T27 — App/server integration readiness

- [ ] Test the app repository/transport boundary against local backend behavior or a controlled transport fixture.
- [ ] Cover create/read/update/delete, owner isolation, conflict/revision behavior, and failed transport recovery as applicable.
- [ ] Document what changes when the user adds Tiger/API configuration and what remains demo-only.
- [ ] Verify the root `.env` is zero bytes and ignored; `.env.example` contains placeholders only.

## I. Independent fictional demo dataset

### T28 — Coherent sample patient and records

- [ ] Create a fictional identity with no real personal medical information and clear synthetic labels.
- [ ] Include multiple dated records: general history/medication/allergy context, labs, an earlier procedure/implant or orthopedic record, a distinct unrelated episode, recent visit notes, and a post-visit transcript.
- [ ] Ensure dates/values/source references are internally consistent and any deliberately conflicting field is explicitly modeled for review.
- [ ] Provide at least two appointment goals with a documented expected relevant-record set.

### T29 — Standalone importable artifacts and fixture generator

- [ ] Save separate fake medical report PDFs/text/image scans where useful, plus machine-readable fixture metadata.
- [ ] Use the same IDs/content in bundled app fixtures and standalone sources so the demo remains reproducible.
- [ ] Render/inspect sample PDFs, verify extractable text, and include a deliberate OCR/review example.
- [ ] Keep generators and instructions so the dataset can be reset or expanded without hand-editing conflicting copies.

### T30 — Presentation demo script

- [ ] Write a short walkthrough: seeded Summary → visit report → original evidence → import sample → correct/reprocess → different visit goal → simulated booking → sample visit memory → PDF share.
- [ ] Include a reset path, fallback steps for hardware/network limitations, and a plain list of simulated versus functional features.

## J. Review loops, checkpoints, and verification

### T31 — Claude architecture review

- [ ] Give Claude a bounded packet covering user scope, completion gates, palette/style, data contract, offline/demo boundary, and proposed architecture.
- [ ] Ask for material omissions, likely failure modes, and a concise implementation review checklist; no unrelated repo work or unbounded subagents.
- [ ] Manually assess findings, record decisions, and update specs/implementation where needed.

### T32 — Claude implementation review in an isolated worktree

- [ ] Create a review worktree from the current checkpoint and configure the Claude session for that Reva worktree when appropriate.
- [ ] Review actual code paths for persistence, source/report consistency, imports, booking duplication, recording provenance, server ownership, and setup honesty.
- [ ] Scope follow-up fixes to explicit findings. Keep parent integration work separate from the reviewed snapshot.
- [ ] Apply reviewed fixes through commits/cherry-picks or explicit patches, inspect the final diff, and rerun affected checks.

### T33 — Functional tests and recovery checks

- [ ] Test meaningful domain behavior: relevance differences, pinned records, stale reports, deletion, valid references, persistent mutations, and deterministic demo reset.
- [ ] Test server configuration and owner isolation, payload validation, persistence, and duplicate/conflict handling.
- [ ] Test native import/extraction/error routes and local recording/sample provenance where testable.
- [ ] Avoid adding tests that merely repeat implementation; record what each important test proves.

### T34 — Running-app and visual verification

- [ ] Inspect all major screens in the running iPhone app, not only source or screenshots of a separate mockup.
- [ ] Exercise the complete presentation route, including working buttons and navigation.
- [ ] Verify persistence through app termination/relaunch and explicit demo reset.
- [ ] Check light/dark appearance, smaller iPhone width, large text, empty/error/review states, source links, and export layout.
- [ ] Record actual simulator evidence separately from physical camera/microphone requirements and live-provider exceptions.

### T35 — Final focused review and criterion audit

- [ ] Give Claude a bounded final delta/acceptance review; use evidence and avoid exhausting the plan on cosmetic nitpicks.
- [ ] Primary agent manually reviews the integrated code and every completion gate.
- [ ] Fix material missing functionality or contradicting evidence; do not redefine criteria around the subset that happens to work.
- [ ] Explicitly list manual external steps and hardware-only limitations. Everything else must be implemented and verified for completion.

### T36 — Checkpoint commits and durable history

- [ ] Commit meaningful stages: setup/palette, native/data foundation, records/preparation, booking/recording, server/fixtures, review fixes, final verified prototype.
- [ ] Before each commit inspect scope, ensure secrets/build artifacts are excluded, and record checks and remaining work.
- [ ] Append checkpoint hashes and rationales in the progress/edit-history log; preserve review packets and findings.
- [ ] Use worktrees for subsequent review/fixes without overwriting the main working tree or losing uncommitted work.

### T37 — Final delivery and GitHub push

- [ ] Complete T38 immediately before final commit/push.
- [ ] Update README with build/run, Xcode project, simulator/device instructions, demo script, architecture, Tiger/API setup, and known limitations.
- [ ] Recheck `.env`, tests/build, working tree, latest source versions, and final review findings.
- [ ] Push the completed verified commits to the configured GitHub repository and verify remote branch/HEAD alignment.
- [ ] Provide the user a concise result with runnable entry point, demo instructions, verification evidence, and remaining manual setup.
- [ ] Mark the active goal complete only after all required gates are proven. Otherwise keep it active and continue meaningful work within the resource policy.

### T38 — As-built full stack visualization, immediately before pushing

- [ ] Create `docs/architecture.md` after implementation and final review, before the final GitHub push.
- [ ] Include diagrams for the native client, app state/repository, Swift server, Tiger PostgreSQL/data attachments, device services, and configured/deferred external connectors.
- [ ] Visualize document intake/extraction/summary/retrieval/report, simulated/live booking boundary, and recording/transcript/post-visit memory flows.
- [ ] Distinguish what actually works locally, what is simulated, and what requires manual API/database setup. Avoid presenting the original planned architecture as implemented without evidence.
- [ ] Include a compact stack inventory and relevant code/setup links; link the document from README.
- [ ] Check diagrams against final source/configuration and include the document in the final checkpoint commit before pushing.

## K. Implementation dependency order

1. T01–T04: readiness, Claude project, source control, task packets and shared contracts.
2. T05–T09: native foundation, selected design, navigation, domain and persistence.
3. T10–T18: records, scanning/import, memory, visits, relevant reports and sharing.
4. T19–T24: booking and recording/post-visit flows.
5. T25–T30: backend/Tiger preparation and the separate demo dataset can run in parallel with app work once contracts are fixed.
6. T31–T36: reviews, tests, visual checks and commits occur throughout; isolated review worktrees follow meaningful checkpoints.
7. T38, then T37: verify and visualize the as-built stack, final evidence-based audit, push, and delivery.

**Current status:** setup/palette/planning checkpoint exists. The native preflight build was started before the latest instruction; its live execution handle must be polled rather than restarted. No full interface or backend completion is claimed. Resume only after this list and its goals-file mirror have been written.
