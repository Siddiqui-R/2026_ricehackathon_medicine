# Reva full-codebase audit checklist

Status values: **Pass / Defect / Unverified / WIP / Deferred / Not applicable**. Start every row Unverified; the checkbox means review coverage completed, not that behavior passed. Record snapshot identity, files, evidence and finding IDs in `reports/coverage.csv`.

## A Scope and traceability

- [x] **A01** — Record frozen SHA, dirty-file inventory, hashes, worktrees and active implementation changes. Review one identified snapshot at a time.
- [x] **A02** — Map every active feature to native/browser/server implementation and evidence; distinguish working, partial, WIP, deferred and unverified.
- [x] **A03** — Resolve historical-spec contradictions: heart palette and browser support supersede older teal/dark/web-deferred plans; review account/Tiger work as emerging scope.
- [x] **A04** — Reproduce actual builds/checks; historical pass counts are not new evidence. Record skipped gates and unavailable tools.

## B Code quality, cleanliness and ownership

- [x] **B01** — Purpose/Inputs/Outputs/Side effects headers and named responsibility sections describe real behavior; run structure check and inspect cohesion manually.
- [x] **B02** — Dependency direction separates UI, domain state, persistence, device IO and provider transport. Identify duplicated contracts/rules and hidden alternate state owners.
- [x] **B03** — Three-person feature ownership is practical; shared contracts, stores, theme and generators have explicit integration ownership.
- [x] **B04** — Find demonstrably dead code, unused imports/assets/dependencies, misleading comments, debug logging and generated-file leakage. File length alone is not a defect.
- [x] **B05** — Check error types, cancellation propagation, input validation, naming, API consistency and maintainable complexity. Do not prescribe arbitrary fragmentation or claim NASA certification.

## C Navigation, profile and symptoms

- [x] **C01** — Native Summary, Records, Visits, Medical profile and Settings plus all details/editors have working back, cancel, empty and failure paths.
- [x] **C02** — Browser sidebar/header/bottom navigation, hash/query routes, reload/deep links and modal reopening work. Audit new /, /demo, /login and /signup routes separately.
- [x] **C03** — Recent-records View all reaches the full Records list, Log symptoms is intuitive, Medical profile is reachable, Appearance and history-retention marketing tile stay removed.
- [x] **C04** — Profile identity/DOB/allergies/medications/conditions/surgeries/implants/care notes persist; absent facts are not invented; legacy snapshots decode.
- [x] **C05** — Persistent profile facts remain distinct from historical evidence; report whether preparation consumes profile or only Records without silently rewriting sources.
- [x] **C06** — Symptom entry validates observation/time and preserves optional severity, duration, details, triggers/relief, timezone, self-reported provenance, IDs, creation time, versions and search/filter/edit/delete.

## D Intake, original evidence and memory

- [x] **D01** — PDF/text/image/camera intake handles empty, unsupported, malformed, corrupt and oversized inputs with finite time/page/text/byte limits.
- [x] **D02** — Original bytes, filename, MIME, SHA256 identity and pages survive save/edit/reload/sync/failure; same-name conflicts and fixture fallback cannot replace evidence silently.
- [x] **D03** — PDFKit/Vision and PDF.js/Tesseract preserve page mapping; mixed/scanned/obscured documents stay reviewable. Do not assume perfect OCR.
- [x] **D04** — Extraction preview, user review/correction, cancellation, failed save/quota, retry and processing state avoid ghost records, duplicate saves and lost originals.
- [x] **D05** — Usable uploads receive the promised local excerpt or configured AI summary. Origin/model/status are honest; units, doses, dates, negations and uncertainty stay intact.
- [x] **D06** — Search covers advertised fields; filters, date ordering, empty results and source navigation remain coherent after mutation and reload; stale evidence is visible.

## E Visits, retrieval and export

- [x] **E01** — Visit fields and CRUD preserve timezone/date/DST semantics, upcoming/past sorting, notes/questions and cancellation; concurrent edits do not overwrite each other.
- [x] **E02** — Distinct visit goals select appropriate histories; old implant page two is found for orthopedics, unrelated ear note excluded, pins retained and no brittle absolute body-part rule.
- [x] **E03** — Every quotation is exact saved source text and every record/page/version link resolves; AI candidate IDs are supplied IDs; no invented page or clinical assertion.
- [x] **E04** — Source/goal/pin changes stale prior reports; delayed AI cannot overwrite newer edits; personal questions/notes survive regeneration; actual Swift signature goldens match browser.
- [x] **E05** — Native PDF and browser print show only the intended fresh report with citations/questions/notes, usable pagination and no clipping. System print also respects staleness; capture actual print artifact if tool permits.

## F State, sync and race safety

- [x] **F01** — Native atomic JSON/backup/recovery, first-run seed, migration, save failure and explicit reset/relaunch preserve valid active state and documented retained originals.
- [x] **F02** — IndexedDB snapshot/original transaction, quota/corruption handling and cross-tab CAS are correct; no silent reset or stale async publication.
- [x] **F03** — Native/server/browser round trips retain IDs, optional profile/symptom/provider fields, timestamps/date-only values, source versions/signatures and transcript/audio metadata.
- [x] **F04** — Sync captures identity/snapshot/revision; 409 preserves local state and prevents accidental overwrite; connection switches and local edits cannot accept stale pulls or provider responses.
- [x] **F05** — Attachment hashing, owner scoping, deduplication, MIME/bytes, collision handling and staged rollback work. Assess attachment-before-snapshot writes that survive failed CAS as a documented tradeoff or concrete defect.

## G HTTP, storage, accounts and Tiger

- [x] **G01** — Every authenticated route obtains trusted identity; payload cannot choose another owner; state, files and receipts isolate owners; invalid/expired tokens fail safely.
- [x] **G02** — Request/response limits, streaming/buffering, deadlines/cancellation, path confinement, malformed JSON and safe errors are finite and do not leak patient content or credentials.
- [x] **G03** — Local store locking, monotonic revisions/tombstones, restart/corrupt/missing data and disk failure retain consistency without silent fallback.
- [x] **G04** — PostgreSQL/Tiger schema and migrations, parameter binding, verified TLS, owner keys, transactions and persistence match actual code. Run only local ephemeral DB if available; live Tiger remains unverified.
- [x] **G05** — When account implementation lands: registration/login validation, salted adaptive server-side password hashing/verification, no plaintext retention/logging, session expiry/revocation, duplicate users and error/rate controls are correct.
- [x] **G06** — Demo/login/logout/account switches isolate local data and in-flight requests; never silently upload another account or demo workspace into a real account.
- [x] **G07** — Account onboarding works across browser/server/native contracts as implemented; authentication cannot be a cosmetic page, client-only hash comparison, hardcoded credential or insecure SQL shortcut.
- [x] **G08** — New account storage joins owner-scoped medical data and migrations correctly; setup failures are explicit, and existing bearer-token workflows are either preserved or deliberately migrated.

## H AI and provider boundaries

- [x] **H01** — Current effective models, service discovery, paid-access/configuration flags and examples agree. Verify current model/API assumptions with official sources; do not use obsolete planned names.
- [x] **H02** — Gemini summary/preparation requests, limits and structured responses handle malformed/blocked/truncated/oversized/invalid-ID/timeout/error cases without losing local data.
- [x] **H03** — Whisper transport uses actual original audio/MIME/filename including WebM/Ogg; segments have finite valid relative offsets and honest generic speaker labels.
- [x] **H04** — Provider keys remain server-only; tokens/sessions follow the implemented contract; fixed destinations, redirect refusal, no secret bundling and no unexpected background transmissions.
- [x] **H05** — Uploaded document instructions cannot override the app task, invoke tools or fabricate source authority; prompt/data separation and output validation resist malicious synthetic source text.

## I Booking and calls

- [x] **I01** — Simulation reviews clinic/window/preferences, labels no real call, supports available/needs-input/failure and restores state across reload; confirmation updates one existing visit.
- [x] **I02** — Real calls require configured provider/agent/number/enable gates and explicit final reviewed consent with frozen patient/context/window.
- [x] **I03** — Durable owner/request intent precedes outbound action; concurrent/restarted/unknown requests never auto-redial; polling and retained receipts are owner scoped.
- [x] **I04** — A completed conversation never implies confirmed appointment; reviewed outcome/time is separate; stale polling and errors do not fabricate successful status.

## J Recording, transcripts and memories

- [x] **J01** — Native/browser denial/start/pause/resume/finish/cancel, interruptions, page-hide/navigation/unmount and late permissions clean up tracks/resources and preserve correct elapsed state.
- [x] **J02** — Saved originals are intact and playback reflects codec support; sample transcript has no matching real audio and is never attached to a newly recorded conversation.
- [x] **J03** — Corrections preserve segment ID/time/speaker/audio, separate notes and source links; repeated memory save updates a stable record and stales dependent reports appropriately.

## K Visual design and accessibility

- [x] **K01** — Exact light heart palette: canvas #FBF7F5, white #FFFFFF, accent #B84250, deep red #8C2F3B, petal #FAE6E5, linen #DBCBC9. Deep red on petal remains readable; no stale appearance toggle.
- [x] **K02** — Native Apple Health hierarchy and browser MyChart-informed organization suit the platform; new landing intent is minimal medical/technical, without invented clinical claims.
- [x] **K03** — Check all main pages/details/forms at 375,390,768,1024,1440,1920 and large text/zoom; no clipped/hidden primary actions, horizontal overflow, unsafe fixed navigation or unusable forms.
- [x] **K04** — Keyboard navigation, focus restoration/trapping, Escape, labels, screen-reader names, contrast, control size, reduced motion, status and error announcements work.
- [x] **K05** — Safari/Firefox/iPhone hardware, secure contexts, audio formats and export are either verified with supported tools or listed unverified; IndexedDB is not an offline-launch/service-worker guarantee.

## L Build, deployment and supply chain

- [x] **L01** — Vercel root/nested configuration, framework/install/build/output, sibling fixture access, generated assets and routing agree; prove /, /demo, /login, /signup, deep-link/refresh behavior.
- [x] **L02** — Dist hosting is distinct from Node proxy and Vapor. /v1 and /health require deployed authenticated routing; frontend environment keys alone never constitute hosted backend.
- [x] **L03** — Local production proxy retains fixed destination, route/method/header allowlists, path/symlink/traversal protection, CSP/PDF/OCR/WASM compatibility and bounded bodies/deadlines.
- [x] **L04** — Clean pinned dependency install and native/server/web builds work; inspect dependency surface and lockfile portability, ignored secrets/output and release configuration. No upgrades as part of review.

## M Measured efficiency

- [x] **M01** — Measure representative bounded large synthetic record/PDF/audio cases: startup/chunks, search/relevance, main-thread serialization, memory retention, worker cleanup, repeated reads and SQL queries.
- [x] **M02** — Reproduce previous sync generation/collision/dedup/budget fixes before reopening them; evaluate streaming/memory and cache proposals with measured impact, not speculative micro-optimization.
- [x] **M03** — Distinguish worthwhile architectural simplification from harmful abstraction/chunk proliferation; recommend smallest measurable improvements with cost and verification.

## N Evidence, testing and final feedback

- [x] **N01** — Tests assert user outcomes, failure paths and races against production logic; mocks are labeled and isolated; inventory meaningful coverage gaps instead of counting assertions alone.
- [x] **N02** — Exercise synthetic import-review-save-report-source-edit-stale-regenerate-export-reload and booking/transcript-memory journeys in native/browser where tools permit.
- [x] **N03** — Independent validators reproduce major findings, challenge false positives, deduplicate shared issues and distinguish defect/evidence gap/WIP/roadmap.
- [x] **N04** — Deliver ranked repair backlog, checklist coverage, commands/logs, exact file/line/trigger, confidence, tests/limits and three-person owner recommendations. No audit claim exceeds observed evidence.
