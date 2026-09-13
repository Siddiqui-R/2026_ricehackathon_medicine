# Vercel deployment

Reva's browser and Node.js API deploy together from the repository root. `/health` and `/v1/*` route to `api/reva.mjs`; React uses the same origin. The Swift server remains available for local development. The unfinished calling/booking demo has been removed.

## Build and storage

| Setting        | Value                                                            |
| -------------- | ---------------------------------------------------------------- |
| Project        | Reva / revamed                                                   |
| Production     | https://revamed.health                                           |
| Root Directory | Repository root                                                  |
| Node.js        | 24.x                                                             |
| Install        | `npm ci --include=dev && npm ci --include=dev --prefix apps/web` |
| Build          | `npm run build --prefix apps/web`                                |
| Static output  | `apps/web/dist`                                                  |
| API            | `api/reva.mjs`, maximum duration 120 seconds                     |
| Database       | TLS-verified Tiger PostgreSQL                                    |

Keep the repository root: asset preparation reads native fictional assets and the API bundles the existing SQL migrations. `vercel.json` owns these settings. Push `main` to deploy; environment changes apply to new deployments.

The API reuses the Swift snapshot, attachment, account and session tables and migration lock. Two additive tables store shared throttles and temporary upload chunks. It never stores patient data in Vercel's temporary filesystem. Passwords use bcrypt; sessions store only hashed opaque tokens. Accounts have separate data; state writes require the expected revision and return 409 on conflicts.

The animated `HomeLanding` and product tour is the public homepage at `/`. `/demo` continues to open the fictional workspace. The root configuration explicitly serves the application entry page for `/demo`, `/login`, `/signup`, and `/app`. The browser client determines the screen and session requirements; a rewrite alone does not implement accounts. Workspace navigation uses `#/records`-style hash routes, so no catch-all rewrite is needed. Keep these rules in the root `vercel.json`; a second `apps/web/vercel.json` selects a different configuration if the project root is changed and must not be maintained. Missing `/v1` or OCR files must not be rewritten to the app's HTML. The configuration applies the same CSP, nosniff and referrer policy as the tested local static host. It permits the local PDF/OCR workers and WebAssembly without allowing an external script CDN.

The experimental animated landing at `/test` and former minimal homepage at `/basic` are local archives, loaded only by the Vite development server when the ignored `apps/web/src/test/` and `apps/web/src/basic/` files are present. Both archives are optional in a clean checkout and excluded from production bundles. Do not add either route to the Vercel rewrites or the production wrapper's route allowlist; production requests to both paths return 404.

## Environment variables

Store secrets in **Vercel → revamed → Environment Variables → Production → Secret**. Never prefix secrets with `VITE_`. Local `.env`, `secrets/` and generated test artifacts are Git-ignored. This deployment uses Production values; configure Preview separately before expecting authenticated previews to work.

| Variable                         | Use                                                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `DATABASE_URL`                   | Required Tiger connection string with database password; certificate verification is enforced.              |
| `REVA_STORAGE=postgres`          | Documents storage selection; this API supports PostgreSQL only.                                             |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Document summaries, transcript summaries and visit preparation.                                             |
| `ELEVENLABS_API_KEY`             | Scribe v2 transcription; key needs Speech to Text access.                                                   |
| `REVA_SIGNUP`                    | Optional `closed` disables registrations; open by default.                                                  |
| `REVA_SESSION_DAYS`              | Optional lifetime, default 30, bounded 1–365.                                                               |
| `REVA_ALLOWED_ORIGINS`           | Optional comma-separated exact origins; defaults to production domains and allows the deployment URL.       |
| `REVA_TOKENS`                    | Optional private token-to-owner JSON mapping for native/manual integrations. Accounts need no shared token. |

Existing ElevenLabs agent, Twilio and local Swift listener settings were also stored in Vercel as requested. They are inactive compatibility settings: this app has no telephone/booking routes. `OPENAI_TRANSCRIPTION_MODEL` is unused here; no OpenAI key is required. Vercel manages the port; `REVA_HOST`, `REVA_PORT` and `REVA_DATA_DIRECTORY` do not control functions. `REVA_ACCOUNTS` is Swift-only; Vercel account routes are always enabled.

## Transfer and provider limits

The Vercel browser build uploads originals/audio in 3 MiB chunks and downloads originals using verified byte ranges. Maximum original size is 16 MiB; account originals are limited to 128 files / 64 MiB. Incomplete chunks expire after one hour with a separate 32 MiB / 8-upload quota. Finalization preserves the attachment ID. Snapshots are limited to 4 MiB. Clients without chunk support must keep direct uploads/downloads below 4 MiB. Local Swift connections keep their existing protocol.

Provider calls require authentication and share limits of 30 per owner per hour and 200 total per day. Failures preserve saved originals. Gemini output is validated against a strict schema and supplied source IDs. Scribe supplies recording-relative times and neutral speaker labels. Users review transcript accuracy and confirm everyone's consent before recording.

The adapters omit `candidateCount` and sampling overrides such as `temperature`: Google's current Gemini 3.8 migration instructions require their removal. An upstream 400 is a request/configuration error, not evidence of exhausted credits. The API reports permanent provider request/output failures as 422, key/model/setup failures as 424, quota limits as 429, and temporary network/provider outages as 503; it never returns raw upstream messages. Check the configured model and API permissions when an operation needs configuration changes, and only retry transient failures with a bounded backoff. [Gemini migration instructions](https://ai.google.dev/gemini-api/docs/generate-content/latest-model), [API errors](https://ai.google.dev/gemini-api/docs/generate-content/api-errors), [retry guidance](https://ai.google.dev/gemini-api/docs/troubleshooting).

## Verification checklist

- [x] Browser suite: 224 tests, including chunked transfers and changed-original rejection.
- [x] Production-mode TypeScript/Vite build.
- [x] Real Tiger HTTP integration: signup/login, account isolation, session revocation, password changes, deletion, snapshot conflicts, originals and staged transfers. Fictional accounts deleted afterward.
- [x] Live ElevenLabs Scribe with locally synthesized fictional speech.
- [x] Live Gemini summaries and visit preparation using `gemini-3.5-flash-lite`. The previous `gemini-3.8-flash` returned provider overload (503); production was switched to the verified model.
- [x] Production deployment `2a08a8f` ready at `revamed.health`; live HTTP contract suite passed against the deployed backend.
- [x] Production Gemini summary/preparation and ElevenLabs transcription succeeded through authenticated API routes. A 5 MiB original round-tripped through chunks and byte ranges with exact byte equality; test accounts and originals were deleted.
- [x] Browser signup opened an empty personal workspace, automatically synced revision 1, reported both providers configured and saved a fictional symptom with a generated Gemini summary.
- [x] Browser appointment creation and connected visit preparation produced a brief with the saved source quotation, source link and suggested questions.
- [x] Browser password-confirmed account deletion returned to the landing page and removed the fictional workspace.
- [x] Formatting and repository structure checks passed. Exact-value scan found no configured credentials in tracked/new source files or built public assets.

Run `npm test` for contracts. Set `REVA_TEST_DB=true` and run `npm test` to additionally use ignored `.env` for isolated Tiger tests. Run `npm test --prefix apps/web` and `npm run build --prefix apps/web` for the browser. No test credentials or patient data are committed.

For deployed HTTP contracts, explicitly set `REVA_TEST_ORIGIN=https://revamed.health` and run `node --test backend/integration.test.mjs`. This creates fictional accounts on that server and deletes them after the test; it does not load local provider/database secrets or touch existing accounts. Provider checks above used separate short fictional fixtures.

References: [Vercel function limits](https://vercel.com/docs/functions/limitations), [environment variables](https://vercel.com/docs/environment-variables), [ElevenLabs transcription API](https://elevenlabs.io/docs/api-reference/speech-to-text/convert).
