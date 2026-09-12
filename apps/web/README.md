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

After `npm ci`, these checks work from a clean checkout; each command that needs generated fixtures prepares them automatically. To check and serve a built application, from `apps/web`:

```sh
npm run typecheck
npm test
npm run format:check
npm run build
npm run serve
```

The built preview opens at `http://127.0.0.1:4173`. `PORT` and `HOST` configure that listener; its default is loopback. Development and built previews have different origins and therefore separate browser storage. Keep the same origin when checking persistence, or use explicit server sync to transfer a workspace.

## Deploy the browser on Vercel

Use the repository root as the Vercel project's Root Directory. The root `vercel.json` installs and builds `apps/web`, then publishes `apps/web/dist`. The [Vercel deployment guide](../../docs/deployment-vercel.md) covers the 404 fix, build settings, source/OCR assets and the separate hosted-backend requirement. The local Node/Vite proxy is not a Vercel backend.

## Connect the existing Swift server

In another terminal, from the repository root:

```sh
python3 scripts/run_server.py --build
```

Both browser launchers proxy same-origin `/v1` and `/health` requests to `http://127.0.0.1:8080`. Set `REVA_API_ORIGIN` in the launcher's environment to use another **loopback HTTP origin**, for example:

```sh
REVA_API_ORIGIN=http://127.0.0.1:8081 npm run dev
```

The proxy accepts only the configured local destination; the browser has no arbitrary API URL field. In **Settings & connections**, enter the server's workspace bearer token and choose **Check connection**. The public local demo token is `reva-local-demo-token`. The app token, provider capabilities, and connected-AI toggle live only in memory and reset on reload. Private credentials are not persisted to IndexedDB/localStorage or embedded in the bundle.

Provider keys, models, agent/phone IDs, database settings, and private token mappings belong to the Swift server environment. Follow [server setup](../../server/README.md) and its [configuration example](../../server/.env.example). Paid providers require a private token mapping; live calls also require server enablement and final reviewed authorization in the UI. Checking configuration does not prove that a provider account works.

**Push to server** uploads originals and then performs a revision-checked snapshot write. **Pull from server** downloads originals before replacing the active browser snapshot after confirmation. A conflict preserves local state and requires an explicit pull before another push; there is no automatic merge or background sync. Attachment uploads and server snapshot writes are separate operations, so a failed push may leave copied originals. Browser pull publishes downloaded originals and state in one local transaction.

## What works

| Area | Browser behavior |
| --- | --- |
| Dashboard and Records | Recent sources, review count, search/filter, source detail, edit/delete, original preview/download, and page links from briefs. |
| Document intake | Text and PDF extraction using PDF.js; image and scanned-PDF OCR using local Tesseract.js and bundled English data. Review text before saving; original bytes remain unchanged. PDF/OCR code loads on demand. |
| Symptom entries | Required symptom and occurrence time; optional severity, duration, details, triggers, and what helped. Entries retain time-zone context and participate in Records, search, source versions, and visit preparation. |
| Medical Profile | Persistent allergies, medications, conditions, surgeries/implants, and care notes. This is quick-reference data; preparation currently reads Records, so profile edits do not rewrite sources or automatically add profile facts to a brief. |
| Visits and preparation | Visit editing, goals/questions, pinned sources, local evidence with exact quotations/page links, stale-report detection, reviewable questions/notes, and report-only print/save-to-PDF. Configured Gemini can provide summaries and preparation. |
| Booking | Clearly labeled local simulation, plus configurable ElevenLabs calling through the Swift server. Durable request identity and manual status refresh handle uncertain outcomes. Call completion does not confirm an appointment; the user reviews the outcome. |
| Visit memory | Consent-gated microphone capture or audio upload, playback, configured transcription, transcript correction, and linked memory records. New audio starts without a fabricated transcript. |

Local imports receive a reviewable excerpt. With connected AI enabled, saving a readable import or symptom entry also requests a configured summary after local saving; errors preserve the source. Transcription and calling use explicit connected actions. No provider account, paid request, real clinic call, or production deployment is established by installing the browser app.

## Limits to keep visible

- Documents and audio are limited to **16 MiB per original**; snapshot JSON is limited to **4 MiB**. Browser quota can impose a lower practical workspace limit, and save errors remain visible.
- Local extraction reads at most **24 PDF pages**, **120,000 UTF-8 bytes of text**, and **three minutes** per file. OCR runs sequentially with one worker and supports English. Images are capped at 40 megapixels before resizing for OCR. Stop reading cancels work; partial or failed extraction retains the original and remains marked for review. Exact OCR is not guaranteed, particularly for handwriting, obscured text, or unsupported image formats.
- Microphone capture requires browser support, a secure context such as localhost/HTTPS, and browser permission. It pauses when the page is hidden, releases tracks on cleanup, and is bounded to 30 minutes or 16 MiB. Audio upload/playback depends on codec support; WebM/Ogg originals retain their actual container type.
- Clearing site data removes this browser's copy. Removing records or restoring the fictional demo does not erase retained originals. This client has no custom password-derived encryption or offline service-worker installation.
- MyChart connection, native VisionKit camera scanning, local Whisper, and automatic appointment confirmation are not browser capabilities. Camera intake uses the browser's image chooser/capture support. Current transcription uses the configured server adapter.

See [core compatibility](src/core/COMPATIBILITY.md) for timestamp/Unicode differences, evidence signatures, concurrency, and sync guarantees.

## Source ownership and visual roles

| Source | Responsibility |
| --- | --- |
| `src/App.tsx`, `src/features/Dashboard.tsx`, `src/features/SettingsPage.tsx` | Shell, navigation, summary dashboard, and explicit connection controls. |
| `src/features/records`, `src/features/profile` | Source intake/review, symptoms, originals, and Medical Profile. |
| `src/features/visits` | Visit editing/preparation, booking, recording lifecycle, transcripts, and memories. |
| `src/core` | Native-compatible values, validation, pure rules, versioned mutation queue, IndexedDB, and same-origin API transport. |
| `src/components`, `src/styles` | Shared components, brand, responsive layout, and palette roles. |
| `scripts`, `vite.config.ts` | Generated local assets, build/development configuration, and bounded built-preview proxy. |

The current light theme follows [the approved palette](../../design/palette.json): canvas `#FBF7F5`, white surfaces/button text `#FFFFFF`, heart-red actions `#B84250`, deep-red labels `#8C2F3B`, soft fills `#FAE6E5`, and decorative outlines `#DBCBC9`. `src/styles/tokens.css` owns these roles; body text and interactive borders use separate readable neutral tokens. Earlier teal/Sky swatches remain historical provenance, not the active theme.

Use the [three-person workflow](../../docs/team-workflow.md) for owned files and worktrees, and the [coding standard](../../docs/coding-standard.md) for responsibility comments and verification. Native device features and browser platform adapters remain separate; coordinate every persisted-field or API change across both clients and the server.
