# Reva final acceptance audit

**Date:** September 12, 2026. **Scope:** read-only acceptance review of the current working tree after checkpoint `7d0f585`; only this report was written. No build, test, simulator action, code change, or commit was performed by this audit. Primary simulator verification and narrowly scoped fixes continue concurrently, so later source changes can supersede the findings below.

The local patient journey is substantially implemented and has concrete verification evidence. Three narrow local task-list gaps remain in the code inspected below. They are distinct from manual provider/device prerequisites and do not imply a production-readiness requirement for this hackathon prototype.

## Evidence and completion gates

Read the binding completion criteria/task list, current app/Core/device/backend code, root and server READMEs, verification notes, review decisions, and recent Git history. Recent checkpoints are `7725fc7` (criteria/palette/plan), `eb2ec3a` (native journeys and server), and `7d0f585` (reviewed evidence/edit fixes). The root `.env` was read-only checked as **0 bytes** and Git-ignored.

| Gates | Acceptance evidence and remaining boundary |
| --- | --- |
| 1, 4, 5, 6 | Native build/install/launch are recorded. Primary additionally verified import → review → save, metadata-only edit preserving pages and synthetic origin, brief staleness, and persisted sample memory across relaunch. Local repository validates before atomic snapshot replacement and retains a valid backup. |
| 7, 8 | Exact fixture evidence sets, pins, page-2 implant evidence and laboratory values are covered by the later Swift verification record. Primary opened the actual implant PDF on page 2 and verified question persistence through regeneration. Long-import relevance has the gap below. The item-driven PDF sheet/date-picker fixes and final in-app export inspection are already active primary work, not new audit blockers. |
| 9, 10 | Primary verified queued → proposed → confirmed booking exactly once, explicit sample transcript/memory save, original completed-visit association, no fabricated audio, and relaunch persistence. Failed/needs-user paths and capture controls are wired. Transcript correction/source navigation has the narrow gap below; physical microphone/camera execution remains a manual exception. |
| 11 | The native URLSession client/server test exercises actual local HTTP, all state domains, nine original attachments, authentication/owner separation, revisions/conflicts and deletion tombstones. Server local tests/restart/no-fallback checks and the PostgreSQL schema/adapter exist. Live Tiger execution remains explicitly gated. Developer transfer is not an atomic source-plus-snapshot operation; see the limitation below. |
| 12, 13, 15, 16 | Empty ignored configuration, reproducible synthetic sources/fixtures, bounded contributor packets, Claude Fable 5.1 architecture/implementation review, isolated review worktree and targeted provenance revision are present. Earlier client verification failures were superseded by primary fixes and later passing evidence. |
| 2, 3, 14, 17 | Exact palette and adaptive dark roles are in code; major navigation and several full flows have execution evidence. Dark/smaller-device/search/appointment/export checks are already underway with the primary. This report does not relabel those scheduled checks as missing implementation. The search code omission below is independently visible in source. |
| 18, 19 | README/run instructions, checkpoint history and review evidence exist. Final ledger reconciliation, as-built `docs/architecture.md`, final commit/push and remote verification are intentionally last-stage work. The architecture diagram is correctly deferred until immediately before push. |

Latest durable progress records 24 passing local Core tests and a separately passing real-client/server test; the verification index's older count of 23 explicitly predates an added regression. A further date regression is now in source. This audit did not rerun them or infer a new final count. The primary should use its latest actual run when completing the ledger.

## Three local gaps

### 1. P2 — Relevant facts after a short excerpt cannot select an imported record

**Gate 7; T16.** [ReportEngine.swift](../../apps/ios/Reva/Core/ReportEngine.swift#L39) indexes only title, tags and summary. `localExcerpt` takes at most 24 lines/1,800 characters ([line 5](../../apps/ios/Reva/Core/ReportEngine.swift#L5)); manual imports generally have no clinical tags and use that excerpt as their summary. A generically titled multipage source whose relevant implant/laboratory fact appears after that prefix is omitted unless pinned, even though its full extracted `record.text` contains the visit term. Page selection reopens full source text only after selection, so it cannot recover this omission. This conflicts with T16's explicit requirement to use original text alongside summaries and tags.

**Bounded remedy:** include bounded full-source text or a full-document term index in record selection while retaining the existing fixture exclusion assertions. A single focused regression with a relevant fact beyond the excerpt boundary is sufficient; no broader AI integration is needed. Pinning remains a usable manual fallback, not proof that automatic selection covers the source.

### 2. P2 — Transcript correction and return-to-source navigation are absent

**Gate 10; T23/T24.** [RecordingViews.swift](../../apps/ios/Reva/UI/RecordingViews.swift#L74) renders transcript segments as read-only text. The only editor binds `recording.summary` and expressly says it does not change the transcript ([line 92](../../apps/ios/Reva/UI/RecordingViews.swift#L92)). Therefore the requested local transcript text-correction flow is absent, including for the sample; this is unrelated to live transcription credentials.

[AppStore.saveMemory](../../apps/ios/Reva/State/AppStore.swift#L99) preserves a timestamped text copy and sample summary with textual segment IDs, which is useful and has been manually verified. The resulting MedicalRecord has no recording/segment source field or source filename, and [RecordDetailView](../../apps/ios/Reva/UI/RecordsView.swift#L46) supplies no route back to the originating transcript. T24's source linkage is therefore textual/manual rather than navigable. Do not describe this as fully implemented segment-level evidence navigation.

**Bounded remedy:** add a correction surface retaining stable segment IDs/relative offsets and a memory-to-recording source link. Preserve the independent original-audio/sample distinction. If scope is deliberately held at the current behavior, explicitly record “sample transcript is read-only; notes are editable; memory source references are textual” as a remaining local limitation instead of classifying it as hardware/provider setup.

### 3. P2 — Summary and displayed-date searches are omitted from the search index

**Gates 3/14; T10.** [RecordsView.filtered](../../apps/ios/Reva/UI/RecordsView.swift#L16) searches title, provider, tags and extracted text, but not `record.summary` or `record.date`. T10 explicitly includes summaries, and the UI prompt promises date search. A date changed through the record editor can be displayed in the record row yet return no result when searched if that new date does not appear in the original text. This is a source-level omission separate from the ongoing visual search check.

**Bounded remedy:** include the summary and stored/displayed date text in the same search index. Existing filters and native search UI can remain unchanged.

## Honest prototype limitations, not additional completion blockers

- **Developer sync has separate attachment and snapshot commits.** [AppStore.sync](../../apps/ios/Reva/State/AppStore.swift#L118) uploads originals under filename-derived stable IDs before the snapshot compare-and-swap. If an existing same-named source has different bytes, a later 409 can leave uploaded bytes replaced while the previous server snapshot remains. Pull downloads first, then writes originals before saving the snapshot ([line 128](../../apps/ios/Reva/State/AppStore.swift#L128)); a disk/save failure can leave a partial file replacement. Normal imports use unique names, reducing collision exposure. [The server README](../../server/README.md#L47) already states these operations are separate transactions, and local transfers/conflicts are meaningfully tested. Retain that limitation in final claims: atomic local JSON persistence and rejected stale snapshots do not establish transactional rollback of every source file. Staging/versioned attachments would be a later improvement if this developer feature expands.
- **Manual exceptions are legitimate and already explicit.** Gemini/live speech, ElevenLabs/Twilio calls, authentication provisioning, Tiger credentials and actual hosted database tests, signing, physical camera/microphone capture and hardware interruptions are deferred. The sample has no matching audio. No new external account, paid service, model download or production deployment is needed to complete the current local prototype.

Before final delivery, reconcile stale status headings in `client-verification.md`, the older task-list “current status,” and the review-log statement that the targeted patch is pending with the later passing tests, applied checkpoint and primary simulator evidence. Preserve the historical failures as history and append their resolution; do not erase them or claim a fresh test run from this audit.
