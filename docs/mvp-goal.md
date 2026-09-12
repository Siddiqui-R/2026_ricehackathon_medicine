# Reva — revised two-hour MVP goal

> Historical deadline milestone. Later user requests added the heart-red light-only palette, Medical profile and symptom entries, a responsive browser, a broad Fable audit, and real browser accounts/Tiger setup. Use [the current project specification](reva-stack-spec.md) and [account contract](task-specs/accounts-and-tiger.md) for active scope/status; the browser/review/palette deferrals below no longer control those later tasks. Calling and booking simulation have since been removed; appointment recording/transcription/AI summaries are now supported. The [current scope](reva-stack-spec.md) and [latest verification](verification/appointment-recording.md) supersede those historical requirements.

User scope revision received September12,2026 at07:28CDT /12:28UTC. Target delivery by09:28CDT /14:28UTC. This supersedes the earlier exhaustive completion loop and task list where they conflict. The active goal tool's original text cannot be edited through its available status-only API; this document and the user's latest instruction control remaining work.

## Deliver now

1. Keep the working native iPhone MVP: the six exact user palette values with no dark substitutions, Summary/Records/Visits, fictional dataset, local persistence, import/OCR/review, relevant cited briefs/PDF, booking demo and recording/sample-memory flows.
2. Add real configurable server adapters and native entry points for MVP APIs: Gemini document summaries/pre-visit selection, OpenAI Whisper audio transcription, ElevenLabs outbound calling through a configured telephony number. Tiger/PostgreSQL preparation already exists. Keys/accounts/agent/number/database/signing remain manual; root .env stays exactly empty. Disabled integrations clearly report missing setup and never pretend success.
3. Make feature boundaries clear so three people can work independently. Separate record/preparation, visit/audio/booking, and backend/provider code; document owned directories, shared contracts, integration procedure and starter tasks.
4. Run the build, meaningful local/mock connector tests and a short key-path simulator check. Fix blockers only. Defer heavy repeated review, extensive edge-case polish and further design revisions to the user's manual feedback loop.
5. Keep focused commits and work history. Immediately before final commit/push, create the as-built stack visualization, update run/configuration/team docs, push to GitHub and verify remote HEAD.

## Explicitly deferred

Production hardening, real medical-data deployment, MyChart, custom encryption, web wrapping, live provider/account activation, physical-device signing/capture validation, exhaustive extra reviews, and nonblocking polish. No real call or paid API request is executed during implementation. Mock transport tests verify connector contracts; a credentialed smoke check is part of manual setup.

## Checkpoints

Existing working native/server checkpoint: d9ec87c. New work is limited to API readiness, module separation, essential validation and delivery.
