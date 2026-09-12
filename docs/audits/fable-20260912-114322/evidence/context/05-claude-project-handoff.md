# Claude project handoff and specification reconciliation

September 12, 2026. User requested a review/summary of their other Claude work and an update to Reva's project specification while the independent audit runs.

## Sources and evidence boundary

- Read the Claude Desktop Code session **Reva architecture review**, local UI session `local_3c7583ff-a1c1-44ed-a2f1-a225a45f2e72`, using Computer. Requested a summary-only handoff; its existing `accounts-and-tiger` workflow remained running.
- Claude returned a handoff labeled “Reva handoff — accounts, landing, Tiger.” Its header time (~11:50) is its own stated reference point, not a reliable completion timestamp. This ledger records the September 12 capture and reconciles it against the changing checkout.
- Read [accounts-and-tiger.md](../task-specs/accounts-and-tiger.md), current source/configuration declarations, palette, Git history and existing verification documents. No credentials or real medical records were inspected; no application tests, live service calls or deployment were performed by this documentation task.
- Committed baseline at inspection: `475eee7` (audit packet), preceded by `cfe0997` (root Vercel configuration), `dc25e87` (sync/audio merge), `2640360` (browser), `678e742` (heart palette), and `77c03da` (native sync protection). Landing/accounts/Tiger/Gemini changes were uncommitted WIP. The source continued changing during inspection.

## Decisions adopted in the current spec

| Decision | Reconciliation |
| --- | --- |
| Heart red and ivory, light only | Confirmed by user feedback, native/browser source, and `design/palette.json`; original supplied swatches remain historical |
| Browser and desktop responsiveness | Delivered baseline, not a future-only phase of the original two-hour goal |
| Landing at `/`, demo at `/demo`, real login/signup and `/app` | New explicit user scope visible in the implementation chat; required, with integration still running |
| Password hashing, revocable account sessions and Tiger persistence | Supersedes deferral of account implementation; live credentials and deployment checks remain separate |
| Gemini default `gemini-3.8-flash` | Present in uncommitted ProviderConfiguration source; this task did not verify provider availability or call it |
| Whisper for current timestamped transcription | Matches the implemented adapter; alternative speech models are future proposals |
| Broad Fable workflow | New user request supersedes the earlier limit on exhaustive review; audit workers are read-only |
| Separate code ownership and comments describing logical blocks | Remains active; not a claim of NASA certification |

The handoff also reports service-side ElevenLabs preferences: Qwen3.6-35B-A3B, thinking off, temperature about 0.4, a ten-minute call cap and a Gemini fallback, plus a later Gemini transcription alternative. These are **reported configuration proposals/decisions**, not settings independently verified in the ElevenLabs account or enforced by the repository. The handoff says a full agent prompt was offered but not yet written. The current spec therefore records the configurable ElevenLabs boundary and preserves Whisper rather than claiming these external model choices are deployed.

## Work status and verification

| Area | Evidence available at handoff | What remains |
| --- | --- | --- |
| Prior native/browser MVP | Git checkpoints and existing `docs/verification/` evidence; previous review rounds recorded under `docs/reviews/` | Historical results remain scoped to their commits |
| Early landing changes | Claude reports typecheck, 77 Vitest tests, seven Node wrapper tests and formatting passed before the account workflow | These do not verify later account code; browser previews pending in the handoff |
| Gemini default | Source/config/docs/test expectation edits present; Claude reports parse checking only | Swift tests and relevant native compatibility check after the change |
| Server accounts | Models, account storage, auth routes and migration 002 present in changing source | Completed integration, tests, owner/expiry/revocation/deletion behavior |
| Browser accounts | Auth/session/account modules and personal-store mode present; root observed real `/app`, `/login`, `/signup` mounting after an earlier inspection still showed placeholders | Fresh end-to-end, responsive/accessibility and conflict/reload checks |
| Tiger tooling | Provisioning script, Dockerfile and setup guide present or newly written | Fake transport results are distinct from a real API response, image build and TLS/migration smoke check |
| Hosted web/API | Root Vercel build fix committed; new nested Vercel routes and API-origin work in progress | Reconcile configuration root, deep-link rewrites, CSP and exact-origin CORS; verify deployed behavior |
| Live integrations | No live Tiger, Docker deployment, provider/clinic calls established by this handoff | User-owned setup plus explicitly recorded synthetic smoke evidence |

The implementation workflow reported run `wf_9f792746-fb6`, task `waq60gg6v`: three implementation tracks (server, web, deploy), then integration, four review lenses, adversarial verification and fixes. These are workflow stages, not completed verification claims.

Corrections to stale handoff statements: the native heart palette has an identifiable committed checkpoint (`678e742`); the current build history already records the browser and newer palette; an older profile/symptom verification sheet intentionally preserves the former palette. An instruction to rewrite those historical observations would erase useful evidence. The other session's suggestion to use Vercel Root Directory `apps/web` conflicts with the committed repository-root build and assets arrangement, so it remains an integration issue rather than an adopted deployment fact.

## Independent audit dispatch

Separate Claude session: **Reva intensive code-review workflow**, UI ID `local_7062b2e7-3e34-4787-9b7e-1133166cacd0`. Observed Fable 5.1 / Ultracode in the session UI. Actual workflow **reva-fable-audit-w1**, run `wf_74d707c0-9d8`, launched the evidence runner and six Wave A reviewers; the panel lists later waves, validation and follow-up. The full plan has 16 source-review domains, one runner, two validators and the supervisor.

The [audit packet](../audits/fable-20260912-114322/START-HERE.md) contains 67 checks and a frozen `cfe0997` plus captured-WIP snapshot with 267 verified hashes. It predates most new account implementation. [workflow-status.json](../audits/fable-20260912-114322/workflow-status.json) records live worker IDs/status. A launched workflow is not a finished code review; findings, delta coverage and adjudication remain pending.

## Documentation changes and ownership

- Replaced [reva-stack-spec.md](../reva-stack-spec.md) with current product scope, implemented stack, precise palette, account/Tiger contract, route/API/configuration maps, status gates and a full-stack diagram.
- Preserved the original cloud-oriented proposal as [reva-stack-spec-planning.md](../reva-stack-spec-planning.md), including its historical research without newly endorsing availability/pricing claims.
- Added supersession notes to the old MVP goal, initial completion criteria and implementation/provider contracts. Added a dated entry to the build history.
- Left README, architecture.md, Tiger setup, configuration examples and all application code to the implementation workflow's assigned owners. They must reconcile those files at integration; the current spec explicitly marks any older conflicting claims.
- Kept the frozen audit source unchanged. Documentation checkpointing does not signify that the uncommitted application work is complete.
