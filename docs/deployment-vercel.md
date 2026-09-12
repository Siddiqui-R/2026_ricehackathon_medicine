# Vercel browser deployment

The repository root contains the native iPhone app, Swift server, and browser client. Vercel must build `apps/web` and publish its generated `dist`; deploying the repository as static files has no root `index.html` and can return 404 even when the deployment status says Ready.

## Versioned build settings

The repository-root `vercel.json` specifies:

| Setting | Value |
| --- | --- |
| Vercel project Root Directory | Repository root (`.` / leave the default root unchanged) |
| Framework | Vite |
| Install | `npm ci --include=dev --prefix apps/web` |
| Build | `npm run build --prefix apps/web` |
| Published output | `apps/web/dist` |
| Node.js | 24.x recommended in project settings; the app requires at least 22.12 |

Keep Root Directory at the repository root: asset preparation reads the sibling native fixture folder at `apps/ios/Reva/Resources`. The include-dev install is required for TypeScript/Vite and the bundled English OCR model. Source files, server files, environment files and node_modules are not in the published output.

The app uses hash routes such as `/#/records`, so no catch-all rewrite is needed. Missing `/v1` or OCR files must not be rewritten to the app's HTML. The configuration applies the same CSP, nosniff and referrer policy as the tested local static host. It permits the local PDF/OCR workers and WebAssembly without allowing an external script CDN.

## Trigger and verify

Push to the branch configured as Vercel Production (currently `main`). A deployment created before this configuration was added remains immutable; open the new deployment or the project's production domain once it is Ready. In Vercel's Build Logs, verify that `npm ci --include=dev --prefix apps/web` and `npm run build --prefix apps/web` actually run. Output must contain `index.html`, `assets/`, `demo/seed.json`, and `ocr/`.

If dashboard Root Directory was changed to a subfolder, restore repository root and redeploy. The root `vercel.json` overrides framework, install, build and output settings. An old root/output override or the wrong project/branch can otherwise produce a different deployment.

## Hosted capability boundary

This deploys the browser frontend and fictional public assets. Local record storage, manual uploads, OCR, symptom entries, Medical profile, local visit briefs and simulations run in the browser. New medical records stay in that browser unless the user explicitly connects and submits an operation.

Vercel static hosting does **not** run `scripts/serve.mjs`, Vite's development proxy, or the Swift Vapor server. Connected AI, sync, transcription and calls need a separately hosted authenticated Swift backend plus explicit same-origin `/v1` and `/health` routing. Adding API keys to Vercel's frontend build does not create that backend; provider keys belong only to the Swift server. No speculative backend destination is included in this fix.

## September 12 verification

GitHub recorded deployment `6411370200` for `dc25e87` as successful, despite the reported 404; there was no Vercel build configuration or root web entry point. The added configuration was checked with a clean dependency install and its exact production build command. The generated index, hashed bundles, original demo sources and local OCR runtime/model were present. Deployment verification after push is recorded in the work log.

Primary references: [Vercel 404 troubleshooting](https://vercel.com/kb/guide/how-to-debug-404-errors), [project configuration](https://vercel.com/docs/project-configuration/vercel-json), [monorepo source boundaries](https://vercel.com/docs/monorepos/monorepo-faq), and [Vite on Vercel](https://vercel.com/docs/frameworks/frontend/vite).
