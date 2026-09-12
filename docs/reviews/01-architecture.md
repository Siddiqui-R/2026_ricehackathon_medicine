# Reva architecture review 01: spec consistency and feasibility

**Reviewer:** Claude Fable 5.1, Extra effort, September 12, 2026. Read-only.
**Scope:** completion-criteria.md, task-list.md, reva-style-plan.md, design/palette.json, reva-stack-spec.md sections 2 to 10, the scaffold, and implementation-contract.md v1 plus task-specs/backend.md, which appeared mid-review and settle the booking enum, snapshot sync, BYTEA attachments, `/health`, and the no-sample-transcript rule.

## Verdict

The set is feasible for a native SwiftUI hackathon prototype, and the gates correctly narrow the production stack spec to a local-first demo with a prepared server. Remaining conflicts sit at seams the stack spec never defined because it assumed cloud services; contract v1 leaves eight open. Each would break the demo route or let the UI imply a service ran; fixes belong in contract v2.

## Findings

### 1. Client sync policy is undefined
**Issue.** Stack spec section 3 makes the server authoritative; gates 4 and 11 make local persistence mandatory without credentials. Contract v1 defines whole-snapshot `PUT /v1/state` with 409 on stale revision but not when the app pushes, what wins on 409, or that attachments upload before the snapshot referencing them. One 409 would otherwise block every later save.
**Fix.** Local store is authoritative on device in every mode. When a base URL is configured, push after each mutation; on 409 fetch the revision and re-put the local snapshot (client wins, logged). Upload attachments first; never show demo data when a configured server is unreachable.

### 2. Local summary has no provenance kind and is mislabeled
**Issue.** Gate 6 and T13 require a deterministic, honestly labeled local summary; contract v1 stores `summary` as bare text with no kind. Style plan section 7 mandates the label "AI summary", which gate 6 forbids when no provider ran. Live imports will look thinner than seeded records; T29 defines no matching mechanism.
**Fix.** Add `summaryKind: localExcerpt | demoFixture | provider` and `sourceHash` to `MedicalRecord`. Local excerpt uses NaturalLanguage sentence, date, and number extraction plus keyword tags, citing only found text. Imports matching a fixture hash receive its summary labeled "Demo summary · bundled fixture". Amend style plan section 7.

### 3. Page citations cannot be derived from a flat text field
**Issue.** Report sources carry `{recordID, page, excerpt}`, but `MedicalRecord.text` is one string with only `pageCount`, so gates 7 and 8 ("opens the right page") degrade to whole-record links. `sourceSignature` has no defined composition, so stale detection (T14/T17) cannot name the changed record, and transcript citations lack a timestamp.
**Fix.** Store `pageTexts: [String]` from PDFKit page strings or Vision. Add `recordVersion` and optional `segmentStart` to sources. Define `sourceSignature` as a hash of sorted `(recordID, version)`, goal, concern, questions, and pinned IDs; a mismatch shows stale and names changed records.

### 4. Booking idempotency and relaunch rules are missing
**Issue.** Contract v1 fixes the status enum and adds `scenario` and `confirmedVisitID`, but spec section 7 and style plan section 6 still use other vocabularies, and nothing covers a kill mid-`calling` or a double Confirm (gate 9).
**Fix.** Align spec and style plan to the contract enum. On launch, `queued` or `calling` requests resume from the persisted stage with the outcome scripted by `scenario`. Creating a confirmed visit requires `confirmedVisitID == nil`, set atomically in the same save. Clinic numbers are text, never `tel:` links.

### 5. Recording end state and lock behavior are unspecified
**Issue.** Contract v1 rightly leaves new audio without a transcript, but nothing says what the presenter sees after finishing a real recording, so an empty screen is likely. Info.plist has no background audio mode, so lock pauses capture silently.
**Fix.** Specify the screen: "Saved · 12:04 · Transcription isn't configured in this build" with playback, delete, manual notes, and a sample-visit link. Ship the sample text-only, labeled "Sample transcript · no audio", unless a labeled synthetic file is generated. Add the `audio` background mode or state that recording pauses on lock.

### 6. Fixture scenarios are prose only; the generator drops fixture formats
**Issue.** Gates 7 and 13 and T16/T33 need two goals with documented expected evidence, yet none is named, so tests have nothing to assert and both reports may look alike. `generate_project.py` bundles only `.swift .json .txt .pdf .wav .m4a .png`; `.jpg`, `.heic`, and `.md` fixtures would silently vanish.
**Fix.** Add `fixtures/expected_evidence.json` naming Scenario A (orthopedic follow-up: older implant, imaging, active medications and allergies; excludes the unrelated episode) and Scenario B (unrelated new concern: medications, allergies, labs; implant only as active context), plus one needs-review scan and one modeled conflicting field. Tests read it. Widen the generator whitelist; one generator emits both copies.

### 7. Core test boundary and client configuration are undefined
**Issue.** A root `Package.swift` now gives `RevaCore` a `swift test` target, but the Xcode project compiles the same sources directly, so nothing keeps device-only code out of the core, and T33's relevance, staleness, and idempotency tests are unnamed. `.env` is server-only and unreadable by iOS, yet `.env.example` lists `REVA_API_BASE_URL` beside server secrets, and Settings has no defined status source.
**Fix.** Keep `apps/ios/Reva/Core` free of UIKit, Vision, and AVFoundation and name the three suites in the contract. The client reads base URL and token from xcconfig keys; empty means local. Integration status comes only from a live `/health` probe. Split `.env.example` into client and server sections.

### 8. Style plan foundation and dark mode still describe palettes A to D
**Issue.** Style plan sections 5 and 9 and spec sections 14 and 15 still request an A to D choice, and the foundation canvas `#F2F2F7` contradicts the Ivory canvas in design/README. No dark variants exist; Teal on black is about 2.7:1, failing gate 2, while Aqua on black is about 8.2:1.
**Fix.** Append a derived-token table: Ivory canvas, white cards, Sky for selected and source surfaces, Teal actions (7.7:1 on white); near-black dark canvas with an Aqua-class accent and dark text on filled buttons; Gold and Slate never as text. Mark sections 5 and 9 superseded. Set device family to iPhone only, portrait only.

## Acceptance checklist

1. Fresh install seeds fixtures; relaunch keeps an added record, edited question, new visit, booking state, and recording; reset restores the fixture set exactly.
2. Import each standalone fixture (text-layer PDF, image-only scan, text file, corrupt file); see extracted text, hash-matched demo summary, needs-review state, and readable errors.
3. Every summary shows its kind; "AI summary" is unreachable without a configured provider.
4. Scenario A and B reports differ per `expected_evidence.json`; pinning adds an excluded record; every citation opens the correct page or timestamp; editing a cited record marks it stale with the cause.
5. Export one report PDF; confirm text, dates, and citations are not clipped.
6. Run each booking scenario; tap Confirm twice and relaunch mid-call; exactly one visit per request.
7. Record in the simulator: permission prompt, pause/resume, timer, playback, "not configured" state; sample visit labeled and never linked to new audio.
8. `swift test` passes for domain and server; `.env` is 0 bytes and ignored; integration status follows `/health` with and without a local server.
9. Light and dark on iPhone 17 and the narrowest simulator at the largest accessibility text size; no Teal text on dark surfaces.

**Deferred as manual:** Tiger credentials, provider keys, physical camera and microphone, signing. None excuse items 1 to 9.
