# Browser core compatibility

Purpose: Record the native/browser boundary and the limits of this implementation.
Inputs: Current Swift Codable models, ReportEngine behavior, HTTP contracts and fictional fixtures.
Outputs: Reviewable compatibility evidence and operational tradeoffs.
Side effects: None.

## Native evidence and state

The browser retains native IDs, schema version, source versions, page text, citation excerpts, optional provider labels, recording IDs and transcript timestamps. Its report signature uses the exact native separators, full candidate pool, sorted IDs and epoch-second `.0` formatting. Tests compare all three demo visit hashes with values emitted by the actual Swift ReportEngine compiled against the same checked-in seed. Source selection and page assertions use the existing fixture acceptance file.

User questions and separate notes remain authoritative when a report is refreshed. Correcting a transcript changes words by segment ID, keeps timing/speakers/original audio, updates an existing linked memory and preserves its separate notes. A correction alone does not create a new memory.

JavaScript dates have millisecond precision. Imported timestamps with finer precision, unusual Unicode IDs whose lexical ordering differs from Swift, and differences between browser/Swift Unicode segmentation tables may produce a different signature or source ranking. Normal UUID/demo IDs and whole-second timestamps emitted by both clients match. A changed signature makes a brief stale and requires regeneration; it never changes a saved original quotation. Browser input bounds for filename and symptom/transcript text may be stricter for multi-code-point characters than Swift's grapheme counts. Date display follows browser locale; date-only record days are rendered in UTC to avoid day shifts.

## Durable local state and explicit sync

IndexedDB uses one read/write transaction for revision comparison, snapshot publication and any downloaded originals. Competing tabs cannot silently overwrite an unseen local revision. Corrupt snapshots and corrupt stored originals fail visibly; only an explicit demo reset may replace corrupt snapshot data. Missing originals can fall back only to manifest-listed bundled sources with verified byte length and SHA256. Original files are retained when records are removed or the demo is reset.

The owner token, provider availability and AI toggle stay in memory. Changing identity clears server revision and capabilities. The token cannot change during a connected operation. No timer calls a provider or syncs data. A 409 preserves the browser snapshot and blocks another push until a successful explicit pull; checking connection does not adopt the conflicting write revision.

Server originals and state use separate existing HTTP endpoints. A push uploads originals before the compare-and-swap snapshot write, so failed/conflicting pushes can leave uploaded or overwritten attachment bytes on the server; the snapshot itself remains revision-protected. Imported original filenames use UUID prefixes, and IDs hash the exact filename using native SHA256. A pull downloads all originals first, checks for local edits during the request and then commits the aggregate atomically. It does not infer a merge.

## Provider and browser limits

All requests use same-origin fixed API paths with bearer authentication, redirects rejected, no cookies, response size bounds and timeouts. WebM/Ogg browser originals retain their actual content type; they are not relabeled MP4. Uploads are limited to 16 MiB and snapshot JSON to 4 MiB. Browser storage quota remains browser-controlled and errors retain the previously committed snapshot.

Calling requires the UI's final reviewed authorization and configured capabilities. A unique durable request is saved before submission. Failed or interrupted requests become unknown, never automatically replay, and never confirm an appointment. API/store tests use synthetic data and injected responses; no paid provider call is exercised by the test suite. The browser context has no provider keys or arbitrary remote server destination.
