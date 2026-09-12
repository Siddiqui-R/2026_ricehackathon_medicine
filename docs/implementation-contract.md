# Reva prototype implementation contract v1

> Historical baseline wire/device contract. See [the current project specification](reva-stack-spec.md) for later scope and [accounts-and-tiger.md](task-specs/accounts-and-tiger.md) for the active account extension: public signup/login, hashed sessions, optional static-token identities with accounts enabled, browser account mode and migration 002. Older requirements below for a nonempty static-token map in every PostgreSQL deployment do not override that newer contract. Existing snapshot/provider compatibility requirements remain in force.

This contract makes the user goal concrete for concurrent work. Primary agent owns domain types, app state, UI, report relevance/generation, app/server integration, and final audit. Contributors own only their assigned paths. All dates in JSON are ISO 8601 strings; use UUID-shaped strings or stable fixture IDs consistently. All sample material is explicitly fictional. Data persists locally with no credentials; live service work is deferred.

## App state and fixture JSON

Top-level `seed.json` / persisted state shape:

```
{
  schemaVersion: 1,
  profile: { id, name, dateOfBirth, initials, allergies: [String], medications: [String], conditions: [String], isDemo: true },
  records: [MedicalRecord], visits: [Visit], bookings: [], recordings: []
}
```

`MedicalRecord`: `id`, `title`, `kind` (one of Notes, Labs, Imaging, Procedure, Scan, Recording), `provider`, `date` (YYYY-MM-DD), `uploadedAt` (ISO timestamp), `tags` ([String]), `text` (full source text), `summary` (plain text), `sourceFilename` (optional filename; bundled sources have flat unique names), `mimeType` (optional), `pageCount` (Int), `status` (ready/needsReview/processing), `notes` (String), `isDemo` (Bool), `version` (Int starting 1).

`Visit`: `id`, `title`, `type` (Primary care/Orthopedics/Cardiology/Other), `provider`, `clinic`, `date` (ISO timestamp), `timeZone` (IANA timezone), `concern`, `goal`, `questions` ([String]), `pinnedRecordIDs` ([String]), `notes` (String), `status` (upcoming/completed), `report` (nullable; seed omit or null).

`VisitReport`: `id`, `visitID`, `createdAt`, `sourceSignature`, `sections` ([{id,title,body,sources:[{recordID,page,excerpt}]}]), `questions` ([String]), `notes`, `selectedRecordIDs`, `isDemo`.

`BookingRequest` and the `bookings` array are retained only for backward-compatible decoding/sync of historical snapshots. No booking simulation, calling UI or call execution remains.

`VisitRecording`: id/visitID/title/createdAt/duration/audioFilename(optional)/segments([{id,speaker,start,end,text}])/summary/isSample/status. New microphone audio has no transcript until entered/real service configured. The bundled sample is a separate explicit action and never assigned to new audio.

## App / server wire contract

The prototype uses an atomic state-sync boundary for coherent domain relationships, plus attachment endpoints. The server owns identity; a client cannot choose another owner using payload fields. Top-level state remains the shape above inside `snapshot`.

- `GET /health`: public, storage mode and status, no sensitive content.
- `GET /v1/state`: Bearer token required → `{revision: Int, snapshot: JSON object}` or 404 for empty owner state.
- `PUT /v1/state`: `{baseRevision: Int, snapshot: JSON object}` → new revision. First write uses 0. Stale writes return 409. Validate required top-level arrays/profile and payload size. Owner identity comes from auth.
- `PUT /v1/attachments/{id}`: authenticated raw file bytes, content-type, safe filename metadata. Owner-scoped unique ID, bounded payload.
- `GET /v1/attachments/{id}`: authenticated exact original bytes + type/name; no path traversal.
- `DELETE /v1/attachments/{id}` and `DELETE /v1/state`: owner-scoped deletion, with clear local-development semantics.

Local server: bind localhost by default, demo-only token identity, atomic file persistence. PostgreSQL mode: explicit DATABASE_URL and nonempty token configuration; no silent fallback. Tiger tables may use a versioned JSONB snapshot to persist all prototype domains together, plus BYTEA attachment records, owner keys, revisions, timestamps, constraints, and audit/idempotency metadata. This is a deliberate hackathon schema; production normalized views/tables are a documented future change, not falsely claimed implemented. All data including sample attachments is supported by the Tiger store. Do not build cloud Storage integration now.

## Device adapters

Adapters live in `apps/ios/Reva/Device/`; no app state dependencies.

- `ImportedDocument` contains filename:String, mimeType:String, data:Data, text:String, warnings:[String], pageCount:Int.
- `DocumentImportService.ingest(url: URL) async throws -> ImportedDocument` and `ingest(imageData: Data, filename: String) async throws -> ImportedDocument`; security-scoped access, embedded PDF text / OCR via Vision, bounded PDF/image sizes/pages, clear failures.
- `DocumentScanner` is a UIViewControllerRepresentable with `onFinish: ([UIImage])->Void`, `onCancel: ()->Void`, `onError: (Error)->Void`; caller checks VNDocumentCameraViewController.isSupported.
- `AudioRecorder: ObservableObject`, @MainActor. Published `isRecording`, `isPaused`, `elapsed`, `audioURL`, `errorMessage` as appropriate. `start(directory:URL) async throws`, `pause()`, `resume()`, `finish() throws -> URL`, `cancel()`. Validate permissions; retain actual captured audio; never create a sample transcript automatically.
- `AudioPlayback: ObservableObject`, @MainActor: `play(url:) throws`, `pause()`, `stop()`, `seek(to:)`; expose currentTime/duration/isPlaying if useful.
- `PDFSection {title:String, body:String}` and `ReportPDFRenderer.render(title:String, subtitle:String, sections:[PDFSection], sources:[String]) throws -> URL`: native UIGraphicsPDFRenderer with pagination; export path in temporary app storage.

## Build and review boundaries

No external API keys, no live calls, no real patient files, no automatic model downloads. The app includes source files/resources through `scripts/generate_project.py`; tell the parent about new resources so it can regenerate. Backend/dataset/device contributors may write their own detailed task packet in `docs/task-specs/`, and must list verification evidence/failures. Do not commit or push concurrently; primary agent checkpoints reviewed scopes. Claude writes only explicitly assigned review files until given a later bounded revision task in a worktree.

## Implemented seam decisions after architecture review

- The native app remains local-authoritative. Developer Settings exposes explicit probe/push/pull operations; no failed request switches modes or substitutes fixture data. A pull downloads originals before replacing the snapshot. A stale push reports409 and preserves local data. This is a manual demonstration transport, not production background synchronization.
- `MedicalRecord.pageTexts` optionally retains per-page extraction. `SourceReference.sourceVersion` records evidence version. Report signatures hash the full candidate source/version pool, goal/type/date and pinned set. Manual whole-document corrections discard prior page segmentation.
- Server attachment IDs are lowercase SHA256 hashes of the UTF8 local filename; wire `X-Filename` is sanitized ASCII metadata only. State retains its local filename and derives the same ID on retrieval. Limits:16MiB per attachment,64MiB and128 attachments per owner,4MiB state request. Missing state carries `X-State-Revision`; deletion leaves a monotonic tombstone.
- Unfinished queued/calling simulations become needsUser on restart, with explicit retry. A confirmed attempt can update only its existing visit once. Sample transcript remains attached to its original completed fixture visit, even when opened from another visit. Real microphone audio never receives sample transcript text.
- Recording pauses when Reva leaves the foreground. No background audio entitlement. Local excerpts quote source text, demo summaries are explicitly bundled fictional material; no Gemini-run claim is made.


## Appointment summary additions

`VisitRecording.summary` remains personal notes. Optional `aiSummary`, `aiSummaryModel`, and `aiSummaryGeneratedAt` store a derived summary separately. Missing fields decode normally in old snapshots. AI receives the full timestamped transcript; transcript edits invalidate the derived summary, while notes edits do not. A saved memory keeps full source text and can use the generated summary/model without replacing the transcript. Capture requires the doctor’s and everyone present’s consent.
