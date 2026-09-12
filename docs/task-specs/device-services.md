# Device services task specification

Owner: device-services contributor. Written before implementation on September 12, 2026. Authority: `docs/implementation-contract.md`, `docs/completion-criteria.md`, `docs/task-list.md`, and the primary agent's bounded assignment. No applicable `AGENTS.md` was found in the workspace ancestry or initial repository file inventory.

## Scope and integration boundary

Own only `apps/ios/Reva/Device/` and this specification. Do not change app state, shared domain models, views outside Device, Info.plist, project generation, or Xcode project files. Do not commit or push. The primary agent integrates and verifies actual screens, persistence, source storage, share presentation, and consent UI. All adapters use native Apple frameworks, work without keys or servers, and never manufacture a transcript or medical interpretation.

## Import contract and behavior

`ImportedDocument` has `filename: String`, `mimeType: String`, `data: Data`, `text: String`, `warnings: [String]`, `pageCount: Int`, and `pageTexts: [String]` (default empty). `pageTexts` is ordered by original page and contains empty strings for unavailable pages, preserving evidence page identity. The data field retains the exact original imported bytes. Caller persists these bytes in app-owned storage and presents warnings and a text correction step.

`DocumentImportService.ingest(url:) async throws` and `ingest(imageData:filename:) async throws` return this value. Instance-based actor isolates synchronous extraction away from the UI actor and serializes memory-intensive work. Files ingestion opens security-scoped access for the complete bounded read and closes it with defer; file-provider reads use file coordination. Only local file URLs are accepted. A bounded stream rejects overlarge files even if their metadata is wrong. Filenames returned are safe leaf names, not directory paths.

Support PDF, UTF-8/UTF-16 plain text, and ImageIO-supported still images (including camera JPEG/HEIC/PNG). Detect actual image MIME types. Reject empty, unsupported, malformed, encrypted/unreadable, and oversized inputs with human-readable errors. Limits: 16 MiB source bytes, 30 PDF pages, 40 million source image pixels, 2,600 pixels on the long edge for OCR, at most 10 PDF pages requiring OCR, and 200,000 extracted text characters per import. Preserve the source when OCR/text is absent or incomplete; warnings explicitly describe review needs and any extraction limits. Reject a PDF above the total page cap rather than silently omitting original pages.

For each PDF page, use embedded text where readable; otherwise render a bounded raster and run Vision OCR. OCR uses accurate recognition without language correction to reduce automatic changes to clinical spelling or values, but cannot guarantee accuracy. Every OCR result carries a manual-review warning; low-confidence, failed, or unreadable pages add specific warnings. Cancellation is checked between pages and read chunks. No extraction-success claim when no text is found.

## Native camera scanner

`DocumentScanner: UIViewControllerRepresentable` exposes exact callbacks `onFinish: ([UIImage]) -> Void`, `onCancel: () -> Void`, `onError: (Error) -> Void`. Add a convenience supported Boolean that reads `VNDocumentCameraViewController.isSupported`; caller gates presentation and offers real sample import on the simulator. The native scanner owns its capture/review interface. Delegate emits one terminal callback and bounds accepted pages to the import page limit. Caller dismisses its sheet, persists scan images or a generated PDF, then invokes ingestion. No synthetic scanner output.

## Recording and playback

`@MainActor AudioRecorder: ObservableObject` publishes `isRecording`, `isPaused`, `elapsed`, `audioURL`, `errorMessage`. Start uses `AVAudioApplication.requestRecordPermission`, activates a record-capable audio session, validates a local caller-provided persistent directory, generates a UUID filename, and records real AAC audio. Reject concurrent starts and unavailable input. `pause` retains the file and elapsed time; `resume` reactivates the session. `finish` verifies that captured audio exists and returns its URL; it never returns invented media or transcript. `cancel` removes only the recorder's own unfinished file. Calling cancel after successful finish does not delete delivered audio.

Observe audio interruptions, route loss, media service reset, and app background entry. Pause capture visibly without automatic resumption; errors tell the user to resume or finish. No audio background mode is assumed. Primary agent also pauses on scene phase changes and owns leaving-screen confirmation. Finishing a paused recording is valid. Timer shows actual recorder time rather than wall time. Recording duration is capped at one hour to bound unintended capture. Caller owns deletion of finished recordings.

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

Pending implementation. Installed Xcode reports 26.4; iPhone simulator SDK path is `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.4.sdk`. Initial xcrun probe emitted sandbox temp-cache warnings, but resolved the SDK. Use compiler paths directly and an owned temporary module cache for isolated typechecking.
