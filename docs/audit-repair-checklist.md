# Audit repair checklist — September 12, 2026

Purpose: Track each confirmed defect, applied repair, regression evidence and remaining verification.
Inputs: The frozen [23-finding audit](audits/fable-20260912-114322/FINAL-REPORT.md), integrated onto `main` at `98261b8`.
Outputs: A reviewable implementation checklist and release gates.
Side effects: None. The original audit and captured worktree remain unchanged.

**22 applicable defects have implementation changes; one finding applies only to captured WIP.** Checked rows mean implemented with the stated evidence. They do not certify unexecuted iPhone hardware, real OCR accuracy, live providers, database operation or deployment.

## Source and report rules

| Done | Finding | Problem and applied fix | Evidence |
| --- | --- | --- | --- |
| [x] | RVA-02-002 | Clipping could change a dose/value. Both clients quote complete source lines within 24-line/1,800-character bounds; omission notices stay outside quotations. Oversized single lines direct the user to full text/original. Recompute legacy local previews for display and provider input. | Swift/browser tests cover doses, units, negation, Unicode, exact spans, line limits and legacy previews. |
| [x] | RVA-02-004 | Generic visit words selected unrelated history. Remove generic selection words and fixture wrappers from retrieval; explicit pins remain authoritative. | Both clients exclude unrelated ear-infection evidence for the primary visit and retain relevant/pinned sources. |
| [x] | RVA-02-005 | An ordinary `Source date:` line could remove preceding content. Require explicit fictional provenance and the exact recognized opening marker before stripping wrappers. | Ordinary headers/trailer-like text and recognized fixtures tested in both clients. |
| [x] | RVA-02-006 | Hiding a timestamp's clock also shifted its date to UTC. Use the visit/local zone for timestamp days; preserve date-only calendar days. | Offset crossing midnight and date-only records tested in both clients. |
| [x] | RVA-04-001 | Native appointments sorted ISO strings. Sort actual instants with stable ID ties. | Production AppStore mixed-offset order and equal-instant tests. |
| [x] | RVA-04-004 | Busy native brief creation silently did nothing. Disable the action while busy and provide retry guidance. | Busy-state rejection and subsequent successful generation tested; actual UI remains a gate. |

The shared `source-rules-v2` signature prefix deliberately makes older briefs stale. Regenerate them to apply the repaired rules. Original text/files, attributed AI summaries and user questions/notes remain intact. See [compatibility](../apps/web/src/core/COMPATIBILITY.md) for signature evidence and limits.

## State ownership and recovery

| Done | Finding | Problem and applied fix | Evidence |
| --- | --- | --- | --- |
| [x] | RVA-03-001 | Failed optional startup repair hid valid loaded data. Keep the snapshot available, show the error and require confirmation before demo reset. | Injected persistence failure retains loaded data; native confirmation source-reviewed. |
| [x] | RVA-04-005 | Stale record edits erased newer summaries/fields. Retain the opening baseline in SwiftUI state; merge only edited fields against current data and reject conflicts. | Production tests cover incoming AI summary, source conflicts, corrected text and kind changes. Parent-refresh baseline source-reviewed. |
| [x] | RVA-05-001 | Native recording notes could replace a newer transcript. Save only notes against the current recording ID. | Transcript, model, timestamps, status and original audio survive the update. |
| [x] | RVA-08-001 | Browser brief notes could clear newly generated questions. Keep immutable opening questions/notes and merge field-specific changes with conflict checks. | Pure merge tests and actual React/jsdom editor rerenders. |
| [x] | RVA-10-001 | Native late provider results could publish into a changed connection/workspace. Capture both generations; reject stale success/error while allowing unrelated ordinary edits. | 48 delayed-result cases across six operations/four context changes, six valid-result controls, and fresh-preview input preservation. |

## Capture, extraction and originals

| Done | Finding | Problem and applied fix | Evidence |
| --- | --- | --- | --- |
| [x] | RVA-04-006 | Scanner PDFs became Notes and lacked kind correction. Scanner origin selects Scan; intake/editor share configurable kinds. | Exact production intake reset tested; physical scanner remains a gate. |
| [x] | RVA-05-002 | Failed audio finalization left unusable resume guidance. Enter an explicit terminal failure state with discard/restart guidance and reset. | Exact production recorder transitions with AVAudio doubles. |
| [x] | RVA-05-004 | PDF headers suppressed scanned-body OCR. Check mixed pages within the ten-page budget, prioritizing pages with little/no embedded text. Preserve distinct values and warn about unchecked/overlapping text. | Exact production PDF loop with doubles: mixed pages, scan after ten text pages, budget, page mapping and original bytes. Numeric-prefix conflicts such as 5 versus 50 are preserved. |
| [x] | RVA-05-008 | Failed metadata save had no audio retry path. Retain one finalized file and stable metadata; retry persistence, offer sharing and confirm leaving unsaved. | Repeated failures retain URL, bytes, ID, timestamp and duration; finalization runs once. |
| [x] | RVA-07-001 | Browser PDF headers could hide scanned bodies. Detect raster operators, run bounded OCR and keep embedded text with incomplete warnings on failure. | Six injected PDF/OCR adapter tests cover mixed pages, failures, bounds and cleanup. |
| [x] | RVA-07-002 | Failed browser import left unused attachment keys. Commit the original Blob and record in one existing IndexedDB transaction. | Failed commit leaves neither; successful import retains exact bytes/metadata. |

## Presentation and repeatable checks

| Done | Finding | Problem and applied fix | Evidence |
| --- | --- | --- | --- |
| [x] | RVA-04-007 | Native question numbers lacked contrast. Use the shared deep-red text role. | Calculated contrast 6.78:1; native visual check pending. |
| [x] | RVA-04-008 | Native PDF headings retained old teal. Use the current shared deep-red role. | Source review/syntax parsing; export visual check pending. |
| [x] | RVA-14-001 | Tablet links lost names when labels were hidden. Add explicit accessible rail-link names. | Three name tests simulate hidden labels in jsdom; real screen-reader check pending. |
| [x] | RVA-14-002 | Browser text selection lacked contrast. Use white on deep red. | Contrast regression passes. |
| N/A | RVA-16-001 | Captured WIP had contradictory Vercel roots. Current clean `main` has coherent repository-root configuration and no competing nested file. | No deployment change needed here. WIP owner must reconcile when landing that work; hosted behavior not retested. |
| [x] | RVA-16-002 | Standalone checks omitted generated asset prerequisites. Add `pretest` and `pretypecheck` preparation. | Both standalone commands generate assets and pass. |

Focused helpers own source spans, PDF text merging, finalized-recording retries and brief field merges. File contracts and named responsibility blocks document inputs, outputs, effects and preservation rules. Regenerated Xcode metadata includes the new files. Secret environments and dependency/cache directories remain Git-ignored.

## Executed checks and review corrections

- **106 browser tests in 16 files passed**; TypeScript typecheck and production build passed.
- Formatting checks pass after normalizing browser source line endings. Git attributes retain LF for those source formats on Windows; responsibility checks pass across 74 Swift and 61 browser source files. Changed native sources also pass syntax parsing, which is not Apple-framework typechecking.
- **7 HTTP-wrapper tests passed.** The original file-symlink fixture failed with Windows `EPERM`. A Windows directory junction now exercises the same realpath escape without skipping the check; wrapper behavior is unchanged.
- Native focused suites passed: existing optimization checks (six groups), audit state checks, source-integrity checks (four groups), and device checks (five groups). These compile production logic with documented stand-ins for unavailable Apple APIs.
- Independent final review caught the moving native editor baseline, numeric-prefix PDF deduplication and OCR starvation of a late scan. These were corrected before delivery; affected regressions were rerun.
- Windows Swift 6.3.3's formatter moved declaration comments with `OrderedImports` enabled. Comments/imports were restored and formatting/lint used a local `OrderedImports: false` override. The tracked formatter configuration remains unchanged.

Repeat from the repository root:

```sh
python scripts/check_optimization_fixes.py
python scripts/check_audit_state.py
python scripts/check_source_integrity.py
python scripts/check_native_device.py
python scripts/check_code_structure.py
npm --prefix apps/web test
npm --prefix apps/web run typecheck
npm --prefix apps/web run build
npm --prefix apps/web run format:check
node --test apps/web/scripts/serve.test.mjs
```

## Next verification steps

- [ ] On macOS, run both Swift package suites and build the iOS project in Xcode. Recompare current hash vectors with real CryptoKit; Windows equality-only stand-ins do not verify cryptography.
- [ ] Exercise native editor refresh/conflicts, startup recovery/reset, busy preparation, microphone finish/save retry/share, scanner kinds and actual PDFKit/Vision mixed-page OCR. Inspect exported PDF colors/layout.
- [ ] Run current import → review → save → prepare → cite → edit → stale → regenerate → reload journeys across supported browsers, including real OCR and tablet keyboard/screen-reader access. jsdom does not perform real CSS layout or OCR.
- [x] Save Tiger database credentials locally and verify TLS, authentication and a read-only `SELECT 1`. Completed September 12 with normal system trust and hostname verification; no database mutations or application-data reads. The transaction-pool connection reports the underlying `tsdb` database.
- [x] Save the Google key locally and verify authenticated model listing, including the configured `gemini-3.8-flash`. This verifies key/catalog access, not generated-content quality or the running Reva integration.
- [ ] Configure private `REVA_TOKENS` for the backend. It remains empty; PostgreSQL and paid providers cannot use the public demo token.
- [ ] Initialize Reva's database schema and run dedicated migration/persistence/concurrency checks through the real Swift adapter. The read-only probe found no visible `reva_schema_migrations` table. The exact PostgresNIO startup parameters and pool behavior remain unverified.
- [ ] Run/deploy the authenticated Swift backend with persistent storage for call receipts, then configure the browser's same-origin `/v1` and `/health` routing. Vercel's static browser build does not start the backend or deploy local `.env` secrets.
- [ ] Configure and test transcription. The current implementation uses OpenAI Whisper; `OPENAI_API_KEY` is missing. ElevenLabs speech-to-text would require a separate adapter and verification, not just an environment-variable change.
- [ ] Complete the ElevenLabs activation steps below, then test an explicitly reviewed call. No paid generation, phone call or account-permission change was made during this review.
- [ ] Review later account/session/deployment work at a completed checkpoint and verify actual hosted routes. Audit suggestions and unverified candidates are not implied complete by these repairs.

## ElevenLabs activation review — September 12

The signed-in account has Agents entitlement suitable for a prototype. Reva already implements outbound requests, per-call consent, durable replay protection, transcript polling and manual appointment confirmation in both client flows and the Swift backend. A source comparison found no material mismatch with the current [outbound API](https://elevenlabs.io/docs/api-reference/integrations/twilio/outbound-call). This is compatibility evidence, not a successful live call.

| Done | Required step | Current evidence / completion check |
| --- | --- | --- |
| [x] | Confirm account access to ElevenAgents | Agents subscription and configuration surfaces are available. Account billing and usage were not changed. |
| [ ] | Give the server key appropriate ElevenAgents permissions | The existing enabled key has ElevenAgents set to **No Access**. Text-to-speech and speech-to-speech access alone cannot start/poll agent calls. Configure access for the required conversation operations and save the usable key as `ELEVENLABS_API_KEY` in backend secrets. The local value is currently empty. |
| [ ] | Configure a Reva scheduling agent | No Reva agent ID is configured locally; the account's agent route opened template onboarding during review. Create or identify the intended agent, review its behavior, and set `ELEVENLABS_AGENT_ID`. |
| [ ] | Match the scheduling prompt to Reva's request | Consume `request_id`, `clinic_name`, `patient_name`, `appointment_reason`, `earliest`, `latest`, `time_zone` and `preferences`. Request availability within the supplied constraints; leave final confirmation to the user's existing review flow. |
| [ ] | Import an outbound-capable Twilio identity | Phone Numbers explicitly shows no numbers. Use a purchased Twilio number or a Twilio verified caller ID for outbound-only use, then set the returned `ELEVENLABS_PHONE_NUMBER_ID`. Twilio credentials belong in the ElevenLabs integration, not the browser bundle. See the [native integration guide](https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/native-integration). |
| [ ] | Review recording/retention behavior | Reva supplies `call_recording_enabled:false`, which controls Twilio recording; it does not establish every ElevenLabs audio/transcript-retention setting. Verify agent settings before the live test. |
| [ ] | Verify the complete call flow | With backend authentication/storage ready, enable `REVA_ENABLE_LIVE_CALLS` and use a specifically authorized test recipient. Verify dynamic variables, transcript/status, duplicate prevention, unknown outcomes and manual appointment confirmation. The flag remains false. |

An in-browser voice conversation is a separate possible feature: the [ElevenLabs React SDK](https://elevenlabs.io/docs/eleven-agents/libraries/react) supports microphone conversations without a phone number. Reva currently has no such session UI or SDK integration. It would need a backend-issued short-lived token for a private agent, session/error cleanup, microphone tests and narrowly scoped CSP changes. It would not replace the phone connection needed to call clinics.

The existing key also has Speech to Text set to No Access. Switching saved-recording transcription from Whisper to ElevenLabs therefore needs both provider permission and implementation work. Database and Google credentials remain only in ignored local files; this document contains no key values, passwords or account identifiers.
