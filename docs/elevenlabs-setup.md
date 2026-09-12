# ElevenLabs setup

September 12, 2026. The **Reva Scheduling Assistant** agent was created in the connected ElevenLabs account. Its key and `ELEVENLABS_AGENT_ID` are saved only in ignored local configuration. Local secrets are not deployed by a Git push.

## Configured sections

| Section | Saved configuration |
| --- | --- |
| Agent | [Block-structured prompt and first message](elevenlabs-agent-prompt.md); AI disclosure, clinic verification, availability inquiry and patient review |
| Request variables | All eight fields sent by `VoiceCalls.swift`; missing required defaults are `[NOT_PROVIDED]`, optional preferences are empty |
| Language and voice | English; Eric — Smooth, Trustworthy; Eleven Flash v2 |
| LLM | `qwen36-35b-a3b`, temperature 0.4, 512 output tokens; `gemini-3.8-flash` fallback after a five-second cascade timeout |
| Tools | End call, voicemail detection with no message, skip turn for holds, and keypad tones for announced scheduling menu options |
| Guardrails | Topic focus and prompt-injection protection enabled |
| Security | Private agent authentication enabled; prompt, model, first-message and external-tool overrides disabled |
| Call limits | 600 seconds per conversation; two concurrent conversations; 20 conversations per day; bursting disabled |
| Privacy | Audio saving disabled; transcript/PII and audio deletion scheduled after seven days; user memory disabled |
| Analysis | Three evaluation criteria: disclosure/verification, availability-only authority, and accurate constraints/no invention |
| Data collection | Inquiry outcome, candidate options and patient follow-up; no automatic booking confirmation |
| Tests | Seven saved and attached synthetic response/tool tests; all seven passed against the final saved version. See [results and scope](elevenlabs-agent-tests.md). |

The API accepted these settings and the agent dashboard displayed the prompt, private access, Qwen model and Eric voice. English Flash v2.5 was rejected by the provider; Flash v2 was accepted. The provider normalized a zero thinking budget to `null` and rejected an explicit reasoning-effort setting for this Qwen model, despite exposing that control in its UI/catalog. Reasoning therefore remains the provider default; **thinking off is not verified**.

Seven-day retention preserves the provider transcript for Reva's polling and manual review. It does not delete copies that a user has already saved in Reva. Audio saving being disabled does not mean no audio processing occurs. These prototype settings do not establish compliance certification.

The silence timeout is 120 seconds; long silent holds can end before the overall ten-minute limit. Real hold audio, speech recognition and keypad delivery still require a phone test. Synthetic response tests do not verify the guardrail service's runtime behavior, duration enforcement or scheduled deletion.

## Remaining phone connection

- [x] Sign in to the intended Twilio account and verify the supplied primary API key. Both number-inventory requests returned HTTP 200. The account SID and supplied key pairs are saved only in ignored `secrets/twilio.env`; the alternate key was saved but not tested.
- [ ] Complete the Twilio account upgrade. The current 30-day trial blocks `<Stream>`, which prevents the ElevenLabs voice integration. The console upgrade form requires account/tax details, a balance selection and payment. No upgrade or purchase was submitted.
- [ ] Select a purchased, voice-capable Twilio number or an outbound-only verified caller ID. Both API inventories currently contain zero entries. The console's trial caller number and verified trial recipient are separate from these inventories; neither proves an importable number exists. A verified caller ID cannot receive inbound calls.
- [ ] In ElevenLabs **Phone Numbers → Import number**, supply a label, the exact number, and the Twilio SID/token or supported API key credentials. API-key imports additionally require the account Auth Token for inbound webhook verification. Store Twilio secrets in that integration and disable SMS routing (`enable_sms=false`).
- [ ] Verify the imported resource supports outbound calls, then put its returned identifier in `ELEVENLABS_PHONE_NUMBER_ID` in backend secrets. Reva chooses the agent explicitly on each outbound request; inbound assignment is a separate choice.
- [ ] Configure private `REVA_TOKENS`, start/deploy the Swift backend with durable call-receipt storage, and route the browser API requests to it.
- [ ] Use a specifically reviewed test recipient and scheduling request before enabling `REVA_ENABLE_LIVE_CALLS`. Confirm speech, menu navigation, transcript polling, duplicate prevention and manual review through the app.

Live calling remains disabled. No real phone call was placed. Knowledge-base uploads, calendar writes, messaging integrations, public widgets and extra workflow agents are not required by the existing availability-inquiry implementation.

Twilio verification references: [current trial restrictions](https://www.twilio.com/docs/usage/trials), [Voice trial blocked verbs](https://www.twilio.com/docs/usage/trials/try-out-voice#blocked-verbs), and [ElevenLabs phone import schema](https://elevenlabs.io/docs/eleven-agents/api-reference/phone-numbers/create). Recheck the number inventories after upgrading; do not use the console trial number as `ELEVENLABS_PHONE_NUMBER_ID`.

Provider references: [agent creation](https://elevenlabs.io/docs/api-reference/agents/create), [dynamic variables](https://elevenlabs.io/docs/eleven-agents/customization/personalization/dynamic-variables), [retention](https://elevenlabs.io/docs/eleven-agents/customization/privacy/retention), and [Twilio integration](https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/native-integration).
