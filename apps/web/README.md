# Reva browser client

Reva's browser interface is a dedicated React/TypeScript application with a desktop sidebar, clinical cards, source history, visit preparation, and a Medical Profile. The iPhone interface remains native SwiftUI. The browser shares the Swift app's JSON and HTTP contracts; it does not compile SwiftUI for the web.

The first visit loads the same clearly fictional dataset and original documents used by the native demo. Browser changes persist in IndexedDB. The Swift server is optional for local use and required for explicit cross-device sync and configured providers. This is a local implementation and handoff, with no production deployment.

## Run locally

Use Node **22.12 or newer** and npm. From the repository root:

```sh
cd apps/web
npm ci
npm run assets
npm run dev
```

Open `http://127.0.0.1:5173`. `npm run assets` copies native fictional fixtures and installed English OCR assets into generated `public/demo` and `public/ocr` directories. The `dev`, `build`, `typecheck`, and `test` scripts run that step automatically; running it separately is useful after fixture changes. Generated assets, `node_modules`, and `dist` are not source files to edit or commit.

## Routes

| Path | What it shows |
| --- | --- |
| `/` | Public landing with **Sign up**, **Log in** and **View the demo**. With a live session the actions become **Open your workspace**, **View the demo** and **Log out**. |
| `/signup` | Creates an account (`POST /v1/auth/signup`), stores the returned session and opens `/app`. |
| `/login` | Logs an existing account in (`POST /v1/auth/login`). `/login?reason=session` shows a quiet "Your session ended" notice after a rejected session. |
| `/app` | The signed-in workspace. It keeps the workspace's `#/…` hash routes and redirects to `/login` when no live session is stored. |
| `/demo` | The fictional demo workspace with the public local token and manual push/pull. Older `/#/…` bookmarks are forwarded here. |

`scripts/serve.mjs` serves every one of these paths as the single page, and `vercel.json` rewrites them the same way. Hash routes inside `/app` and `/demo` are handled by the client.

After `npm ci`, these checks work from a clean checkout; each command that needs generated fixtures prepares them automatically. To check and serve a built application, from `apps/web`:

```sh
npm run typecheck
npm test
npm run format:check
npm run build
npm run serve
```

The built preview opens at `http://127.0.0.1:4173`. After pulling route or server changes, rebuild, stop the existing preview, and run `npm run serve` again. The preview process does not reload `scripts/serve.mjs`; an older process can return “File not found” for `/demo` even when the current source supports it. `PORT` and `HOST` configure that listener; its default is loopback. Development and built previews have different origins and therefore separate browser storage. Keep the same origin when checking persistence, or use explicit server sync to transfer a workspace.

## Deploy the browser on Vercel

Use the repository root as the Vercel project's Root Directory. The root `vercel.json` is the only deployment configuration: it installs and builds `apps/web`, then publishes `apps/web/dist`, with the entry-page rewrites and security headers. Do not set the project root to `apps/web` or add a nested deployment configuration; asset preparation needs the sibling native fixtures. The [Vercel deployment guide](../../docs/deployment-vercel.md) covers the 404 fix, build settings, source/OCR assets and the separate hosted-backend requirement. The local Node/Vite proxy is not a Vercel backend.

## Connect the existing Swift server

In another terminal, from the repository root:

```sh
python3 scripts/run_server.py --build
```

Both browser launchers proxy same-origin `/v1` and `/health` requests to `http://127.0.0.1:8080`. Set `REVA_API_ORIGIN` in the launcher's environment to use another **loopback HTTP origin**, for example:

```sh
REVA_API_ORIGIN=http://127.0.0.1:8081 npm run dev
```

The proxy accepts only the configured local destination; the browser has no arbitrary API URL field. In the demo workspace's **Settings & connections**, enter the server's workspace bearer token and choose **Check connection**. The public local demo token is `reva-local-demo-token`. The demo token, provider capabilities, and connected-AI toggle live only in memory and reset on reload. Apart from the account session described below, private credentials are not persisted to IndexedDB/localStorage or embedded in the bundle.

On Vercel, keep the project at the repository root and use its canonical `vercel.json`, which includes the build, output, security headers, and `/demo`, `/login`, `/signup`, and `/app` entry-page rewrites. To reach a hosted Swift server, configure explicit `/v1/:path*` and `/health` rewrites to that server's HTTPS origin, or configure `VITE_REVA_API_ORIGIN` with the CSP and CORS requirements below. The bounded loopback proxy is for local use only.

### `VITE_REVA_API_ORIGIN`

By default every request is same-origin (`/v1/…`, `/health`) and reaches the Swift server through the local proxy or a hosting rewrite. Setting `VITE_REVA_API_ORIGIN` at **build time** makes `src/core/api.ts` prefix every API path with that origin instead, for the workspace transport and the auth client alike. The value must be an absolute `https://` origin or a loopback `http://` origin (`http://127.0.0.1:8080`, `http://localhost:8080`, `http://[::1]:8080`) with no path, query, hash or credentials; anything else makes the app throw at startup rather than send a bearer token somewhere unintended. The server must then allow the site's origin for CORS, and the frontend host's Content-Security-Policy must explicitly permit that API origin in `connect-src`. The checked-in root CSP permits same-origin connections; setting this environment variable alone does not change it. Never write this or any other value into a checked-in `.env` file; pass it through the build environment.

## Accounts and sessions

Accounts are created and used through the Swift server's `/v1/auth` routes. The browser keeps one **bearer session token** per browser in `localStorage` under the key `reva.session.v1`, together with its expiry and the signed-in user's `id`, `email`, `name` and `createdAt`. The server issues sessions with a **30-day expiry**; an expired or malformed entry reads as absent and is removed. **Log out** revokes the session on the server (`POST /v1/auth/logout`) and then clears the key; **Log out everywhere** (`/v1/auth/logout-all`) and a successful password change end other sessions too. Every storage read and write is wrapped in `try/catch`, so blocked storage degrades to "not logged in" instead of a broken page. The token never appears in a URL.

Because the token lives in `localStorage`, cross-site scripting is the threat to keep in mind. The mitigations in this client are the Content-Security-Policy set by `scripts/serve.mjs` (scripts only from the same origin, no inline scripts, no remote connections beyond the same origin), the absence of inline scripts and `dangerouslySetInnerHTML` in the application, and the server's own limits: any HTTP 401 immediately clears the stored session, shows one notice and returns the workspace to `/login?reason=session`. Apply an equivalent CSP header on any other host.

Inside `/app` the store runs in **account mode**: the session token is the workspace token (the Settings token field is not shown), records live in a **per-user IndexedDB database** named `reva-account-<16 hex of SHA-256(user id)>-v1` (the demo keeps `reva-workspace-v1`), and saves are pushed to the server automatically about **1.5 seconds** after the last local commit. On first login the store compares both sides: an empty server receives an empty personal snapshot built around the account (never the fictional demo); a server with data and an empty browser downloads the snapshot and its originals; when both hold data and this browser's remembered in-sync revision (`localStorage` key `reva.sync.v1.<user id>`) does not match the server, the local copy is kept, automatic pushes pause, and Settings shows "The server copy differs; pull to review it." Originals uploaded earlier in the same session (same filename and size) are not re-uploaded. Manual **Push to server** and **Pull from server** remain available; **Restore fictional demo** is demo-only. **Settings** also offers **Change password** and a typed-confirmation **Delete account**, which removes the server copy, every session and this browser's private database.

Production provider keys and database settings belong to Vercel's server-only environment. The [Vercel backend guide](../../docs/deployment-vercel.md) covers accounts, Tiger storage, Gemini and ElevenLabs Scribe. For local Swift development, follow [server setup](../../server/README.md). Paid providers require an authenticated account or private workspace token. Checking configuration does not prove that a provider account works.

**Push to server** uploads originals and then performs a revision-checked snapshot write. **Pull from server** downloads originals before replacing the active browser snapshot after confirmation. A conflict preserves local state and requires an explicit pull before another push; there is no automatic merge. The demo has no background sync; account mode adds the debounced automatic push described under **Accounts and sessions**. Attachment uploads and server snapshot writes are separate operations, so a failed push may leave copied originals. Browser pull publishes downloaded originals and state in one local transaction.

## What works

| Area | Browser behavior |
| --- | --- |
| Dashboard and Records | Recent sources, search/filter, source detail, edit/delete, original preview/download, and page links from briefs. |
| Document intake | Text and PDF extraction using PDF.js; image and scanned-PDF OCR using local Tesseract.js and bundled English data. Review text before saving; original bytes remain unchanged. PDF/OCR code loads on demand. |
| Symptom entries | Required symptom and occurrence time; optional severity, duration, details, triggers, and what helped. Entries retain time-zone context and participate in Records, search, source versions, and visit preparation. |
| Medical Profile | Persistent allergies, medications, conditions, surgeries/implants, and care notes. This is quick-reference data; preparation currently reads Records, so profile edits do not rewrite sources or automatically add profile facts to a brief. |
| Visits and preparation | Visit editing, goals/questions, pinned sources, local evidence with exact quotations/page links, stale-report detection, reviewable questions/notes, and report-only print/save-to-PDF. Configured Gemini can provide summaries and preparation. |
| Visit memory | Consent-gated microphone capture or audio upload, playback, configured transcription, transcript correction, and linked memory records. New audio starts without a fabricated transcript. |

Local imports receive a reviewable excerpt. With connected AI enabled, saving a readable import or symptom entry also requests a configured summary after local saving; errors preserve the source. Transcription and appointment summaries use explicit connected actions. No provider account, paid request, or production deployment is established by installing the browser app.

## Appointment recording

Each appointment has **Record appointment → Transcribe → Summarize appointment**. Before recording or uploading audio, the user must confirm: “My doctor and everyone present agreed to recording.” The screen also says: “Get your doctor’s consent and permission from everyone present before recording.”

Audio and its metadata are saved together in the active account or demo database. Transcription and summarization failures preserve the audio and existing saved content. AI summaries use only the full timestamped transcript, show their model and generation time, and ask the user to check the result against the transcript and audio. Changing transcript content invalidates its AI summary; changing personal notes does not. A saved memory keeps the entire transcript as its source, with the AI summary as a separate attributed summary when available. Existing snapshots retain legacy booking history as inert compatibility data; the application has no calling or booking-simulation controls or endpoints.

## Limits to keep visible

- Documents and audio are limited to **16 MiB per original**; snapshot JSON is limited to **4 MiB**. Browser quota can impose a lower practical workspace limit, and save errors remain visible.
- Local extraction reads at most **24 PDF pages**, **120,000 UTF-8 bytes of text**, and **three minutes** per file. OCR runs sequentially with one worker and supports English. Images are capped at 40 megapixels before resizing for OCR. Stop reading cancels work; partial or failed extraction retains the original and records extraction warnings in the source notes. Exact OCR is not guaranteed, particularly for handwriting, obscured text, or unsupported image formats.
- Microphone capture requires browser support, a secure context such as localhost/HTTPS, and browser permission. It pauses when the page is hidden, releases tracks on cleanup, and is bounded to 30 minutes or 16 MiB. Audio upload/playback depends on codec support; WebM/Ogg originals retain their actual container type.
- Clearing site data removes this browser's copy. Removing records or restoring the fictional demo does not erase retained originals. This client has no custom password-derived encryption or offline service-worker installation.
- MyChart connection, native VisionKit camera scanning, local Whisper, and automatic appointment confirmation are not browser capabilities. Camera intake uses the browser's image chooser/capture support. Current transcription uses the configured server adapter.

See [core compatibility](src/core/COMPATIBILITY.md) for timestamp/Unicode differences, evidence signatures, concurrency, and sync guarantees.

## Source ownership and visual roles

| Source | Responsibility |
| --- | --- |
| `src/App.tsx`, `src/features/Dashboard.tsx`, `src/features/SettingsPage.tsx`, `src/features/AccountSettings.tsx` | Shell, navigation, summary dashboard, explicit connection controls, and account cards. |
| `src/landing` | Public landing, `/login` and `/signup` forms and their shared accessible form pieces. |
| `src/features/records`, `src/features/profile` | Source intake/review, symptoms, originals, and Medical Profile. |
| `src/features/visits` | Visit editing/preparation, consent-gated recording, transcripts, appointment summaries, and memories. |
| `src/core` | Native-compatible values, validation, pure rules, versioned mutation queue, IndexedDB, API transport, the auth client (`auth.ts`), stored session (`session.ts`) and account-mode store logic. |
| `src/components`, `src/styles` | Shared components, brand, responsive layout, and palette roles. |
| `scripts`, `vite.config.ts` | Generated local assets, build/development configuration, and bounded built-preview proxy. |

The current light theme follows [the approved palette](../../design/palette.json): canvas `#FBF7F5`, white surfaces/button text `#FFFFFF`, heart-red actions `#B84250`, deep-red labels `#8C2F3B`, soft fills `#FAE6E5`, and decorative outlines `#DBCBC9`. `src/styles/tokens.css` owns these roles; body text and interactive borders use separate readable neutral tokens. Earlier teal/Sky swatches remain historical provenance, not the active theme.

Use the [three-person workflow](../../docs/team-workflow.md) for owned files and worktrees, and the [coding standard](../../docs/coding-standard.md) for responsibility comments and verification. Native device features and browser platform adapters remain separate; coordinate every persisted-field or API change across both clients and the server.
