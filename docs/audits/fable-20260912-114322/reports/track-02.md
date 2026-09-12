# Track 02 report: Native domain and medical evidence

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip` (frozen worktree `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`).
Reviewer role: Track 02 source reviewer, wave A. Model Fable 5.1 (claude-fable-5-1); effort as configured by the platform (Ultracode was requested; the exact effort setting is not observable from inside the worker).
Method: read-only source review of the assigned files, line citations verified with `sed -n`, a Python re-implementation of the ReportEngine algorithm run against the checked-in fictional seed (scratchpad only, no writes to the worktree), and the shared runner's logs under `evidence/`. No builds, tests, servers, simulators, providers or databases were touched by this track.

The captured WIP diff (`.audit-source-delta.patch`) does not touch any file in this track's scope (its headers list only `.env.example`, READMEs, `apps/web/scripts/serve*.mjs`, `apps/web/src/main.tsx`, `apps/web/vercel.json`, docs, `ProviderConfiguration.swift`, `GeminiProviderTests.swift`). All findings below therefore apply equally to `cfe0997` and to the snapshot with WIP applied.

## 1. Scope and inventory

### Assigned production files (all fully read, every line)

| File | Lines | Status |
| --- | --- | --- |
| `apps/ios/Reva/Core/Models.swift` | 237 | inventoried, fully read |
| `apps/ios/Reva/Core/SymptomEntry.swift` | 142 | inventoried, fully read |
| `apps/ios/Reva/Core/ReportEngine.swift` | 167 | inventoried, fully read |
| `apps/ios/Reva/Core/BookingEngine.swift` | 37 | inventoried, fully read |

### Assigned test files (all fully read)

| File | Lines | Notes |
| --- | --- | --- |
| `Tests/RevaCoreTests/DomainTests.swift` | 167 | staleness, pins/source versions, question authority, calendar-date round trip, local excerpt negation, deep-passage evidence, snapshot validation, booking idempotency, atomic persistence |
| `Tests/RevaCoreTests/SymptomEntryTests.swift` | 172 | validation failures, exact record text, list date, legacy decode (symptomEntry key removed), page-0 citation |
| `Tests/RevaCoreTests/FixtureEvidenceTests.swift` | 180 | expected-evidence scenarios, reference resolution to version/page, pin override, ambiguous scan caveat |
| `Tests/RevaCoreTests/MedicalProfileTests.swift` | 76 | legacy profile decode without optional fields, empty lists, partial updates |
| `Tests/RevaCoreTests/LiveServerTests.swift` | 221 | opt-in (skipped unless `REVA_RUN_LIVE_CLIENT_TESTS`), outside my functional focus |
| `Tests/RevaCoreTests/TransportTests.swift` | 390 | read for context; transport is track 03's scope |
| `Tests/RevaCoreTests/ProviderClientTests.swift` | 473 | read for context; provider client is track 03's scope |

Files inventoried: 11. Files only sampled: none.

### Shared interfaces consulted (read, not reviewed; findings there are attributed to their owner tracks)

`apps/ios/Reva/State/AppStore.swift` (records/visits sort), `AppStore+Visits.swift`, `AppStore+AI.swift`, `AppStore+Symptoms.swift`, `AppStore+Records.swift`, `AppStore+Bookings.swift`, `Features/Records/SymptomEntryEditorView.swift`, `Features/Records/RecordEditorView.swift`, `Features/Records/RecordDetailView.swift`, `Features/Preparation/ReportView.swift`, `Features/Preparation/VisitsView.swift`, `Features/Visits/RecordingDetailView.swift`, `Features/Visits/VisitEditorView.swift`, `Features/Booking/*EditorView.swift`, `server/Sources/RevaServer/Models.swift` (snapshot validation), browser twins `apps/web/src/core/domain.ts`, `symptoms.ts`, `models.ts`, `validation.ts`, `mutations.ts`, `apps/web/src/core/__tests__/domain.test.ts`, `demo/seed.json`, `demo/expected-evidence.json`, `COMPATIBILITY.md`, the first commit's `Models.swift` (`git show eb2ec3a:...`, read-only) for legacy key analysis, and the concurrent contract `/Users/tempadmin/Documents/Reva/docs/task-specs/accounts-and-tiger.md` (read-only).

### Scratch helper (not evidence of Swift execution)

`/private/tmp/claude-502/-Users-tempadmin-Documents-Reva/a4829c72-eed5-4457-959e-34f8c5715bdc/scratchpad/port_check.py` re-implements the Swift signature, selection, page-score and excerpt code as read, applied to `demo/seed.json`. Output `port_check.out` (same directory). Results used below: the three seed visit signatures produced by the port equal the browser goldens in `domain.test.ts:24-26`; every seed scenario in `expected-evidence.json` satisfies mustInclude/mustExclude/allowed; no seed page's first 24 content lines exceed 1800 characters (max 888); tibia record page scores are `[(0,0),(1,0)]`, `[(8,0),(8,25)]`, `[(1,0),(1,0)]` for the three seed visits. This is a reading aid; the runner evidence request ER-02-02 asks for the same numbers from actual Swift.

### Runner evidence available at writing time

- `evidence/r1-10-swift-test-root.log` lines 36-151: root package `swift test`, 44 tests executed, 1 skipped (LiveServerTests, env-gated), 0 failures. DomainTests 9/9, FixtureEvidenceTests 4/4, MedicalProfileTests 3/3, SymptomEntryTests 6/6, ProviderClientTests 8/8, TransportTests 13/13.
- `evidence/r1-07b-vitest-after-assets.log` line 20: `src/core/__tests__/domain.test.ts` 12 tests passed (includes "matches every native fixture signature exactly" against the three golden hashes). The first Vitest run `r1-07-vitest.log` failed on a missing generated `public/demo/expected-evidence.json`; that is a build-asset ordering matter for track 06/16, not a domain defect.
- `evidence/r1-18-xcodebuild.log` line 1251: `BUILD SUCCEEDED` for the iOS app.

## 2. Checklist dispositions

| ID | Disposition | Basis |
| --- | --- | --- |
| C06 | Defect (P2, RVA-02-001); otherwise Pass for the domain layer | `SymptomEntry.validated()` (SymptomEntry.swift:25-58) enforces symptom 1-120 chars single line, strict ISO instant with calendar-day check (122-141), not more than 5 minutes in the future (39), valid zone, severity in mild/moderate/severe or nil, bounds 12000/2000. `makeRecord` (86-118) preserves id/uploadedAt/notes/version, sets tags `self-reported`+`symptoms`, `symptomEntry` provenance, `pageCount 1`, `pageTexts nil`, `summaryModel nil`; list date derived in the entry zone (101-107). Save path guards version and entry equality (AppStore+Symptoms.swift:23). Tests: SymptomEntryTests 6/6 in r1-10. Defect: record text pairs the UTC instant with the local zone name (RVA-02-001). Search/filter/edit/delete UI is track 04's scope (deferred there). |
| D05 | Defect (P2, RVA-02-002; P3, RVA-02-005) | Local excerpt is exact source lines (ReportEngine.swift:14-16) and origin labels are honest (`summaryLabel` Models.swift:59-62; RecordDetailView derives "Local excerpt"/model label; `summaryModel` cleared on text change RecordEditorView.swift:65-67). Defects: the 1800-character cut can end mid-token (dose/unit/negation) with no marker (RVA-02-002); fixture-wrapper stripping is applied to user documents (RVA-02-005). |
| E01 | Defect (P3, RVA-02-006, RVA-02-007; suggestion RVA-02-008) | Visit keeps `date` as an ISO string plus `timeZone` (Models.swift:105-106); editors write via `RevaDate.iso` and display with the visit zone. Notes/questions mirrored into the report on save (AppStore+Visits.swift:11-14); question authority in ReportEngine.swift:146. Defects/suggestions: "Prepared" and recording dates rendered in UTC calendar day (006), visit list sorted lexically by ISO string (007, AppStore.swift:98, Person 2), no visit version so concurrent save is last-writer-wins (008). DST is handled by Foundation zone math; no DST-specific test exists. |
| E02 | Pass (with P3 RVA-02-004) | Selection (ReportEngine.swift:54-89) uses goal/concern/type words plus fixed synonym groups; no absolute body-part rule. Seed scenarios pass in FixtureEvidenceTests (r1-10 lines 62-67) and in the port: orthopedics selects history/tibia/fibula/imaging, excludes ear/labs/ecg/diary; page 2 of the tibia record wins under the implant bonus (score 8+25 vs 8). Pins score 1000 and survive (tested). Weakness: generic words ("patient", "reported", "documents") count as terms, so the completed seed visit selects all nine records including the ear note (RVA-02-004). |
| E03 | Defect (P2 RVA-02-002; P3 RVA-02-003, RVA-02-005) | Quotations are substrings of the chosen page (`relevantExcerpt` 154-166 returns joined source lines) and every reference carries recordID/page/sourceVersion (SourceReference Models.swift:67-74; `sourcePage` 0 for typed text, ReportEngine.swift:122). AI candidate IDs are validated as a subset of supplied IDs (AppStore+AI.swift:57-60) and pages/excerpts are derived natively. Tests: DomainTests:165 substring check; FixtureEvidenceTests:136-138 grounded by whitespace-normalized containment. Defects: mid-token cut (002), last-page tie-break for zero-hit/tied pages (003), wrapper stripping (005). |
| E04 | Pass (Swift golden equality Unverified pending ER-02-02) | Signature covers type/concern/goal/date epoch/sorted pins and every record's id/version/title/date/text/summary/tags/status (ReportEngine.swift:33-47); `isStale` compares (48-51) and is evaluated per row (VisitsView.swift:45, ReportView.swift:29/85). AI path captures the signature before the await and re-checks after (AppStore+AI.swift:40, 51), stores it on the report (66-68), and preserves user questions/notes (74-79; ReportEngine.swift:146-147). Staleness tests DomainTests 9/9 (r1-10). Python port of the Swift algorithm reproduces the three browser goldens exactly; browser test passes in r1-07b. No Swift test asserts the literal golden hashes, so the "actual Swift" clause is an evidence gap (ER-02-02). |
| F03 | Pass | Native Codable keeps IDs, timestamps and date-only values as verbatim strings; optional fields (`surgeriesAndImplants`, `careNotes`, `sourceRecordingID`, `summaryModel`, `symptomEntry`, `sourceVersion`, `generationModel`, provider fields) are `Optional` with `nil` defaults so absent keys decode (Models.swift:9, 26-45, 87-98). Every non-optional key existed in the first commit (`eb2ec3a`), so legacy snapshots decode. Tests: MedicalProfileTests:13-17, SymptomEntryTests:118-140, DomainTests:133-136 (calendar-date round trip). Server stores the snapshot opaquely with structural checks only (server Models.swift, consulted). Gap: legacy tests only omit optional keys; no test decodes a first-commit-shaped snapshot (RVA-02-012). |
| H05 | Pass for the native extractive engine; server prompt/data separation Deferred to the server/provider tracks | The native engine is purely extractive: it never interprets record text as instructions, cannot invoke tools, and the AI path rejects unknown source IDs (AppStore+AI.swift:57-60). Only the fixture-marker parsing (RVA-02-005) reacts to document content, and it can only shrink excerpts. |

## 3. Findings

Severity order. All statuses are `candidate` or `suggestion`; nothing is marked `confirmed` because no finding was executed in Swift by this track.

### RVA-02-001 (candidate, P2) Symptom record text quotes the UTC instant beside a local zone name

- File: `apps/ios/Reva/Core/SymptomEntry.swift:66` (`"Occurred at: \(observedAt) (\(timeZone))"`). Browser twin: `apps/web/src/core/symptoms.ts:57`.
- Trigger: a user in `America/Chicago` records a symptom observed 2026-09-11 at 21:15 local. The editor binding writes `observedAt` via `RevaDate.iso` (SymptomEntryEditorView.swift:40), which always emits `Z`, so the entry is `2026-09-12T02:15:00Z` with `timeZone = America/Chicago`.
- Expected: the record body (which is the quoted source text for reports and the visible record) states the occurrence in the user's zone, or the instant with its real offset, so the day/time shown agrees with the record's list date.
- Actual: `Occurred at: 2026-09-12T02:15:00Z (America/Chicago)`. SymptomEntryTests.swift:77 pins this exact line and line 88 asserts the same record's list date is `2026-09-11`, so the record's own text and its list date disagree by one calendar day for any evening observation west of UTC.
- Impact: report quotations copy this line verbatim; a reader (or clinician) can attribute the symptom to the wrong day, and the "(America/Chicago)" suffix invites reading 02:15 as a local time. No data loss: `symptomEntry.observedAt`/`timeZone` are stored precisely.
- Evidence: source lines above; `Tests/RevaCoreTests/SymptomEntryTests.swift:77,88`; `r1-10-swift-test-root.log` lines 104-118 (these tests pass, i.e. the behavior is the current contract).
- Confidence: high (behavior); the classification as unintended is a judgement, hence candidate.
- Smallest fix: format `observedAt` in `entry.timeZone` with an explicit offset (for example `2026-09-11 21:15 (America/Chicago, UTC-05:00)`) in `recordText`, mirror it in `symptoms.ts`, and update the pinned test string in both clients in the same change (record text feeds `version` bumps and the report signature, so existing records change only when re-saved).
- Regression check: SymptomEntryTests: entry `2026-09-12T02:15:00Z` / `America/Chicago` produces record text containing `2026-09-11` and `21:15`; browser symptoms test asserts the identical string.
- Owner: Person 1 (records), with the Captain for the browser twin.

### RVA-02-002 (candidate, P2) 1800-character excerpt cut can split a value, unit or negation with no marker

- File: `apps/ios/Reva/Core/ReportEngine.swift:15` (`localExcerpt`), also `:165` (`relevantExcerpt`). Browser twin: `apps/web/src/core/domain.ts:61,161`.
- Trigger: any record page whose first 24 non-blank content lines join to more than 1800 characters (an OCR'd lab table with 24 lines of about 80 characters). `localExcerpt` is the stored summary after every text edit (RecordEditorView.swift:65-67) and the report quotation for pages with no focus hit; `relevantExcerpt` applies the same cut after the best-hit window.
- Expected: quotations end at a line boundary or carry a visible marker, so `Potassium 4.15 mmol/L` cannot become `Potassium 4.1` and `No chest pain` cannot become `No`.
- Actual: `.prefix(1800)` cuts at an arbitrary character with no ellipsis. `DomainTests.swift:114-117` covers negation only for a 3-line text; `FixtureEvidenceTests.swift:136-138` grounds excerpts by substring containment, which a mid-token cut still satisfies; `DomainTests.swift:165` likewise.
- Impact: altered dose/unit/negation in the "Local excerpt" summary and in the pre-visit brief for long pages (D05/E03). Not exercised by the seed (max joined length 888, port_check.out section 5).
- Evidence: source lines; port_check.out section 5.
- Confidence: high that the cut happens; medium on how often real uploads reach it.
- Smallest fix: cut at the last newline (or whitespace) at or before 1800 and append a marker such as ` [...]` in the excerpt only (not in signature inputs), in both `localExcerpt` and `relevantExcerpt` and their browser twins.
- Regression check: unit test with 24 lines x 80 characters ending in `Potassium 4.15 mmol/L`: excerpt ends at a line boundary, contains no partial token, and still passes the grounded-substring assertion.
- Owner: Captain (shared core, both clients).

### RVA-02-003 (candidate, P3) Page tie-break selects the last page for zero-hit or tied multi-page records

- File: `apps/ios/Reva/Core/ReportEngine.swift:112-117`. Browser twin: `apps/web/src/core/domain.ts:180-183` (`score >= maximum`).
- Trigger: a multi-page record selected by pin (score 1000) or by a context tag whose pages all score equally for the visit focus (seed: the two-page tibia record under `demo-visit-primary-20260908` scores `[1,1]`; a pinned scan with zero hits scores `[0,0,...]`).
- Expected: with no distinguishing hit the citation should point at the first page (the document opening, which is what the fallback excerpt quotes), or the tie rule should at least be explicit and tested.
- Actual: `Sequence.max(by:)` replaces the running maximum whenever `areInIncreasingOrder(current, candidate)` is true; with the closure returning `lhs.offset < rhs.offset` on ties, a later page always wins. The reference cites the last page, and the excerpt is that page's opening lines, so the citation is still grounded (FixtureEvidenceTests pass) but the chosen page is the least informative one for scanned records that end with signature/footer pages. The intent of writing `lhs.offset < rhs.offset` reads as "prefer the earlier page", which is the opposite of the effect; the browser twin's `>=` produces the same last-page result, so the two clients agree.
- Impact: lower-quality citations for pinned/context documents; no false quotation.
- Evidence: source lines; port_check.out section 4; `Swift.Sequence.max(by:)` semantics.
- Confidence: medium (behavior is certain; whether last-page is intended is not documented).
- Smallest fix: return `lhs.offset > rhs.offset` on ties (first page wins) in Swift and `score > maximum` in the browser, plus a comment stating the rule.
- Regression check: unit test: a 3-page record with zero focus hits and a pinned selection cites page 1; a 2-page record with hits only on page 2 cites page 2 (unchanged).
- Owner: Captain.

### RVA-02-004 (candidate, P3) Generic goal words become relevance terms; the fixture trailer is indexed

- File: `apps/ios/Reva/Core/ReportEngine.swift:72` (terms filter), `:77-79` (index built from title+tags+summary+full text).
- Trigger: the completed seed visit `demo-visit-primary-20260908` (concern "Discuss patient-reported brief palpitations and nausea.", goal "Review existing source documents and organize unresolved questions before the follow-up visit.").
- Expected: the unrelated ear note is excluded for a palpitations/nausea visit (E02 wording), or at least ranked as context-free.
- Actual: `patient`, `reported`, `documents`, `existing`, `organize` survive the stop list (they are longer than 3 letters and not listed), and every seed record's text/summary contains "patient"/"reported"/"documents" (partly via the fixture trailer sentences that the index does not strip). The ear record scores 30 and all nine records are selected (port_check.out section 2). Expected-evidence.json has no scenario for this visit, so no test constrains it.
- Impact: over-inclusion for goals written in everyday language; not a false citation.
- Evidence: port_check.out section 2; source lines.
- Confidence: high for the seed behavior (port), pending Swift confirmation in ER-02-02.
- Smallest fix: extend the stop list with document-generic words (patient, reported, documents, existing, organize, unresolved) and build the index from `contentLines(record.text)` so the demo trailer is not indexed; add an expected-evidence scenario for the completed visit.
- Regression check: FixtureEvidenceTests scenario for `demo-visit-primary-20260908` with mustExclude ear-infection.
- Owner: Captain.

### RVA-02-005 (candidate, P3) Fixture-wrapper stripping is applied to every user document

- File: `apps/ios/Reva/Core/ReportEngine.swift:21-29`.
- Trigger: a real uploaded document whose first 10 non-blank lines contain a line starting `Source date:` or `Week ending:`, or any line starting `Invented for Reva software demonstration.`.
- Expected: excerpts of user documents quote the document from its first line; only demo fixtures carry the wrapper.
- Actual: `contentLines` drops everything up to and including the last such metadata line in the first 10 lines, and everything from the trailer line on, for all records (there is no `isDemo` check). A lab report headed `Source date: 2026-09-01` loses its heading block from the summary/quotation and from page scoring (which uses `contentLines`).
- Impact: missing header context in excerpts; `record.text` itself is intact so nothing is lost from storage.
- Evidence: source lines; `MedicalRecord.isDemo` (Models.swift:40) is available but unused here.
- Confidence: high.
- Smallest fix: apply the marker stripping only when `record.isDemo` (pass the flag into `contentLines`/`localExcerpt`), or move the wrapper out of fixture text.
- Regression check: unit test: non-demo record starting with `Source date: 2026-09-01\nPotassium 4.1 mmol/L` keeps both lines in `localExcerpt`.
- Owner: Captain.

### RVA-02-006 (candidate, P3) `RevaDate.display(time: false)` renders the UTC calendar day of instants

- File: `apps/ios/Reva/Core/Models.swift:225-231`; callers `Features/Preparation/ReportView.swift:27` ("Prepared ..."), `Features/Visits/RecordingDetailView.swift:27`.
- Trigger: a report generated at 21:30 `America/Chicago` on 2026-09-11 has `createdAt = 2026-09-12T02:30:00Z`.
- Expected: "Prepared Sep 11, 2026" (the user's day), as the comment on line 203 states ("display actual instants in the supplied zone").
- Actual: `display` uses `TimeZone(secondsFromGMT: 0)` whenever `time == false`, so the header reads "Prepared Sep 12, 2026"; same for recording dates. The rule is correct for date-only values (record dates) but the callers pass instants. Browser `formatDate` has the same UTC-when-no-time rule (domain.ts:28).
- Impact: off-by-one day labels for evening activity west of UTC; cosmetic but medical-context sensitive.
- Evidence: source lines.
- Confidence: high.
- Smallest fix: callers that display instants pass `time: true` (or add a `dayOfInstant(zone:)` variant) and the browser twin mirrors it.
- Regression check: unit test `RevaDate.display("2026-09-12T02:30:00Z", time: true, zone: "America/Chicago")` contains "Sep 11".
- Owner: Captain (RevaDate) / Person 2 (callers).

### RVA-02-007 (candidate, P3) Visit ordering compares ISO strings lexically; mixed offsets misorder same-day visits

- File: `apps/ios/Reva/State/AppStore.swift:98` (outside strict scope; the contract is `Visit.date: String` with no normalization, `Models.swift:105`). Overlaps tracks 03/04.
- Trigger: seed visits carry `-05:00` offsets (`2026-09-15T09:00:00-05:00` = 14:00Z); app-created visits use `RevaDate.iso` (`Z`). A visit created for 2026-09-15 13:00Z sorts after the 14:00Z seed visit because `"...T13:00:00Z" > "...T09:00:00-05:00"` lexically. `BookingEngine.confirm` copies `request.earliest` verbatim (BookingEngine.swift:31), so booking-derived visits keep whatever format the request used.
- Expected: visits ordered by instant.
- Actual: lexical ordering; records are already ordered via `RevaDate.parse` (AppStore.swift:91-96), so the visits sort is the inconsistent one.
- Impact: wrong order in the visits list when formats mix (imports, browser-created data, demo seed plus user visits).
- Evidence: source lines; `demo/seed.json` visit dates.
- Confidence: high for the mechanism; medium for user exposure (requires mixed formats on one day).
- Smallest fix: sort by `RevaDate.parse($0.date)` with id tie-break, or normalize `Visit.date` to UTC `Z` on save.
- Regression check: unit test sorting `["2026-09-15T13:00:00Z", "2026-09-15T09:00:00-05:00"]` yields the `Z` visit first.
- Owner: Person 2.

### RVA-02-008 (suggestion, P3) `Visit` has no version; `save(visit)` is whole-value replace

- File: `apps/ios/Reva/State/AppStore+Visits.swift:11-22`; model `Models.swift:99-114`.
- Observation: records carry `version` and every record/symptom save guards on it (AppStore+Records.swift:20-24, AppStore+Symptoms.swift:23); visits do not. A pull that completes while the visit editor is open, or an AI report that lands between open and save, is overwritten by the editor's stale copy (the AI path itself is guarded by the signature re-check, AppStore+AI.swift:51, but the plain editor save is not). E01 asks that concurrent edits do not overwrite each other.
- Direction: add a `version`/`updatedAt` to `Visit` (optional for legacy decode) and reject stale saves the way records do.
- Regression check: test that `save(visit)` with an outdated copy throws after the stored visit changed.
- Owner: Person 2.

### RVA-02-009 (suggestion, P3) `BookingEngine.validate` accepts unparsable date strings

- File: `apps/ios/Reva/Core/BookingEngine.swift:16`.
- Observation: `RevaDate.parse` returns `.distantPast` for unparsable text, so `"abc" <= "xyz"` passes and `confirm` later writes `visit.date = "abc"` (line 31). Native editors always write ISO via `RevaDate.iso`, so the main path is safe; browser-synced or imported bookings are not re-validated. The test `testBookingConfirmationIsIdempotentAndBounded` covers idempotency and bounds but not rejection of malformed dates, phone shortfall or bad zone.
- Direction: require both dates to parse (`RevaDate.parse != .distantPast` or a strict parser) and add failure-path tests.
- Owner: Person 2.

### RVA-02-010 (suggestion, P3) Formatter allocation per call in `RevaDate`; per-access sorting parses every record

- File: `apps/ios/Reva/Core/Models.swift:205-231`; consumers `AppStore.swift:91-96`, `VisitsView.swift:45`.
- Observation (asymptotic, unmeasured): `parse` allocates up to three formatters per call; `AppStore.records` sorts on every access with two `parse` calls per comparison (O(N log N) parses per SwiftUI body evaluation); `isStale` hashes the full record corpus per visit row. With the 5000-record cap the server allows, this is a plausible UI-latency source but no measurement exists. Not a defect claim.
- Direction: cache formatters (static lets; `ISO8601DateFormatter` is thread-safe) and memoize the sorted arrays/signature per snapshot revision; measure first (ER-02-02 includes a bounded timing).
- Owner: Captain.

### RVA-02-011 (suggestion, P3) `VisitReport.isDemo` defaults to `true`

- File: `apps/ios/Reva/Core/Models.swift:96`.
- Observation: `ReportEngine.generate` does not set `isDemo`, so every locally generated report over real user records is flagged as demo data; the AI path sets it to `false` (AppStore+AI.swift:68). Nothing in the native app reads the flag today, but it is serialized to the server and browser, where a future "demo" badge or cleanup filter would misclassify real reports.
- Direction: default to `false` and set `true` only for seeded demo reports; or drop the flag.
- Owner: Captain.

### RVA-02-012 (suggestion, P3) Test gaps in the assigned test target

- File: `Tests/RevaCoreTests/DomainTests.swift:114` (anchor for the excerpt tests).
- Gaps observed after reading all seven test files: no Swift test asserts the literal signature goldens used by the browser (E04 "actual Swift"); no page-selection test for a multi-page record with zero or tied hits; no truncation-boundary test for the 1800-character cut; no `BookingEngine.validate`/`confirm` rejection tests (short phone, bad zone, unparsable dates, non-proposed status); no `RevaDate.display`/`day` zone tests; legacy Codable tests only omit optional keys rather than decoding a first-commit-shaped snapshot; no DST-crossing visit test. Existing tests do assert user outcomes (staleness, pins, grounded citations, question authority, list date) and several failure paths (symptom validation, duplicate IDs, unsafe filenames, malformed provider responses), which is good coverage for the happy path and validation of records.
- Direction: add the seven tests listed; the golden test can decode `demo/seed.json` and compare `ReportEngine.signature` to the three hex strings in `domain.test.ts:24-26`.
- Owner: Captain.

### WIP note (not a finding)

The concurrent accounts contract (`docs/task-specs/accounts-and-tiger.md`) adds `UserRecord`/`SessionRecord` on the server and makes `profile.id` the user ID. `AppSnapshot.validate` (Models.swift:170) already requires a nonempty `profile.id`, so no native model change is implied; nothing in this track's scope is blocked on or broken by the contract. Status: WIP, no delta expected in these four files.

## 4. Evidence requests

ER-02-01 (satisfied): root `swift test` was already executed by the runner (`evidence/r1-10-swift-test-root.log`, 44 tests, 0 failures, 1 skipped). No re-run needed.

ER-02-03 (satisfied): browser `domain.test.ts` passed in `evidence/r1-07b-vitest-after-assets.log` line 20 (12 tests, including the native-signature golden test).

ER-02-02 (open, priority high for E04, medium for the rest). Purpose: obtain actual Swift numbers for the claims this track could only derive by reading and by the Python port. Suggested execution, entirely inside the runner's temp directory (no writes to the worktree):

1. `mkdir -p "$RUNNER_TMP/track02-harness/Sources/Harness"` and copy (read-only from the worktree) `apps/ios/Reva/Core/Models.swift`, `SymptomEntry.swift`, `ReportEngine.swift`, `BookingEngine.swift`, plus a minimal `RevaError` stub if `RevaError` is not defined in those files (check `apps/ios/Reva/Core/` for its definition and copy that file too), into `Sources/Harness/`; write a `Package.swift` (swift-tools-version 5.9, one executable target) and `main.swift` that:
   - decodes `demo/seed.json` into `AppSnapshot` and prints `ReportEngine.signature(visit:records:)` for each of the three visits (expected: `b2437a79...6731`, `6b7fbb52...9163`, `5718d660...a619`, see `apps/web/src/core/__tests__/domain.test.ts:24-26`);
   - prints `ReportEngine.selectedRecords(visit:records:).map(\.id)` per visit (expected for `demo-visit-primary-20260908`: all nine records including `demo-record-ear-infection`, per RVA-02-004);
   - prints the `page` of the `demo-record-tibia-procedure` reference in `ReportEngine.generate` for `demo-visit-primary-20260908` (expected 2, per RVA-02-003) and for `demo-visit-orthopedics-20260917` (expected 2);
   - prints `ReportEngine.localExcerpt` of a synthetic 24-line page of 80-character lines whose last line is `Potassium 4.15 mmol/L`, showing the final 30 characters (expected: a cut mid-token, per RVA-02-002);
   - times 10000 iterations of `RevaDate.parse("2026-09-15T09:00:00-05:00")` with `ContinuousClock` (bounded measurement for RVA-02-010).
2. Run `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$RUNNER_TMP" swift run --package-path "$RUNNER_TMP/track02-harness" --scratch-path "$RUNNER_TMP/track02-harness/.build"` from `$RUNNER_TMP`, log to `evidence/r2-02-native-domain-harness.log`.
3. Expected: the three signatures equal the goldens; if they differ, E04 becomes a Defect and RVA-02-004/003 numbers must be re-read from the log.

## 5. What was NOT reviewed and why

- Any file outside `apps/ios/Reva/Core/{Models,SymptomEntry,ReportEngine,BookingEngine}.swift` and `Tests/RevaCoreTests/**` was consulted only to trace callers and browser parity; those files belong to tracks 03 (AppStore/LocalRepository/ServerClient), 04 (native record/profile/preparation features), 06 (browser core) and 08 (browser visits). Findings that anchor there (RVA-02-007, RVA-02-008) are labeled with their owner and the overlap.
- `LiveServerTests.swift`, `TransportTests.swift`, `ProviderClientTests.swift` were read in full for inventory but their subject matter (transport, provider clients) was not audited here; track 03 owns it.
- Server-side prompt/data separation for H05 (Gemini prompt construction, output validation) is the server/provider tracks' scope; this track only confirms the native engine is extractive and validates AI-supplied IDs.
- Runtime behavior was not executed by this track (rule: only track 17 runs builds/tests). All Swift-execution claims cite the runner's `r1-10` log or are listed as ER-02-02.
- The live main checkout's application files were not read (rule), except the read-only contract file named in the brief.

## 6. Statement on actionable defects

Two candidate defects of severity P2 survive review (RVA-02-001 symptom record text UTC/zone mismatch; RVA-02-002 unmarked mid-token excerpt cut), five P3 candidates (003 last-page tie, 004 generic relevance terms, 005 wrapper stripping on user documents, 006 UTC calendar-day display of instants, 007 lexical visit ordering) and five suggestions (008-012). No P0/P1 defect was found in the assigned files: legacy snapshot decoding, signature/staleness coverage, AI-result ID validation, question/notes authority, booking idempotency and symptom validation all hold as read and as exercised by the runner's 44 passing root tests. No credential-like values were encountered in the reviewed files.
