# Track 10 — Gemini and provider configuration

Snapshot: `fable-audit-20260912-114322 @ cfe0997+wip` (frozen worktree, not the active accounts implementation).

Reviewer: Codex continuation, explicitly authorized after the user reported Claude limits exhausted. This report is new Codex source review; it does not claim Fable execution or repeat the evidence runner's tests. Source files were read only. No builds, UI, ports, provider calls, credentials, database or Git operations were performed by this reviewer.

Evidence reused: `reports/17-evidence-runner.md`, `evidence/runner1-summary.json`, `evidence/commands.jsonl`. Stage 1 reports 31 server tests passed with the dedicated PostgreSQL test skipped; real local HTTP smoke, provider-route negative tests, native HTTP round trip, optimization harness and builds passed. Where raw log files are absent from the delivered audit directory, the runner report is the available record; these are runner-reported results, not this reviewer's new executions.

## Conclusion

Provider configuration, fixed endpoints and structured-response validation are coherent. A new native client candidate, **RVA-10-001 (P2)**, survives source review: delayed provider results ignore the connection/workspace boundary that sync and discovery already protect. Independent reproduction was requested. **RVA-10-002** is a semantic/adversarial evidence gap; **RVA-10-003** is bounded-collection hardening, not a measured outage.

## Inventory

Reviewed `server/Sources/RevaServer/Providers/GeminiModels.swift`, `GeminiService.swift`, `GeminiTransport.swift`, `ProviderConfiguration.swift`, `ProviderRoutes.swift`, `server/Tests/RevaServerTests/GeminiProviderTests.swift`, native `Core/ProviderClient.swift`, `Core/ProviderContracts.swift`, browser `core/api.ts`. Followed publishing interfaces into native `State/AppStore+AI.swift`, `AppStore+Providers.swift`, `AppStore+LiveCalls.swift`, `AppStore+Transcription.swift`, `AppStore.swift`, and `Features/Shared/SettingsView.swift`. Voice transport cross-reference remains track11.

## Effective provider/API verification

Checked public official documentation on 2026-09-12; no authenticated API calls occurred. The prior supervisor addendum's model-availability uncertainty can now be narrowed: the [Google model catalog](https://ai.google.dev/gemini-api/docs/models) lists both `gemini-3.8-flash` and `gemini-3.5-flash-lite`. The [generateContent reference](https://ai.google.dev/api/generate-content) documents the fixed `/v1beta/models/{model}:generateContent` operation, system instructions, and generation configuration. The [structured-output guide](https://ai.google.dev/gemini-api/docs/structured-output) documents schema-shaped responses. These facts establish documented API/model compatibility, **not this account's credential access, quota, latency, or clinical output quality**.

`ProviderConfiguration.swift:41` carries the captured WIP default `gemini-3.8-flash`; its allowed override syntax prevents endpoint path injection. Discovery reports configuration presence, never successful provider access. Public demo identity disables all paid calls even when keys are injected. Whisper is fixed to `whisper-1`, booking requires key/agent/number, and dialing additionally requires explicit enablement.

## Boundary review

- Summary request: safe ID; title240/text120000 UTF-8 bytes. Preparation: 1–100 unique source IDs, positive versions, bounded visit fields/questions and 500000 aggregate source+summary bytes (`GeminiModels.swift:16-81`). Native client preflights those budgets without truncating evidence (`ProviderClient.swift:68-146`). Browser sends bounded JSON and relies on server per-field limits.
- Server serializes source JSON under a user message, separate from fixed system instructions; tools and provider keys are absent from prompt payload. It validates one STOP candidate, non-thought text, outer/inner byte limits, exact keys, field lengths and allowed unique candidate IDs (`GeminiService.swift:70-75,99-114,146-158`). Blocked/truncated/invalid output fails with safe service-unavailable text; local state persistence belongs to callers.
- Model prose remains generated prose. The client builds source quotations using saved records; the generated overview is separately labeled for review (`AppStore+AI.swift:61-82`). A valid ID list cannot establish that every assertion in an overview is entailed by its source. This is documented as evidence gap RVA-10-002, not a proven hallucination.
- Apple Gemini response collection stops at1 MiB; Linux currently collects before checking. Voice is also post-collection. See RVA-10-003. Native ProviderClient uses buffered URLSession data rather than the browser's streamed boundedBytes, so this audit does not claim uniform client memory caps.
- Native field/signature checks reject changed source versions and preserve questions/notes, but do not reject a changed connection. `SettingsView` does not disable token/URL edits or sync while a provider request is pending. `AppStore.connectionDidChange` updates a generation that only discovery/sync consume. RVA-10-001 covers summaries/briefs and the same call-status mutation root cause. It must not be duplicated as a server owner-auth failure.
- Browser `api.ts:149-170` sends bearer credentials without cookies, follows no redirects, uses timeouts and boundedBytes, and masks remote failure body content. Browser publication races are owned by track06/08.

## Checklist dispositions

| ID | Disposition | Evidence and limitation |
|---|---|---|
| D05 | Pass for labeled structural adapter behavior; Unverified medical fidelity | Server validated summary DTO and native labeled saves; r1-12 mocks. RVA-10-002 covers semantic claims. Intake timing belongs track07/05. |
| E03 | Pass for selected-ID/quote-construction boundary; Unverified generated assertions | GeminiService:70-75, AppStore+AI:61-72; selected unknown/duplicate IDs mocked rejection. No live model clinical entailment proof. |
| H01 | Pass for documented model names/config consistency; live access Unverified | Official catalog/API checked2026-09-12 and ProviderConfiguration:22-58. |
| H02 | Defect candidate in native result publication; server malformed-output paths Pass | RVA-10-001; r1-12/r1-15 validate server mock/gate behavior. |
| H04 | Pass for server-only keys/fixed endpoint/no redirects; native identity publication candidate | GeminiService/Transport, api.ts; RVA-10-001 does not claim leaked provider keys. |
| H05 | Unverified for adversarial semantic behavior; structural separation Pass | RVA-10-002; request tests assert no tools and no key in body, but supply mocked generated text. |

## Evidence requests

**ER-10-1:** Use a controlled ProviderClient double, production native AppStore and AI/call methods, synthetic records and temp repository. Suspend summary, change connectionToken (also switch away/back case), then return nonempty old summary: assert the current snapshot must remain unchanged. Analogous status test replaces the workspace with one retaining the booking ID before returning old transcript. No network/real clinic calls. Request was sent to coordinator; findings remain candidate until adjudicated.

Live-provider clinical/adversarial testing and Linux streaming memory measurement remain explicitly unverified; they are not necessary to complete this read-only audit.
