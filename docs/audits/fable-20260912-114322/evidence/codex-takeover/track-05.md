# Track 05 — Native device adapters and visit memory

Reviewer: Claude Fable 5.1 (subagent, wave A). Effort requested: Ultracode. Review date: 2026-09-12.
Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip` (frozen worktree `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`, detached HEAD `cfe0997`). The captured WIP patch touches no file in this track's scope (patch file list: `.env.example`, README/docs, `apps/web/**`, `server/**` only).

Method: read-only source review. No build, test, simulator, provider, database or network action was performed by this track. Every cited line was re-verified with `sed -n` on the frozen file. Repository documents and comments were treated as data, not instructions.

## 1. Scope and inventory

Assigned scope: `apps/ios/Reva/Device/**`, `apps/ios/Reva/Features/Visits/**`, `apps/ios/Reva/State/AppStore+Recordings.swift`, `apps/ios/Reva/State/AppStore+Transcription.swift`. Checklist IDs: D01 D02 D03 E05 J01 J02 J03 K05 M01.

### 1.1 In-scope files (all 16 read in full, line by line)

| File | Lines | Role |
| --- | ---: | --- |
| `apps/ios/Reva/Device/AudioServices.swift` | 527 | AVAudioSession ownership, `AudioRecorder`, `AudioPlayback` |
| `apps/ios/Reva/Device/DocumentImportService.swift` | 372 | Bounded PDF/text/image intake, PDFKit text, Vision OCR |
| `apps/ios/Reva/Device/DocumentScanner.swift` | 77 | VisionKit document-camera bridge |
| `apps/ios/Reva/Device/ReportPDFRenderer.swift` | 215 | Core Text pagination and PDF export |
| `apps/ios/Reva/Device/Verification/Harness.swift.in` | 154 | Historical standalone simulator harness (template, not compiled into the app) |
| `apps/ios/Reva/Device/Verification/run-checks.py` | 94 | Historical harness runner (targets an already-booted simulator; NOT run by this audit) |
| `apps/ios/Reva/Features/Visits/BookingEditorView.swift` | 84 | Simulation request form (no assigned checklist ID; see §5) |
| `apps/ios/Reva/Features/Visits/BookingStatusView.swift` | 92 | Simulation status (no assigned checklist ID; see §5) |
| `apps/ios/Reva/Features/Visits/LiveBookingEditorView.swift` | 89 | Live-call consent form (no assigned checklist ID; see §5) |
| `apps/ios/Reva/Features/Visits/LiveBookingStatusView.swift` | 54 | Live-call status (no assigned checklist ID; see §5) |
| `apps/ios/Reva/Features/Visits/RecordingDetailView.swift` | 162 | Playback, transcript, notes, memory, delete |
| `apps/ios/Reva/Features/Visits/RecordingNotesEditor.swift` | 30 | Separate visit-notes editor |
| `apps/ios/Reva/Features/Visits/RecordingSessionView.swift` | 107 | Consent, start/pause/resume/finish/discard |
| `apps/ios/Reva/Features/Visits/TranscriptTextEditor.swift` | 74 | Words-only correction editor |
| `apps/ios/Reva/State/AppStore+Recordings.swift` | 131 | `save(_:)`, `loadSample`, `saveMemory` |
| `apps/ios/Reva/State/AppStore+Transcription.swift` | 46 | `transcribeRecording` |

Total in scope: 2,308 lines, 16 files, all fully read.

### 1.2 Shared interfaces consulted (outside scope; read to understand contracts, not reviewed)

Fully read: `Core/Models.swift`, `Core/LocalRepository.swift`, `Core/ReportEngine.swift`, `Core/ProviderClient.swift`, `Core/ProviderContracts.swift`, `State/AppStore.swift`, `State/AppStore+AI.swift`, `State/AppStore+Visits.swift`, `State/AppStore+Records.swift`, `Features/Records/AddRecordView.swift`, `Features/Records/SourcePreview.swift`, `Features/Preparation/ReportView.swift`, `Features/Preparation/VisitDetailView.swift`, `Info.plist`, `Resources/sample-transcript.json`, `docs/task-specs/device-services.md`, `docs/task-specs/transcript-correction.md` (lines 1-40), `docs/verification/README.md`.
Sampled only (greps / line ranges): `Core/ServerClient.swift` (36-75), `State/AppStore+Sync.swift` (30-110), `Features/Records/RecordDetailView.swift` (60-100 + greps), `Features/Records/RecordEditorView.swift` (greps), `Features/Shared/RootView.swift` (greps), `Features/Shared/Theme.swift` (13-24), `scripts/generate_project.py` (greps), `Tests/OptimizationChecks/StateChecks.swift` (1-30 + names), `Resources/seed.json` (structural summary via python), `docs/architecture.md` (168-192 + greps), `docs/reviews/*` (greps), `docs/completion-criteria.md` / `docs/mvp-goal.md` (greps), `apps/web/src/core/store.ts` and `api.ts` (grep for audio extensions only).

### 1.3 Evidence directory state at review time

`evidence/` contained only `00-snapshot-verification.log` (supervisor). No `commands.jsonl`, no build/test logs. All runtime claims in this report are therefore either source-proven or listed as evidence requests (§4). Historical verification text in `docs/task-specs/device-services.md` (26 harness checks) and `docs/verification/README.md` (17 transcript persistence checks, 6-page `orthopedic-brief.pdf`) is cited as **past evidence only**; it is not new evidence for this snapshot.

### 1.4 Status convention used in §2

A row is **Defect** when a `confirmed`/`candidate` finding of severity P1/P2 is attached. P3 candidates and suggestions are listed against a row without changing a **Pass**. **Unverified** means the behaviour could not be established from source and no evidence exists yet.

## 2. Checklist dispositions

| ID | Status | Files / lines | Evidence and notes | Findings |
| --- | --- | --- | --- | --- |
| **D01** Intake limits (empty/unsupported/malformed/corrupt/oversized; finite time/page/text/byte limits) | **Defect** (camera path, candidate P2); Files/photo/text paths Pass | `DocumentImportService.swift` 70-75 (limits), 77-109 (dispatch), 117-140 (1 MiB-chunk bounded read, `fileSize` precheck, empty check), 153-178 (UTF-8/UTF-16, NUL/control rejection), 182-230 (image: 40 MP cap, 2600 px thumbnail), 234-290 (PDF: `invalidPDF`, `lockedPDF`, 30-page cap, 10-page OCR cap, 200k-char budget with per-page slots), 292-319 (rotation-aware bounded raster), 323-351 (Vision errors -> warning, cancellation propagated); `DocumentScanner.swift` 52-60 | Byte, page, pixel, OCR-page and text limits are all finite and enforced before expensive work; cancellation is checked between pages and read chunks. There is no wall-clock cap, but work is bounded by the page/pixel caps (at most 10 Vision passes at <= 2600 px). Camera path: scanner accepts 30 pages and the caller assembles full-resolution pages into a PDF on the main actor before the 16 MiB check, with a Files-oriented error message (RVA-05-003; page count at which rejection occurs unmeasured, EV-05-02). Historical harness (device-services.md:73-76) exercised empty/binary/remote/oversized/corrupt/31-page/12-page-OCR/200k cases; not re-run here. | RVA-05-003 |
| **D02** Original bytes/filename/MIME/pages survive; same-name/fixture fallback cannot replace evidence silently | **Pass** (adapter scope); persistence/sync portions deferred to the state/sync tracks | `DocumentImportService.swift` 14-35 (`data` is the exact read bytes), 93/142-149 (safe leaf filename <= 180 chars, control chars stripped), 203-205 (MIME sniffed from bytes via ImageIO, not extension), 287-289 (pageCount/pageTexts); `AddRecordView.swift` 264-274 (UUID-prefixed attachment name, MIME/pageCount/pageTexts persisted; pageTexts dropped only when the user edited the text); `Models.swift` 187-190 (`safeFilename`); `LocalRepository.swift` 51-59, 67-81 (`stagePullAttachment` refuses conflicting bytes for an existing name); `AppStore.swift` 106-108 (`sourceURL` falls back to the bundle only by exact filename) | The adapter returns exact bytes (historical harness asserted `data == original` for text/PNG/PDF), a sanitised leaf filename and a byte-sniffed MIME. User attachments are `UUID-<leaf>` (AddRecordView:264), so a bundle fixture can never shadow a user file via the `sourceURL` fallback, and pull staging refuses differing bytes for the same name. Native `MedicalRecord` stores no SHA-256; attachment identity on the wire is `SHA256(filename)` (`ServerClient.swift:44-46`) — content hashing lives server-side (F05, other track). Observation (not filed, outside my files): Photos imports are always named `photo.jpg` even when the sniffed MIME is HEIC/PNG (`AddRecordView.swift:135`), so the stored extension can contradict `mimeType`. | — |
| **D03** PDFKit/Vision page mapping; mixed/scanned/obscured documents reviewable | **Pass** with a P3 candidate | `DocumentImportService.swift` 243-281 (one `pageTexts` slot per original page, including `""` beyond the text budget), 250-278 (embedded text preferred, weak pages OCR'd, per-page warnings name the page), 265 (OCR review warning), 294-319 (crop box + `/Rotate` handled), 336-339 (low-confidence warning); `ReportEngine.swift` 98-122 (page index -> `SourceReference.page`); `SourcePreview.swift` 57-92 (page navigation) | Page identity is preserved end to end (page N text -> `pageTexts[N-1]` -> citation `p. N` -> PDFKit `go(to:)`). Every OCR result carries the review warning; failures degrade to explicit warnings, never invented text. Weakness: a page with >= 20 embedded characters is never OCR'd and receives no warning, so fax/scanner text stamps hide the page image content (RVA-05-004; documented as a known limitation in device-services.md:101 but not surfaced to the user). Reading-order/OCR accuracy is not assumed perfect; originals stay authoritative. | RVA-05-004 |
| **E05** Native PDF export: only the fresh report, citations/questions/notes, usable pagination, no clipping; staleness respected | **Pass** (native, source level); artifact capture Unverified; browser print Deferred (web track) | `ReportView.swift` 29-34 (stale notice), 80-85 (`Share visit brief` disabled when `ReportEngine.isStale`), 98-126 (sections + `Source:` labels, questions, notes, `Sources` list with title/date/version); `ReportPDFRenderer.swift` 41-53 (empty-title, 200k-char, 200-section, 500-source caps), 60-82 (exact page ranges measured first, 100-page cap, `layoutFailed` on non-progress, orphan-heading avoidance with a proven-progress guard), 96-113 (per-page chrome, identity text matrix, flipped CTM, `CTFrameDraw` per measured range), 177-206 (header at y 32, rule at 733, footer/page `x / y` at 742 — disjoint from body 65-716); `SourcePreview.swift` 12-37 (preview + `ShareLink`) | Export is only reachable for a fresh report, so system share/print cannot receive a stale one. Pagination cannot loop (each iteration advances by a positive length; heading cut only when the heading starts after `position`) and cannot clip horizontally (word wrapping with character fallback in Core Text; measured visible ranges). Historical evidence: 16-page harness PDF with all 75 markers, footers on every page, upright glyphs after the text-matrix fix (device-services.md:77,83-85); archived 6-page app export `docs/verification/orthopedic-brief.pdf` from `d9ec87c` — the renderer's only later change (`30bd762`) is formatting/comments (`git diff -w` shows no logic change). This audit could not render that PDF (no poppler); see EV-05-03. Suggestions: legacy teal colour in the export (RVA-05-006); main-actor rendering cost unmeasured (RVA-05-009). | RVA-05-006, RVA-05-009 |
| **J01** Native denial/start/pause/resume/finish/cancel, interruptions, background, late permission clean up resources and preserve elapsed | **Defect** (confirmed P2 on the failed-finish path); lifecycle otherwise Pass | `AudioServices.swift` 36-63 (owner-checked session activate/release), 110-162 (permission await with attempt ID; cancel during await -> `CancellationError`, draft cleanup only when this attempt still owns it), 166-198 (pause keeps bytes/elapsed and releases session; resume re-activates, checks input, resumes with remaining duration), 202-228 (finish stops, verifies size/duration, transfers ownership), 232-253 (cancel deletes only the owned draft), 257-272 (200 ms ticker, one-hour bound), 282-322 (interruption/route-loss/background/media-reset -> pause, never auto-resume), 326-351 (stale-recorder callbacks ignored by identity); `RecordingSessionView.swift` 79-93 (`interactiveDismissDisabled`, discard confirmation, `onDisappear` pause); `Info.plist` 14 (mic usage string; no background audio mode, matching the documented pause-on-background) | Denial: `permissionDenied` with Settings guidance. Elapsed uses recorder time (`max(elapsed, currentTime)`) across pause/resume and is replaced by the verified file duration on finish. Interruptions, route loss, backgrounding and media-services reset all pause visibly; resumption is a user action. Defect: when `finish()` fails verification the recorder is left stopped with `reachedEnd = true` and `isRecording = true`, so Resume reports the one-hour limit and Finish repeats the failure; only Discard exits (RVA-05-002). Suggestion: finish success followed by a metadata-save failure orphans the audio without retry (RVA-05-008). Hardware behaviour (real microphone, headset/phone-call interruption, one-hour cap) is **Unverified** in this audit and documented as manual-only (device-services.md:99). | RVA-05-002, RVA-05-008 |
| **J02** Saved originals intact; playback reflects codec support; sample transcript has no matching audio and is never attached to new audio | **Pass** with a P3 candidate | `AppStore+Recordings.swift` 22-39 (`loadSample`: `audioFilename = nil`, `isSample = true`, bound to its fixture visit, reused if present); `RecordingSessionView.swift` 100-102 (new `VisitRecording` has default empty `segments`, `isSample = false`); `AppStore+Transcription.swift` 12-14 (`!original.isSample`, requires an existing audio file); `RecordingDetailView.swift` 25 (`FICTIONAL SAMPLE · NO AUDIO` badge), 29 (player only when a file exists), 56 (`ShareLink` on the original); `AudioServices.swift` 393-421 (file existence, finite duration, prepare; failures publish an error and pause), 128-142 (AAC 22.05 kHz mono 32 kbps -> 1 h <= ~14.4 MB, under the 16 MiB transport cap in `ProviderClient.swift:151`) | Sample separation holds on every path found (`isSample` is set only by `loadSample`; the transcribe path refuses samples; new recordings never receive fixture segments). Originals are written once by the recorder, verified on finish, never rewritten (corrections touch `segments[i].text` only; notes/transcription re-save the metadata object, not the file). Weakness: a browser-made WebM/Ogg recording pulled by sync fails `AVAudioPlayer` init and the message claims the file is "missing or damaged" (RVA-05-005; codec support itself Unverified on hardware). Cleanliness: `loadSample(visitID:)` ignores its parameter (RVA-05-007). Known, disclosed trade-off (not filed): "Delete recording" removes only the snapshot entry; the `.m4a` stays on disk, disclosed in Settings (`apps/ios/Reva/Features/Shared/SettingsView.swift:81`) and in `docs/reviews/review-log.md` item 7 — the delete dialog itself (`RecordingDetailView.swift:146-148`) does not say so. | RVA-05-005, RVA-05-007 |
| **J03** Corrections preserve segment ID/time/speaker/audio, separate notes, source links; repeated memory save updates a stable record and stales dependent reports | **Defect** (confirmed P2 via the notes-editor path); correction logic itself Pass | `AppStore+Recordings.swift` 42-73 (corrections keyed by segment ID; set equality with current IDs rejects a changed transcript; only `.text` assigned; 20k/200k bounds), 74-79 (stable id `memory-<recordingID>` with `sourceRecordingID` fallback; corrections never create a record), 80-123 (text rebuilt from segments with `[start–end] speaker:` prefixes; notes = origin + separate visit notes, preserved on correction; `isDemo` from `isSample`; version bumped only when text/summary changed); `TranscriptTextEditor.swift` 25-31, 62-70; `RecordDetailView.swift` 81-95 (`Open visit transcript` link / explicit missing-source notice); `ReportEngine.swift` 33-51 (signature covers every record's id/version/title/date/text/summary/tags/status, so a new or changed memory stales all saved briefs); `AppStore+Transcription.swift` 40-42 (existing memory refreshed after transcription) | The correction path is correct and guarded. The defect is the sibling notes path: `RecordingNotesEditor` saves a stale whole `VisitRecording`, so a transcript that lands while the notes sheet is open is erased (RVA-05-001). Suggestion: an idempotent "Update memory" resets an AI summary of the memory record and bumps the version, staling briefs without a source change (RVA-05-010). Historical evidence: 17 isolated AppStore checks for words-only corrections/atomic memory update (`docs/verification/README.md:18`, `docs/task-specs/transcript-correction.md`); the harness is not in the repository and did not cover the notes-editor overlap. | RVA-05-001, RVA-05-010 |
| **K05** Safari/Firefox/iPhone hardware, secure contexts, audio formats, export: verified or listed unverified | **Pass** (documented as unverified); hardware behaviour itself Unverified | `docs/architecture.md` 189 ("Physical capture/signing and Safari/Firefox hardware validation remain manual checks"; WebM/Ogg playback "depends on the receiving device"); `docs/task-specs/device-services.md` 99; `docs/verification/README.md` 47 | This track's share: iPhone microphone/camera/interruption/HEIC/AAC behaviour is explicitly listed as manual/unverified in the docs, which satisfies the checklist wording. No tool available to this audit can verify hardware (simulator use is prohibited). The one source-level issue found is the misleading codec-failure message (RVA-05-005). Browser secure-context/IndexedDB claims are the web track's remit. | RVA-05-005 |
| **M01** Measured efficiency (large record/PDF/audio cases, main-thread serialisation, memory retention) | **Unverified** — no measurements exist; two bounded requests filed | `ReportPDFRenderer.swift` 34-35, 63-81, 96-112; `AppStore+Transcription.swift` 18 (`Data(contentsOf:)` <= 16 MiB on the main actor before the await); `DocumentImportService.swift` 69 (actor), 250 (`autoreleasepool` per page), 211-230 (thumbnail decode); `AddRecordView.swift` 143-165 (main-actor PDF assembly of scan pages) | Concrete resource arguments only: import work is off the main actor and per-page memory is bounded (<= 2600 px raster, autoreleased); PDF export is O(characters) on the main actor with a 200k-char/100-page ceiling (RVA-05-009, EV-05-01); the scan path holds N full-resolution bitmaps plus the assembled PDF in memory on the main actor (RVA-05-003, EV-05-02). The 16 MiB synchronous audio read before transcription is bounded (tens of ms at flash speeds) and not filed. No efficiency claim in this track is presented as measured. | RVA-05-003, RVA-05-009 |

## 3. Findings (ordered by severity)

### RVA-05-001 — P2 — confirmed — Visit-notes editor saves a stale whole `VisitRecording` and can erase a transcript that arrived while the sheet was open
- Snapshot/file/line: `fable-audit-20260912-114322 @ cfe0997+wip`, `apps/ios/Reva/Features/Visits/RecordingNotesEditor.swift:26` (also `:15`; `apps/ios/Reva/State/AppStore+Recordings.swift:11-19`; `apps/ios/Reva/Features/Visits/RecordingDetailView.swift:74-80,127-128,140-142`; `apps/ios/Reva/State/AppStore+Transcription.swift:36-42`).
- Trigger: tap "Transcribe saved audio" (async provider call), open "Edit visit notes" while it runs (the button is not disabled by `isProviderBusy`), let transcription finish (segments/model/status saved), then tap Save in the notes sheet.
- Expected: only `summary` changes; the transcript saved a moment earlier remains (the editor's own header promises it "does not alter transcript words or audio").
- Actual: `@State var recording` is initialised once from the sheet's initial value; Save calls `store.save(recording)`, and `AppStore.save(_ recording:)` replaces the whole element by id. The stale draft (`segments = []`, `transcriptionModel = nil`, `status = "saved"`) overwrites the transcript. Because "Transcribe saved audio" is enabled only while `segments.isEmpty`, the only recovery is another paid transcription. An existing memory record keeps the transcript text until the next "Update memory", which then rebuilds it from notes only.
- Impact: loss of a paid Whisper transcript on a realistic overlap; the same last-writer-wins shape applies to a segments change arriving via sync pull while the sheet is open.
- Evidence: source lines above (all `sed -n` verified). The store already anticipates this overlap on the transcription side (`AppStore+Transcription.swift:19-20` re-reads `latest` and requires unchanged segments), and `TranscriptTextEditor` + `saveMemory` reject a changed transcript by ID-set equality (`AppStore+Recordings.swift:49-55`); the notes path has no equivalent guard.
- Refutation attempt: checked whether SwiftUI re-initialises `@State` when the parent's `recording` value changes; `State(initialValue:)` is applied only when the view identity is first created, so the draft stays stale for the sheet's lifetime.
- Confidence: high. Owner: Person 2.
- Smallest fix: save notes through a field-targeted mutation (`updateRecordingNotes(id:summary:)` mutating only `data.recordings[i].summary`); keep only the ID plus a `String` draft in the editor. Optionally disable "Edit visit notes" while `isProviderBusy`.
- Regression check: isolated macOS AppStore harness (pattern of `docs/task-specs/transcript-correction.md`): recording with no segments -> capture notes draft -> save the recording with two segments and a model -> apply the notes save with the stale draft -> assert two segments and the model remain and `summary` equals the draft.

### RVA-05-002 — P2 — confirmed — A failed `finish()` leaves the recorder in a dead-end paused state whose only guidance is contradictory
- Snapshot/file/line: `apps/ios/Reva/Device/AudioServices.swift:210` (context `:202-228`, `:176-182`, `:111`, `:26`).
- Trigger: `finish()` verification fails after the recorder was stopped — empty/< 0.1 s capture (Start then Finish almost immediately, or an input that produced no encoded frames), or `AVAudioPlayer(contentsOf:)` rejecting a file left unfinalised after a media-services reset/encode error (those handlers already set `reachedEnd = true` and tell the user to "Save what was captured").
- Expected: the capture stays resumable as the `emptyRecording` text ("Record a little longer and try again") advises, or the recorder enters an explicit terminal state with one accurate instruction.
- Actual: `finish()` stops the recorder and sets `isPaused = true`, `reachedEnd = true` and releases the session before verifying (lines 205-211); on failure it only sets `errorMessage` and rethrows (224-227), leaving `isRecording == true` and `recorder != nil`. The screen shows "Paused" with Resume/Finish. `resume()` hits `guard !reachedEnd` and says "The one-hour recording limit was reached…" (178-182); Finish repeats the failure; `start()` throws `.busy` (111). Only Close -> "Discard recording" exits.
- Impact: contradictory and incorrect guidance on the failure branch of the main recording flow; no data loss beyond the already-unusable draft.
- Refutation attempt: searched for any path clearing `reachedEnd`/`recorder` after a failed finish; only `cancel()`/`cleanUpDraft()` (232-253), which delete the draft.
- Confidence: high. Owner: Person 2.
- Smallest fix: in the `catch` of `finish()`, move to an explicit terminal state (e.g. `finishFailed`) whose Resume message says the recording could not be finalised and must be discarded; change the `emptyRecording` text accordingly. Alternative: verify before marking `reachedEnd`.
- Regression check: harness with an injected empty draft: after `finish()` throws, `resume()` must publish the finalisation message (not the one-hour text) and `cancel()` returns to ready; UI check that the session screen offers discard/restart.

### RVA-05-003 — P2 — candidate — Camera scan path allows 30 pages but assembles full-resolution pages into a PDF on the main actor and then applies the 16 MiB byte cap with a Files-oriented message
- Snapshot/file/line: `apps/ios/Reva/Device/DocumentScanner.swift:56` (context `:52-60`; `apps/ios/Reva/Features/Records/AddRecordView.swift:143-165`; `apps/ios/Reva/Device/DocumentImportService.swift:47-48,70,117-135`).
- Trigger: on hardware, scan several pages with "Scan a document" and tap Save.
- Expected: a scan within the advertised page limit imports, or is rejected with guidance that applies to this path (scan fewer pages); memory bounded by downsampling before PDF assembly.
- Actual: the scanner accepts up to 30 pages and materialises all page images at once; the caller draws each full-resolution `UIImage` into a `UIGraphicsPDFRenderer` inside a MainActor `Task`, writes the PDF to tmp and calls `ingest(url:)`, which rejects > 16 MiB with "This file exceeds the 16 MB import limit. Export a smaller copy and try again." Nothing downsamples scan pages before the byte check (the 2600 px OCR downsampling happens only after acceptance). Core Graphics embeds non-JPEG-backed bitmaps with Flate, so a handful of multi-megapixel pages can exceed the cap while the page limit still says 30.
- Impact: multi-page camera scans are likely rejected far below the advertised page limit with unactionable guidance, after a main-thread PDF assembly whose peak memory scales with N x W x H x 4 bytes plus the encoded PDF. The exact page count at which rejection occurs is unmeasured (hardware unavailable; VisionKit page pixel size/backing not determinable from source).
- Refutation attempt: searched for any resize/JPEG re-encode between the scanner callback and ingest; none.
- Confidence: medium. Owner: Person 1. Evidence request: EV-05-02.
- Smallest fix: resize each page to <= `maximumOCREdge` and JPEG-encode (~0.7) before drawing into the PDF (or ingest the JPEG pages directly), do the assembly off the main actor, and give the scan path its own error text; align the scanner page limit with what the byte cap can hold.
- Regression check: build a PDF from 10 synthetic 3024x4032 pages through the same code path and assert `Data.count < 16 MiB`; hardware check that a 10-page scan imports with 10 `pageTexts` slots.

### RVA-05-004 — P3 — candidate — A 20-character embedded-text threshold skips OCR for scanned pages that carry only a short text banner, with no page warning
- Snapshot/file/line: `apps/ios/Reva/Device/DocumentImportService.swift:257` (context `:250-278`).
- Trigger: import a scanned PDF whose pages are images plus a small embedded text line of >= 20 characters (fax header, scanner date stamp, "CONFIDENTIAL" footer).
- Expected: pages whose embedded text is negligible for the page are OCR'd within the existing 10-page budget, or flagged so the reviewer knows recognition was skipped.
- Actual: `if embedded.count >= 20 { return embedded }` — the page is never rasterised, its image content is absent from `text`/`pageTexts`, and no OCR warning is attached (the review warning is added only when OCR runs, line 265). The review screen shows only the banner text.
- Impact: extracted text for a common class of medical documents is the stamp only, silently. Originals are preserved and text is user-reviewable, so quality/robustness rather than data loss. `docs/task-specs/device-services.md:101` documents the heuristic as a known limitation; the app does not surface it.
- Refutation attempt: checked for a later density comparison or warning; none.
- Confidence: medium. Owner: Person 1.
- Smallest fix: require substantial embedded text (e.g. >= ~200 characters or a small chars-per-area density) before skipping OCR; otherwise OCR and keep the longer result (line 278 already does this); when OCR is skipped on a short-text page, add a per-page warning.
- Regression check: harness PDF with a full-size text image plus a 30-character embedded header; assert `pageTexts[0]` contains the image text and the OCR review warning is present.

### RVA-05-005 — P3 — candidate — Playback of a synced browser recording in an unsupported container (WebM/Ogg) reports "missing or damaged"
- Snapshot/file/line: `apps/ios/Reva/Device/AudioServices.swift:400` (context `:27,393-421`; `apps/ios/Reva/Core/ServerClient.swift:67-75`; `apps/ios/Reva/State/AppStore+Sync.swift:76-78`; `apps/web/src/core/store.ts:59-60`).
- Trigger: a browser-made recording (`.webm`/`.ogg`) is pulled to the iPhone by explicit sync; tap Play.
- Expected: a message that this format cannot be played on this device and that the original is preserved/shareable (the architecture doc already says playback "depends on the receiving device").
- Actual: every `AVAudioPlayer` init/duration failure becomes `DeviceAudioError.invalidAudio` — "This audio file could not be played. It may be missing or damaged." The file is intact; AVFoundation does not decode WebM/Ogg containers.
- Impact: misleading claim that a medical recording is damaged on the cross-client path. Codec behaviour itself is Unverified on hardware; the message path is source-proven for any init failure.
- Refutation attempt: looked for an extension/UTType check before player init; none.
- Confidence: medium. Owner: Person 2.
- Smallest fix: check the extension against the AVFoundation-playable set before init and throw a distinct `unsupportedFormat` error with honest text.
- Regression check: harness `play(url:)` on a synthetic `.webm` publishes the unsupported-format message; the existing `.caf` tone check still passes.

### RVA-05-006 — P3 — suggestion — Exported visit-brief PDF hard-codes the legacy teal (#0A5B6C) instead of the heart-red palette
- `apps/ios/Reva/Device/ReportPDFRenderer.swift:209` (call sites 126/133/141/181; `Features/Shared/Theme.swift:13-22` for current tokens; `docs/verification/README.md:1` states teal is not the current design).
- Impact: visual identity mismatch and a misleading token name; no functional effect. Owner: Person 1 (palette values from the Captain-owned theme).
- Smallest fix: derive the colour from the heart-red/deep-red hex values and rename the property. Regression: sample the header pixel colour in the harness (already done for the teal header per device-services.md:85).

### RVA-05-007 — P3 — suggestion — `loadSample(visitID:)` ignores its `visitID` parameter
- `apps/ios/Reva/State/AppStore+Recordings.swift:22` (`:22-39`; `VisitDetailView.swift:122-130`).
- Behaviour is safe and intended (the sample stays on its fixture visit, never gets audio), but the signature implies per-visit attachment and the user is navigated to a recording that is not listed under the visit they opened it from. Owner: Person 2.
- Smallest fix: drop/rename the parameter; optionally a notice when opened from another visit.

### RVA-05-008 — P3 — suggestion — After a successful `finish()`, a failed metadata save orphans the finalised audio with no retry path
- `apps/ios/Reva/Features/Visits/RecordingSessionView.swift:103` (`:97-106,47-63`; `AudioServices.swift:217-223`).
- If `store.save(recording)` throws after `finish()` succeeded (write failure, or snapshot validation such as the visit no longer existing), the screen falls back to "Start recording"; the finished `.m4a` stays in attachments unreferenced although `recorder.audioURL` still holds it. Owner: Person 2.
- Smallest fix: keep the finished URL in view state and offer "Retry saving recording". Regression: failing-repository double, then retry succeeds with the same `audioFilename`.

### RVA-05-009 — P3 — evidence-gap — PDF export runs Core Text pagination and PDF writing synchronously on the main actor up to 200,000 characters / 100 pages; cost unmeasured
- `apps/ios/Reva/Device/ReportPDFRenderer.swift:34` (`:34-35,63-81,96-112`; `ReportView.swift:99-126`).
- Each page is laid out twice (measure, then draw). Bounded and finite, but no measurement exists. Owner: Person 1. Evidence request EV-05-01. If the ceiling costs >= ~0.3 s, move `render` off the main actor with the existing progress pattern.

### RVA-05-010 — P3 — suggestion — Re-saving an unchanged memory discards a connected-AI summary of the memory record and bumps its version, staling briefs for no source change
- `apps/ios/Reva/State/AppStore+Recordings.swift:97` (`:94-97,116-119`; `ReportEngine.swift:41-42`; `RecordDetailView.swift:66-70` offers "Summarize with Gemini" for any record with text).
- "Update memory in Records" with nothing changed resets `summary` to the local excerpt and `summaryModel` to nil, so `previous.summary != record.summary` bumps `version` and every saved brief becomes stale. Labels remain honest. Owner: Person 2.
- Smallest fix: reset summary/model only when `record.text` actually changes. Regression: save memory, set `summaryModel`, save again unchanged, assert model and version unchanged.

### Observations not filed as findings (for the owning tracks)
- Retained audio after "Delete recording" is a disclosed trade-off (`apps/ios/Reva/Features/Shared/SettingsView.swift:81`, `docs/reviews/review-log.md` item 7); the delete dialog (`RecordingDetailView.swift:146-148`) could state it. Not filed.
- `RecordingSessionView.swift:53-55` surfaces `recorder.start` errors both inline (`recorder.errorMessage`) and in the global alert (`store.errorMessage`), and would print a raw `CancellationError` description if a cancel ever raced the permission await (not reachable through the UI because the system permission alert blocks input). Not filed.
- `AddRecordView.swift:135` names every Photos import `photo.jpg` regardless of sniffed MIME (D02 note above; Records track).
- `AddRecordView.swift:6` imports CryptoKit without using it (B04, other track).
- An `AudioRecorder` deallocated mid-capture by an external sheet dismissal (e.g. the visit vanishing from the snapshot) stops via `AVAudioRecorder` release and leaves an orphan draft; the session screen's own Close/discard path prevents this in normal use. Not filed.
- Booking views in `Features/Visits` (`BookingEditorView`, `BookingStatusView`, `LiveBookingEditorView`, `LiveBookingStatusView`) were read in full; nothing contradicting I01-I04 was seen (simulation labelled as no call, E.164 validation, explicit consent dialog, status vocabulary preserves unknown values, no auto-polling). Those IDs belong to the booking track; no finding is filed from here.

## 4. Evidence requests (for the shared runner; none executed by this track)

All requests are read-only or run entirely in the runner's scratch directory; none touches the worktree, a simulator, a port, a provider or a database. Scripts are macOS proxies for iPhone behaviour and must be labelled as such in any citation.

**EV-05-01** — Main-actor pagination cost proxy (supports RVA-05-009 / M01). Priority: low.
- cwd: runner scratch directory. Save as `ev-05-01-pagination.swift`, run `swift ev-05-01-pagination.swift` (timeout 120 s).
- Purpose: bound the Core Text layout cost at `ReportPDFRenderer`'s 200k-character ceiling with the same measure-then-draw double layout.
- Expected: prints `chars=… pages=… seconds=…`; `pages` about 100. A value >= ~0.3 s supports moving export off the main actor; a value far below it closes the gap.
```swift
import AppKit
import CoreText
let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 3
paragraph.paragraphSpacing = 10
paragraph.lineBreakMode = .byWordWrapping
let sentence = "Synthetic source sentence with several ordinary words for layout timing only. "
let body = String(repeating: sentence, count: 200_000 / sentence.count)
let content = NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: paragraph])
let framesetter = CTFramesetterCreateWithAttributedString(content)
let path = CGPath(rect: CGRect(x: 44, y: 76, width: 524, height: 651), transform: nil)
let start = Date()
var position = 0
var pages = 0
while position < content.length && pages < 100 {
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0), path, nil)
    let length = CTFrameGetVisibleStringRange(frame).length
    guard length > 0 else { break }
    _ = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: length), path, nil) // draw pass
    position += length
    pages += 1
}
print("chars=\(content.length) pages=\(pages) seconds=\(Date().timeIntervalSince(start))")
```

**EV-05-02** — CG PDF image-embedding size for camera-sized pages (supports RVA-05-003 / D01). Priority: medium.
- cwd: runner scratch directory. Save as `ev-05-02-scanpdf.swift`, run `swift ev-05-02-scanpdf.swift` (timeout 300 s; allocates ~50 MB bitmaps).
- Purpose: measure the PDF byte size produced by drawing a 3024x4032 page image N times (N = 1, 3, 5, 10) through Core Graphics' PDF context, for both a plain bitmap (Flate) and a JPEG-backed image, and compare with the 16 MiB (16,777,216) import cap. VisionKit's actual page size/backing remains unverified; this bounds only the encoder behaviour.
- Expected: the smallest N at which either variant exceeds the cap. If N <= 10 for the bitmap variant, RVA-05-003 is supported; if both variants stay under the cap at N = 10, downgrade it to P3.
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
let width = 3024, height = 4032
let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setFillColor(CGColor(gray: 0.96, alpha: 1))
bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
for _ in 0..<400_000 { // paper texture
    bitmap.setFillColor(CGColor(gray: CGFloat.random(in: 0.85...1.0), alpha: 1))
    bitmap.fill(CGRect(x: CGFloat.random(in: 0..<CGFloat(width)), y: CGFloat.random(in: 0..<CGFloat(height)), width: 3, height: 3))
}
for _ in 0..<6_000 { // text-like strokes
    bitmap.setFillColor(CGColor(gray: CGFloat.random(in: 0...0.2), alpha: 1))
    bitmap.fill(CGRect(x: CGFloat.random(in: 0..<CGFloat(width)), y: CGFloat.random(in: 0..<CGFloat(height)), width: CGFloat.random(in: 6...60), height: 3))
}
let raw = bitmap.makeImage()!
let jpegData = NSMutableData()
let dest = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, raw, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
CGImageDestinationFinalize(dest)
let jpegBacked = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(jpegData, nil)!, 0, nil)!
func pdfBytes(_ image: CGImage, pages: Int) -> Int {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let pdf = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &mediaBox, nil)!
    let scale = min(572 / CGFloat(image.width), 752 / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    for _ in 0..<pages {
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: CGRect(x: (612 - size.width) / 2, y: (792 - size.height) / 2, width: size.width, height: size.height))
        pdf.endPDFPage()
    }
    pdf.closePDF()
    return data.length
}
print("jpeg source bytes=\(jpegData.length)")
for pages in [1, 3, 5, 10] {
    print("pages=\(pages) flate(bitmap)=\(pdfBytes(raw, pages: pages)) jpegBacked=\(pdfBytes(jpegBacked, pages: pages)) limit=\(16 * 1024 * 1024)")
}
```

**EV-05-03** — Archived export artifact metadata (E05, historical evidence only). Priority: low.
- Command (read-only): `mdls -name kMDItemNumberOfPages -name kMDItemTitle -name kMDItemCreator /Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322/docs/verification/orthopedic-brief.pdf`; if `pypdf` is importable, additionally `python3 -c "import pypdf,sys;r=pypdf.PdfReader(sys.argv[1]);print(len(r.pages));print([('Source-based preparation' in (p.extract_text() or '')) for p in r.pages])" <same path>`.
- Purpose: confirm the archived app export (commit `d9ec87c`) has the documented 6 pages, the renderer's creator string and a provenance footer on every page. This is a historical artifact; it does not verify the current snapshot's runtime.
- Expected: 6 pages; creator "Reva · on-device report export"; all `True`.

**EV-05-04** — Root package tests (shared with other tracks; do not duplicate if already run): `swift test -j 6` at the worktree root with a sanitised environment. Relevant to this track only for `ProviderClientTests` transcript-segment validation (`Tests/RevaCoreTests/ProviderClientTests.swift:108,294,444`). Purpose: cite pass/fail in the disposition for J02/H03 overlap. Not a request to run `run-checks.py` (it requires an already-booted simulator and restores the shared app — prohibited).

## 5. What was NOT reviewed and why

- Physical-device behaviour (microphone input, headset/phone-call interruptions, one-hour cap, camera scan output size, HEIC camera captures, AAC/WebM playback): no simulator or device may be used by this track; documented as manual checks (`docs/architecture.md:189`, `docs/task-specs/device-services.md:99`). Marked Unverified.
- `run-checks.py` / `Harness.swift.in` were read only as evidence of past checks; they were not executed (they install onto an already-booted simulator and relaunch `health.revamed.Reva`, which would touch the other session's simulator). Their harness compiles the production adapters with strict concurrency, exercises synthetic inputs only, and writes to its own container; nothing in them contradicts the adapters' contracts. `generate_project.py:27-34` includes only `.swift`/resource extensions, so `Harness.swift.in` and `run-checks.py` are neither compiled nor bundled (no generated-file leakage from this directory).
- Browser recording/print/export, secure-context and IndexedDB claims (second half of E05 and K05): web track's scope.
- Booking behaviour (I01-I04) although the four booking views live in my directory: owned by the booking track; read for completeness only (§3 observations).
- Server-side transcription (`H03`), attachment hashing/dedup (`F05`), sync semantics (`F03/F04`), record intake UI state machine (`D04/D05`): other tracks; consulted only where the recording/memory paths depend on them.
- The concurrent account/Tiger contract (`docs/task-specs/accounts-and-tiger.md`) was not read: nothing in this track's scope depends on identity or accounts, and the brief assigns that review to tracks 12/13.

## 6. Completion statement

Actionable defects survived review: two confirmed P2 issues (RVA-05-001 stale notes save erasing a transcript; RVA-05-002 dead-end state after a failed finish), one candidate P2 (RVA-05-003 camera-scan page/byte cap mismatch, pending EV-05-02), two candidate P3 items, four suggestions and one efficiency evidence gap. The core contracts audited here otherwise hold at source level: bounded intake with preserved originals and page mapping, honest OCR warnings, owner-checked audio-session lifecycle with visible pause on every interruption class, sample/real-audio separation on every path found, words-only corrections keyed by segment ID, stable memory records with source links, and staleness propagation through `ReportEngine.signature`. No hardware, codec or timing claim in this report is presented as verified.
