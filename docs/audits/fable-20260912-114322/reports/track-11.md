# Track 11 — Voice transport and durable outbound calls

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip`, the frozen cfe0997 source plus captured WIP.

Reviewer: Codex continuation after explicit user authorization following Claude usage exhaustion. Read-only source review; no builds, UI, live calls, credentials, database or Git operations by this reviewer. Reused the shared Stage1 runner report; its model/transport tests are mocks and are not live provider validation.

## Preserved Fable output and Codex continuation

The existing `track-11-findings.json` contains six Fable findings. It has been preserved byte-for-byte: SHA256 `81d7554d9466345381448a9b728d682795b223cf3cfb137dd78d5c7bfa945924`. This Markdown report is the Codex completion/review of that partial work, not reconstructed Fable prose. No Fable recommendation was silently promoted into a confirmed defect.

Codex adds one cross-track candidate **RVA-10-001**, whose native live-call publication path is in this track's scope. It is recorded once in track10 JSON and referenced here: old call transcripts/status can publish after a connection/workspace replacement because `AppStore+LiveCalls.swift:53-59` has no captured generation guard. Server receipt ownership is unaffected.

## Inventory and implementation review

Reviewed all four `server/Sources/RevaServer/Providers/Voice*.swift` files (VoiceCalls, VoiceRoutes, VoiceTranscription, VoiceTransport), native `State/AppStore+Bookings.swift` and `State/AppStore+LiveCalls.swift`. Consulted `Features/Visits/LiveBookingEditorView.swift`, `LiveBookingStatusView.swift`, `State/AppStore+Transcription.swift`, `Core/ProviderContracts.swift`, `Core/ProviderClient.swift`, `AppStore.swift`, and `server/Tests/RevaServerTests/VoiceProviderTests.swift`.

- Whisper input preserves original bytes, actual MIME and safe filename in multipart; `whisper-1`, `verbose_json`, segment granularities are explicit (`VoiceTranscription.swift:54-76`). Audio is nonempty and <=16 MiB. Validation rejects malformed, duplicate, negative/out-of-order IDs/offsets, impossible durations, empty speech and excessive text. Generic `Speaker` avoids invented diarization.
- Official [OpenAI transcription reference](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create), checked2026-09-12, lists Ogg and WebM formats and documents `whisper-1` with `verbose_json` segment timestamps. The page supports the transport contract; mocked acceptance of arbitrary synthetic bytes does not prove those bytes are decodable audio.
- The [ElevenLabs outbound reference](https://elevenlabs.io/docs/api-reference/integrations/twilio/outbound-call) confirms the configured agent/number, destination, initiation data, `call_recording_enabled` request fields and success/conversation response. The [conversation detail reference](https://elevenlabs.io/docs/api-reference/conversations/get) is the polling operation. No account-specific agent prompt/model/telephony configuration was inspected; claimed Qwen/temperature/10-minute settings are proposals, not enforced in this code.
- `VoiceCallService.start` gates private paid access/configuration/enablement and validates explicit consent before touching receipts (116-128). It stores owner/request identity and full reviewed payload before the first transport suspension (129-145). Payload changes yield409; identical known-conversation replays return stored status; absent conversation never redials. Directory locking excludes a second process and fsync includes parent directories before outbound side effect (284-298,330-368).
- Provider failure, timeout, malformed success and post-dial receipt-write failures preserve uncertain intent (165-185). Polling requires the authenticated owner and saved request, validates conversation ID/status/timestamps, bounds transcript content and never dials (189-258). Disabling new calls does not disable reading previously submitted calls, intentionally.
- Native editor has a consent toggle, final explicit confirmation and reviewed clinic/name/reason/window (LiveBookingEditorView:35-84). Literal consent in the store is only reachable from that flow today; Fable correctly classified this as future boundary hardening rather than an exploit. No server outcome automatically confirms the medical visit.
- Simulation transitions are local delays with explicit simulated statuses; confirmation delegates to BookingEngine. Relaunch repairs interrupted queued/calling non-live requests (AppStore:72-82). Native state methods are not covered by the Core package test target; xcodebuild proves compilation only.

## Disposition of preserved Fable findings

| Finding | Codex disposition | Reason |
|---|---|---|
| RVA-11-001 | Retain suggestion | Receipt directory persistence is a documented operational requirement. Changing cwd/loss of ephemeral filesystem is a future Docker/Tiger deployment risk; no completed captured deployment supplies a failing persistent-volume configuration. An absolute path alone would not prove durable storage. |
| RVA-11-002 | Retain cosmetic suggestion | Empty uncertain conversationID is assigned to a non-nil optional and rendered as a blank Conversation line. Source chain verified; no call safety/data failure. |
| RVA-11-003 | Retain latent suggestion | Busy guard can silently return through direct method use, but current editor disables submission while busy; no reachable first-party conflict was established. |
| RVA-11-004 | Retain boundary suggestion | Current reviewed editor is sole caller; literal consent and late-bound patient name merit a frozen request contract but are not a current consent bypass. |
| RVA-11-005 | Retain evidence gap | Native AppStore booking/live-call transitions lack actual execution evidence; server mocked tests and native build do not close it. |
| RVA-11-006 | Retain targeted test suggestion | Several fail-closed malformed/status/durability branches remain untested; no observed branch failure. This audit does not elevate test quantity into a defect. |
| RVA-10-001 | New candidate; root validation pending | Native status/start-call success/error mutations ignore current connection and replacement-workspace identity. Recorded in track10 to avoid duplicate counting. |

Post-collection response memory cap limits, shared by voice and Linux Gemini, are **RVA-10-003**. Provider clinical speech accuracy and hardware audio playback remain unverified.

## Checklist dispositions

| ID | Disposition | Evidence and limit |
|---|---|---|
| H03 | Pass for mocked transport/DTO contract; actual decoding/fidelity Unverified | VoiceTranscription/VoiceTransport; Stage1 r1-12, official API reference. |
| H04 | Pass for keys/fixed destinations/no automatic replay | VoiceRoutes authenticated group; request endpoints fixed; redirects refused. Native publication caveat RVA-10-001. |
| I01 | Unverified native execution; source-reviewed simulation behavior | AppStore+Bookings and BookingEngine source; build succeeds, no native UI/state runtime evidence. |
| I02 | Pass current reviewed consent/gates; future frozen-payload hardening suggestion | LiveBookingEditor:55-84; VoiceCalls:32-66,116-128. |
| I03 | Pass for server mocked durability/replay/concurrency; native state execution Unverified | VoiceCalls, VoiceProviderTests; r1-12. Persistent volume requirement remains operational WIP. |
| I04 | Defect candidate for native stale publication; outcome separation Pass | RVA-10-001; server never confirms appointment; current status-view guidance is explicit. |
| J02 | Pass transport original-byte preservation; hardware playback Unverified | Multipart exact bytes/MIME/filename test; native codec/hardware playback belongs track05. |

## Evidence requests

Root's ER-10-1 controlled native provider response harness should cover status/start-call stale completion without any real call. No additional live provider or clinic request is authorized/needed. Preserve the existing no-redial mock suite as evidence.
