# Track 15 — Architecture cleanliness and measured performance

**Codex continuation.** This report completes a missing Fable track after the user reported Claude account limits. It was produced by the existing Codex subagent `/root/symptom_entries`; no new Fable worker or Fable/Ultracode execution is claimed. Model/effort are inherited from the parent Codex task and were not independently selectable here.

**Snapshot:** `fable-audit-20260912-114322 @ cfe0997+wip`, source `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`. Only this frozen source, the audit packet, and saved evidence were read. `START-HERE.md`, checklist, assigned track instructions, finding schema, supervisor brief and Addendum 1, refreshed frozen specification, and handoff ledger were consulted. No application edits, Git operations, builds/tests, listeners, UI controls, credentials, or live services were used by this continuation. Existing runner outputs are attributed to their actual producer. Findings require independent coordinator validation.

## Result

**No new actionable architecture or performance defect survives this bounded pass.** `track-15-findings.json` is intentionally empty. Large stores/CSS and installed OCR size are not defects by themselves. Existing functional findings from other domains remain for their owners and validators; this track does not duplicate them or imply they were refuted.

Responsibility boundaries are practical: native UI → operation-specific AppStore → pure Core/local repository/provider client; browser UI → shared queued store → validated domain/IndexedDB/API; server routes → owner storage/provider adapters. Browser and native are distinct interfaces with intentionally mirrored JSON/evidence rules, not a shared compiled UI. Changes to the mirrored contracts remain a coordination cost addressed by compatibility goldens and captain ownership.

## Inventory and manual-review boundary

The appended inventory enumerates first-party production source in native, server, browser, browser runtime scripts, and root scripts; test files are listed by their owning test trees rather than treated as production. Inventory is not a claim of full semantic inspection of every line.

Manual sampling concentrated on `State/AppStore.swift`, browser `core/store.ts`, `repository.ts`, `api.ts`, report/validation boundaries, `Device/DocumentImportService.swift`, `ReportPDFRenderer.swift`, the state/lifecycle sections of `AudioServices.swift`, server `PostgresStore.swift`, `Providers/VoiceCalls.swift`, `GeminiService.swift`, shared browser CSS/UI, the dependency manifests, and explicit team ownership. Domain-specific reviews provide deeper coverage elsewhere. Not every unused CSS selector/import or native UI callback was independently checked here.

## Evidence and coverage

| Requirement | Status | Evidence and boundary |
| --- | --- | --- |
| B01 | Pass | Runner `r1-02-structure-check.log`: 71 Swift and 53 browser files have contracts and sections. Explicit-file Swift lint `r1-03b-swift-format-lint-explicit.log`: 86 files, no diagnostics. `r1-05-format-check.log` passes browser formatting. Sampled contracts name real persistence/provider/resource effects. These mechanical passes do not prove every comment accurate. |
| B02 | Pass | Native `AppStore.swift:12–38` owns observable state; browser `store.ts:106–121` serializes draft changes and publishes after repository commit. `repository.ts:111–160` checks revision and commits snapshot/originals atomically. Pure rules and provider transports have separate files. No hidden alternate state owner was identified in this sample. |
| B03 | Pass | `docs/team-workflow.md` names three people and captain-owned Core/store/theme/generators. Browser Records/Profile and Visits are separate lanes, while shared store edits go through one owner. The native/browser preparation ownership difference is explicitly documented. |
| B04 | Unverified | No demonstrably dead production package or debug-patient logging was found in sampled paths. Generated browser assets/build directories are ignored. This was not a whole-repository dead-code/CSS-usage analysis; file length alone generated no finding. The stale AccountGate deferral comment belongs to WIP scope reconciliation. |
| B05 | Unverified | Sampled services have typed/explicit errors, validated input, owner checks, finite work and cancellation owners. Cross-domain reports contain concrete race/IO findings; this sample cannot certify all failure paths. Browser/native DTO duplication is intentional but requires continued golden/round-trip checks. |
| M01 | Unverified | Saved build inventory establishes artifact/chunk sizes, not patient-scale runtime latency or peak memory. No representative large PDF/audio/store benchmark or repeated-worker heap trace was available. Specific bounded work below is source-reviewed, with performance impact left unmeasured. |
| M02 | Pass | Fresh audit runner `r1-17-optimization-checks.log` reproduces native R1 stale sync/generation, R2 collision/rollback, R3 stale provider discovery, R5 lookup order, R6 audio upload dedup/MIME/retry, and R9 candidate/byte budgets. Do not reopen them from obsolete reviews without a new trigger. |
| M03 | Pass | Focused screens/editors and pure helpers provide useful boundaries. No arbitrary splitting or framework abstraction is recommended. Investigate the measured hotspot first if later timings show one; preserve atomicity, evidence identity, and cancellation. |
| N01 | Pass | Fresh runner executes meaningful production-boundary tests: native source/report/provider behavior, browser IndexedDB CAS and original integrity, queued edits/delayed results, source signature goldens, audio lifecycle, and local HTTP owner/CAS tests. Mocked outcomes remain labeled; the clean asset-prerequisite failure is RVA-16-002. Gaps are listed below. |

## Measured facts, without extrapolation

`evidence/r1-21-dist-inventory.log` measures **50,729,813 raw bytes** in 36 built files. The initial index script is **390,616 bytes raw / 115,996 bytes gzip(level 6)** in that log; CSS is **34,014 / 7,827**. PDF API, PDF worker and Tesseract wrapper are separate outputs. OCR resources total **47,773,887 raw bytes**, but this is installed/deployment output, **not** an initial-page download. `extractDocument.ts:171,244` dynamically imports OCR/PDF code; workers and language assets are requested only for relevant intake. Gzip inventory is an offline compression calculation, not proof the Node wrapper serves compressed responses.

The matrix's `readyMs` fields are navigation-readiness observations under the runner's capture procedure. They do not measure cold startup, search/relevance cost, provider latency, OCR throughput, or render responsiveness; no performance rating is inferred from them. Build durations in runner logs are toolchain/build evidence, not app performance.

Source-bounded work includes 24 PDF pages/120 KB text/one OCR worker with explicit deadlines (`extractDocument.ts`), 16 MiB originals and a 4 MiB serialized browser snapshot (`api.ts`, `repository.ts:117–122`), source candidate/byte limits, and sequential owner transactions. Limits establish finiteness, not acceptable latency. Browser edits clone/validate the snapshot, then persistence validates/clones/stringifies it again (`store.ts:114–116`, `repository.ts:117–118`); this is repeated O(snapshot size) work up to a documented bound. Without a representative input measurement it is not a confirmed UI-stall defect and should not be “optimized” by removing validation.

Native `ReportPDFRenderer.swift:34–41` is main-actor work with ceilings of 200,000 characters/100 pages and two pagination passes. Track 05 already records its unmeasured cost as an evidence gap; this track does not double-count it. PostgreSQL query structure is owner-scoped and transactional, but query timing, execution plans, and peak result memory remain unverified without an authorized ephemeral database.

## Verification gaps and smallest next evidence

Existing audit evidence has 77 browser Vitest tests after assets, 7 Node wrapper tests, 43 passing root Swift tests with one gated skip, one separately passing real local client/server test, and 31 passing server tests with the real PostgreSQL test gated off. These counts do not include a native UI automation suite, large-input browser performance benchmark, live provider semantics, or account-session delta coverage.

If further optimization work is authorized, first measure a synthetic workspace near the existing 4 MiB bound through production search/report/mutation logic, recording input bytes, operation time and memory without changing limits. Separately time a representative OCR cancellation/restart and native near-ceiling PDF export. No arbitrary latency threshold, fabricated result, caching mandate, or live-database load test is supplied here. The coordinator owns any new verification.

## Production inventory

The following paths were inventoried, not all semantically audited. Native/server tests are under `Tests/` and `server/Tests/`; browser test files and fixtures were separately consulted for outcome coverage.

```text
apps/ios/Reva/Core/BookingEngine.swift
apps/ios/Reva/Core/LocalRepository.swift
apps/ios/Reva/Core/Models.swift
apps/ios/Reva/Core/ProviderClient.swift
apps/ios/Reva/Core/ProviderContracts.swift
apps/ios/Reva/Core/ReportEngine.swift
apps/ios/Reva/Core/ServerClient.swift
apps/ios/Reva/Core/SymptomEntry.swift
apps/ios/Reva/Device/AudioServices.swift
apps/ios/Reva/Device/DocumentImportService.swift
apps/ios/Reva/Device/DocumentScanner.swift
apps/ios/Reva/Device/ReportPDFRenderer.swift
apps/ios/Reva/Features/Preparation/ReportEditorView.swift
apps/ios/Reva/Features/Preparation/ReportView.swift
apps/ios/Reva/Features/Preparation/VisitDetailView.swift
apps/ios/Reva/Features/Preparation/VisitEditorView.swift
apps/ios/Reva/Features/Preparation/VisitsView.swift
apps/ios/Reva/Features/Profile/MedicalProfileEditor.swift
apps/ios/Reva/Features/Profile/MedicalProfileView.swift
apps/ios/Reva/Features/Records/AddRecordView.swift
apps/ios/Reva/Features/Records/RecordDetailView.swift
apps/ios/Reva/Features/Records/RecordEditorView.swift
apps/ios/Reva/Features/Records/RecordsView.swift
apps/ios/Reva/Features/Records/SourcePreview.swift
apps/ios/Reva/Features/Records/SymptomEntryDetailsView.swift
apps/ios/Reva/Features/Records/SymptomEntryEditorView.swift
apps/ios/Reva/Features/Shared/RecordRow.swift
apps/ios/Reva/Features/Shared/RootView.swift
apps/ios/Reva/Features/Shared/SettingsView.swift
apps/ios/Reva/Features/Shared/SummaryView.swift
apps/ios/Reva/Features/Shared/Theme.swift
apps/ios/Reva/Features/Shared/ViewComponents.swift
apps/ios/Reva/Features/Shared/VisitRow.swift
apps/ios/Reva/Features/Shared/WelcomeView.swift
apps/ios/Reva/Features/Visits/BookingEditorView.swift
apps/ios/Reva/Features/Visits/BookingStatusView.swift
apps/ios/Reva/Features/Visits/LiveBookingEditorView.swift
apps/ios/Reva/Features/Visits/LiveBookingStatusView.swift
apps/ios/Reva/Features/Visits/RecordingDetailView.swift
apps/ios/Reva/Features/Visits/RecordingNotesEditor.swift
apps/ios/Reva/Features/Visits/RecordingSessionView.swift
apps/ios/Reva/Features/Visits/TranscriptTextEditor.swift
apps/ios/Reva/RevaApp.swift
apps/ios/Reva/State/AppStore+AI.swift
apps/ios/Reva/State/AppStore+Bookings.swift
apps/ios/Reva/State/AppStore+LiveCalls.swift
apps/ios/Reva/State/AppStore+Profile.swift
apps/ios/Reva/State/AppStore+Providers.swift
apps/ios/Reva/State/AppStore+Recordings.swift
apps/ios/Reva/State/AppStore+Records.swift
apps/ios/Reva/State/AppStore+Symptoms.swift
apps/ios/Reva/State/AppStore+Sync.swift
apps/ios/Reva/State/AppStore+Transcription.swift
apps/ios/Reva/State/AppStore+Visits.swift
apps/ios/Reva/State/AppStore.swift
apps/web/scripts/prepare-assets.mjs
apps/web/scripts/serve.mjs
apps/web/src/App.tsx
apps/web/src/components/Brand.tsx
apps/web/src/components/ui.tsx
apps/web/src/core/RevaContext.tsx
apps/web/src/core/api.ts
apps/web/src/core/domain.ts
apps/web/src/core/models.ts
apps/web/src/core/mutations.ts
apps/web/src/core/repository.ts
apps/web/src/core/store.ts
apps/web/src/core/symptoms.ts
apps/web/src/core/validation.ts
apps/web/src/features/Dashboard.tsx
apps/web/src/features/SettingsPage.tsx
apps/web/src/features/profile/MedicalProfilePage.tsx
apps/web/src/features/records/ImportDialog.tsx
apps/web/src/features/records/RecordDetail.tsx
apps/web/src/features/records/RecordEditor.tsx
apps/web/src/features/records/RecordsPage.tsx
apps/web/src/features/records/SourcePreview.tsx
apps/web/src/features/records/SymptomDialog.tsx
apps/web/src/features/records/extractDocument.ts
apps/web/src/features/records/recordPresentation.tsx
apps/web/src/features/visits/BookingPanel.tsx
apps/web/src/features/visits/RecordingCapture.tsx
apps/web/src/features/visits/RecordingDetail.tsx
apps/web/src/features/visits/RecordingsPanel.tsx
apps/web/src/features/visits/VisitBrief.tsx
apps/web/src/features/visits/VisitDetail.tsx
apps/web/src/features/visits/VisitEditor.tsx
apps/web/src/features/visits/VisitsPage.tsx
apps/web/src/features/visits/useVisitRecorder.ts
apps/web/src/features/visits/visitDates.ts
apps/web/src/features/visits/visitEdits.ts
apps/web/src/landing/AccountGate.tsx
apps/web/src/landing/Landing.tsx
apps/web/src/main.tsx
apps/web/src/styles/components.css
apps/web/src/styles/features.css
apps/web/src/styles/landing.css
apps/web/src/styles/layout.css
apps/web/src/styles/tokens.css
scripts/build_overview_packet.py
scripts/check_code_structure.py
scripts/check_optimization_fixes.py
scripts/check_provider_api.py
scripts/extract_palette.py
scripts/generate_project.py
scripts/mock_provider_server.py
scripts/run_server.py
scripts/test_client_server.py
server/Sources/RevaServer/Configuration.swift
server/Sources/RevaServer/Deadline.swift
server/Sources/RevaServer/HTTP.swift
server/Sources/RevaServer/LocalFileStore.swift
server/Sources/RevaServer/Migrations/001_snapshot.sql
server/Sources/RevaServer/Models.swift
server/Sources/RevaServer/PostgresStore.swift
server/Sources/RevaServer/Providers/GeminiModels.swift
server/Sources/RevaServer/Providers/GeminiService.swift
server/Sources/RevaServer/Providers/GeminiTransport.swift
server/Sources/RevaServer/Providers/ProviderConfiguration.swift
server/Sources/RevaServer/Providers/ProviderRoutes.swift
server/Sources/RevaServer/Providers/VoiceCalls.swift
server/Sources/RevaServer/Providers/VoiceRoutes.swift
server/Sources/RevaServer/Providers/VoiceTranscription.swift
server/Sources/RevaServer/Providers/VoiceTransport.swift
server/Sources/Run/EntryPoint.swift
```
