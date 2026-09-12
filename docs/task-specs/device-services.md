# Device services task specification

Owner: device-services contributor. Written before implementation on September 12, 2026. Authority: `docs/implementation-contract.md`, `docs/completion-criteria.md`, `docs/task-list.md`, and the primary agent's bounded assignment. No applicable `AGENTS.md` was found in the workspace ancestry or initial repository file inventory.

## Scope and integration boundary

Own only `apps/ios/Reva/Device/` and this specification. Do not change app state, shared domain models, views outside Device, Info.plist, project generation, or Xcode project files. Do not commit or push. The primary agent integrates and verifies actual screens, persistence, source storage, share presentation, and consent UI. All adapters use native Apple frameworks, work without keys or servers, and never manufacture a transcript or medical interpretation.

## Import contract and behavior

`ImportedDocument` has `filename: String`, `mimeType: String`, `data: Data`, `text: String`, `warnings: [String]`, `pageCount: Int`, and `pageTexts: [String]` (default empty). `pageTexts` is ordered by original page and contains empty strings for unavailable pages, preserving evidence page identity. The data field retains the exact original imported bytes. Caller persists these bytes in app-owned storage and presents warnings and a text correction step.

`DocumentImportService.ingest(url:) async throws` and `ingest(imageData:filename:) async throws` return this value. Instance-based actor isolates synchronous extraction away from the UI actor and serializes memory-intensive work. Files ingestion opens security-scoped access for the complete bounded read and closes it with defer; file-provider reads use file coordination. Only local file URLs are accepted. A bounded stream rejects overlarge files even if their metadata is wrong. Filenames returned are safe leaf names, not directory paths.

Support PDF, UTF-8/UTF-16 plain text, and ImageIO-supported still images (including camera JPEG/HEIC/PNG). Detect actual image MIME types. Reject empty, unsupported, malformed, encrypted/unreadable, and oversized inputs with human-readable errors. Limits: 16 MiB source bytes, 30 PDF pages, 40 million source image pixels, 2,600 pixels on the long edge for OCR, at most 10 PDF pages requiring OCR, and 200,000 extracted text characters per import. Preserve the source when OCR/text is absent or incomplete; warnings explicitly describe review needs and any extraction limits. Reject a PDF above the total page cap rather than silently omitting original pages.

For each PDF page, preserve embedded text and check possible scanned content with bounded Vision OCR. Reserve the ten-page OCR allowance for pages with fewer than twenty embedded characters first, then check other pages with the remaining allowance. Emit results in original page order and explicitly warn when image text could not be checked. Deduplicate only matching complete lines; keep distinct wording and numeric disagreements for review. OCR uses accurate recognition without language correction to reduce automatic changes to clinical spelling or values, but cannot guarantee accuracy. Every OCR result carries a manual-review warning; low-confidence, failed, or unreadable pages add specific warnings. Cancellation is checked between pages and read chunks. No extraction-success claim when no text is found.

## Native camera scanner

`DocumentScanner: UIViewControllerRepresentable` exposes exact callbacks `onFinish: ([UIImage]) -> Void`, `onCancel: () -> Void`, `onError: (Error) -> Void`. `DocumentScanner.isSupported` is explicitly false in simulator builds and otherwise reads `VNDocumentCameraViewController.isSupported`; caller gates presentation and offers real sample import on the simulator. The native scanner owns its capture/review interface. Delegate emits one terminal callback and bounds accepted pages to the import page limit. Caller dismisses its sheet, persists scan images or a generated PDF, then invokes ingestion. No synthetic scanner output.

## Recording and playback

`@MainActor AudioRecorder: ObservableObject` publishes `isRecording`, `isPaused`, `elapsed`, `audioURL`, `errorMessage`. Start uses `AVAudioApplication.requestRecordPermission`, activates a record-capable audio session, validates a local caller-provided persistent directory, generates a UUID filename, and records real AAC audio. Reject concurrent starts and unavailable input. `pause` retains the file and elapsed time; `resume` reactivates the session. `finish` verifies that captured audio exists and returns its URL; it never returns invented media or transcript. `cancel` removes only the recorder's own unfinished file. Calling cancel after successful finish does not delete delivered audio.

Observe audio interruptions, route loss, media service reset, and app background entry. Pause capture visibly without automatic resumption; recoverable interruption errors tell the user to resume or finish. Failed finalization enters a terminal state with explicit discard/restart guidance; finalized audio and stable metadata stay available for persistence retry or sharing after a save failure. No audio background mode is assumed. Primary agent also pauses on scene phase changes and owns leaving-screen confirmation. Finishing a paused recording is valid. Timer shows actual recorder time rather than wall time. Recording duration is capped at one hour to bound unintended capture. Caller owns deletion of finished recordings.

`@MainActor AudioPlayback: ObservableObject` supports `play(url:) throws`, `pause()`, `stop()`, `seek(to:)`, publishes `currentTime`, `duration`, `isPlaying`, and a readable error. Play on an already loaded URL resumes; play a new URL resets position. Seek clamps finite offsets. Pause on interruptions, output route removal, and background entry. No auto-resume after interruption. Audio session ownership is coordinated between recorder/playback adapters so simultaneously created controllers cannot accidentally deactivate each other's session.

## PDF export

`PDFSection { title: String, body: String }` and `@MainActor ReportPDFRenderer.render(title:subtitle:sections:sources:) throws -> URL` produce native US Letter PDFs in a unique temporary export directory. Use text layout with proper pagination, visible heading hierarchy, margins, page numbers, and a provenance/source footer on every page; append all provided source citations as a paginated section. Bound input and page count, preserve long paragraphs across page breaks, and reject impossible layout rather than spinning or clipping. No network or automatic sharing. Caller presents the returned URL through native sharing.

## Verification plan and acceptance

1. Typecheck all owned Swift files against the installed iOS simulator SDK with Swift 6 strict concurrency, using an isolated module cache. Do not change the shared project.
2. If practical, create a temporary standalone simulator harness to exercise import of text, embedded/scanned PDF, images, malformed and oversized files, page limits, exact original data, and pageTexts provenance. Test renderer with long sections and inspect exported pages; never use real records.
3. Communicate exact APIs, limits, completed checks, failures, and device-only checks to primary. Primary regenerates the project and verifies native scan/camera gating, permission routes, persistent captured audio, playback, and share presentation in the integrated app. Simulator checks cannot establish physical camera/microphone correctness.
4. Append actual evidence below as it is obtained. Do not mark physical-device or live transcription checks complete.

## Apple API references

- [Document camera support](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller/issupported)
- [Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- [Microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [Audio sessions](https://developer.apple.com/documentation/avfaudio/avaudiosession)

## Implementation and verification evidence

Implemented native sources: `DocumentImportService.swift`, `DocumentScanner.swift`, `AudioServices.swift`, and `ReportPDFRenderer.swift`. No app-state, project, plist, or shared UI changes were made. The repeatable isolated verification harness lives at `apps/ios/Reva/Device/Verification/Harness.swift.in` with `run-checks.py`; the `.in` suffix prevents the app generator from compiling a second app entrypoint. It uses a separate temporary `.app`, app identifier `health.revamed.DeviceHarness`, synthetic data only, and no microphone or camera permission request. The runner's Python syntax was checked; the equivalent compiler/install/launch commands and this exact harness were executed during implementation.

### Compiler evidence

Installed Xcode 26.4, Swift 6.3. Both native targets passed full compiler checks with Swift 6 and `-strict-concurrency=complete`:

- iOS simulator: compiled and linked the owned sources plus the standalone harness as an arm64 iOS 18 minimum executable, then installed and ran it on iPhone 17 / iOS 26.4, UUID `4F76BEA7-8C37-499C-90B6-AA551D862B0A`.
- Physical-device SDK: `swiftc -emit-module -module-name RevaDevice -swift-version 6 -strict-concurrency=complete -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.4.sdk -target arm64-apple-ios18.0 -module-cache-path /private/tmp/reva-device-module-cache -emit-module-path /private/tmp/reva-device-qa/RevaDevice.swiftmodule apps/ios/Reva/Device/*.swift` exited 0. This proves compilation only, not hardware execution.
- Initial `-typecheck` passed after annotating the main-thread VisionKit delegate conformance `@preconcurrency`; full executable compilation subsequently detected an actor-region issue involving `autoreleasepool`. Stateless extraction helpers were made explicitly nonisolated, preserving serialized actor entry and passing the stronger executable/module checks.

Repeat the runtime checks on an already booted Apple Silicon iPhone simulator with:

```sh
python3 apps/ios/Reva/Device/Verification/run-checks.py --device booted --output /private/tmp/reva-device-qa
```

The script restores `health.revamed.Reva` after the checks when installed. It does not change the shared Xcode project. It requires normal local Xcode/CoreSimulator access; the restricted agent sandbox required approved simulator operations because its default process could not reach CoreSimulator services. Compiler caches and all artifacts remained in owned temporary directories.

### Runtime evidence: 26 checks passed

The final harness log ends with `ALL CHECKS PASSED`. Verified cases:

- UTF-8 and UTF-16 decoding, exact original bytes, page text, empty/binary/remote rejection, the 16 MiB bound, corrupt image rejection.
- Real Vision OCR on a synthetic PNG; MIME sniffing independent of filename extension; leaf filename sanitization; mandatory OCR review warning; blank image yields empty text plus review warning.
- Embedded two-page PDF text maps to each original page and retains original bytes; real image-only PDF OCR; 31-page rejection; a 12-page blank PDF retains twelve page indexes and names pages skipped beyond the ten-page OCR limit.
- 200,000-character truncation carries a clear warning; cancellation propagates.
- A 16-page PDF includes all 75 distinct paragraph markers and all supplied citations. Every page contains the source/provenance footer. An empty export title is rejected.
- Finishing without captured audio is rejected. A real generated tone plays with advancing timer; pause, seek, nonfinite seek rejection, natural completion, stop/reset, and missing audio rejection work.
- The simulator scanner wrapper returns unsupported.

Runtime testing found and fixed two consequential platform behaviors: ImageIO may create an image-source object for text while returning no actual image type, so detection now checks the type; and this simulator's VisionKit support flag returned true despite unavailable document-camera hardware, so the wrapper now explicitly disables simulator scanning. Tests also exposed two harness assumptions that were corrected without altering adapter behavior: PDFKit changes underscore reading order in its text extraction, so distinct plain alphabetic markers replaced underscored assertions; each synthetic PDF now uses a fresh UIGraphicsPDFRenderer instance.

### PDF visual review

Used the PDF skill's read-only visual review workflow. Poppler rendered the native exported PDF, and pages 1, 8, and 16 were inspected. The initial rendering revealed vertically flipped Core Text glyphs despite successful text extraction. Resetting the text matrix to identity before Core Text drawing fixed the defect. The latest images show readable upright text, consistent margins, sensible section spacing, complete source citations, and unclipped footers/page numbers. Text presence checks cover all 16 pages; color-pixel and text-transform inspection confirmed the repeated header is present on the sampled pages.

Temporary evidence paths for primary review (no unrelated repository output changes):

- `/private/tmp/reva-device-qa/results.txt`
- `/private/tmp/reva-device-qa/adapter-report.pdf`
- `/private/tmp/reva-device-qa/report-first.png`
- `/private/tmp/reva-device-qa/report-middle.png`
- `/private/tmp/reva-device-qa/report-last.png`

The harness was terminated and the installed Reva app restored successfully (`simctl launch health.revamed.Reva` returned PID 98009). Primary may now use the simulator for integrated UI checks.

### Remaining manual/integration checks and limits

Physical camera capture, microphone permission/actual microphone input, headset/phone-call interruptions, protected-file behavior while locked, and one-hour recording behavior require real-device verification. The recorder's finish-without-capture error was exercised; successful recording was not claimed tested by this harness. Playback used a generated low-volume tone, not a patient recording. No transcript generation exists in these adapters.

The primary app must use `DocumentScanner.isSupported` (the wrapper), retain an `AudioRecorder` for the capture session, transfer/persist the URL returned by successful `finish()`, pause on scene-phase changes as additional UI protection, display import warnings and editable preview text, persist source bytes/pageTexts, and present the share sheet. `isRecording` stays true while a session is paused; `audioURL` can refer to an unfinished draft, so saving domain state should follow `finish()` success. `cancel()` never deletes an already delivered recording. PDF text and OCR reading order can differ from visual order, especially tables/underscores/handwriting; originals remain authoritative and OCR is always marked for review. The initial implementation preferred embedded text at twenty characters. The September 12 audit repair now also checks mixed pages within the OCR budget, prioritizes short/empty pages, and warns about unchecked text and differing representations. Its focused Windows tests use PDF/OCR doubles; the preceding Apple runtime evidence predates this repair and must be repeated for current behavior. Languages follow the device's supported Vision recognizer; no model downloads or accuracy guarantees are made.
