# Browser audit repair evidence — September 12, 2026

Scope: RVA-07-002, RVA-08-001, RVA-14-001, RVA-14-002, RVA-16-001, and RVA-16-002. Changes were made in the isolated `fix/audit-browser-20260912` worktree, starting at published commit `98261b8`. Main-checkout account/landing work was read for compatibility and left untouched by this agent. The VisitBrief omission notice also supports the evidence track's RVA-02-002 repair.

## Durable imports and concurrent brief editing

`node node_modules/vitest/vitest.mjs run src/core/__tests__/importPersistence.test.ts src/features/visits/briefNotesEdits.test.ts` passed **8 tests** from `apps/web`.

- Three stale-CAS import attempts through the real `RevaStore` and two real `IndexedDBRepository` instances over fake IndexedDB created **zero new attachment keys**. A refreshed store then published one new record and one byte-identical original. Previously retained originals survived both failed retries and record deletion.
- An injected snapshot `QuotaExceededError` after queuing the attachment write rolled back both stores. Retrying the same record/original succeeded with one key. A stale source-version edit also preserved the existing source and original.
- Notes/question tests covered generated questions after editor opening, notes queued ahead of saving a question, whole-save conflict rejection, converged edits, explicit clearing, and a visit deleted while its editor was open.

The browser was then operated through **Computer (`cua_repl`)** at isolated loopback origin `http://127.0.0.1:5193`. A temporary fixture rendered the actual `VisitBrief`, notes modal, `RevaProvider`, and `RevaStore`. Only persistence and provider transport were synthetic: `MemoryRepository`, fictional seed values, and a delayed preparation result released with a visible button in a separate control page through a fixture-only BroadcastChannel. No app-internal state was injected through browser evaluation, and no server/provider was contacted.

1. Started preparation with empty questions, opened the real notes modal while it displayed **Working…**, and changed only notes. Released the synthetic response while the modal remained open. The visible saved state gained `Synthetic generated question?` while the modal questions field remained empty. Saving preserved that question and saved the new notes in both the visit and displayed report.
2. Reopened the modal, edited both questions and notes, and used the fixture control to save newer notes concurrently. Submitting showed **“Your questions or notes changed while this editor was open…”**. The modal remained open with the unsaved input; saved questions and the newer saved notes remained unchanged.

The fixture files and all three temporary tabs were removed/closed. The preview was stopped, and the temporary viewport override was reset. No fixture is included in the production build.

## Navigation and selection

Computer inspection confirmed **`innerWidth: 768`** and the tablet spans' computed `display: none`. The actual accessibility tree retained the names **Overview**, **Health records**, **Appointments**, **Medical profile**, **Log a symptom**, and **Settings & connections**. Keyboard Enter activated each correct hash destination; **Log a symptom** opened the symptom dialog.

A fictional medication source passage was selected by a pointer drag and inspected visually. Its computed selection foreground was `rgb(255, 255, 255)` and background `rgb(140, 47, 59)` (approximately **8.124:1** sRGB contrast). Unselected body text remained `rgb(52, 43, 44)`. This was also visible in the Computer screenshot.

Attempts to apply 375/1440 overrides did not change this tab's observed 768-pixel viewport. Those widths are **not claimed as verified** here. OS high-contrast modes and other browser engines were not exercised.

## Clean checks and deployment boundary

The unchanged lockfile matched the frozen audit's installed dependencies; the coordinator supplied an isolated APFS clone of `node_modules`. Before each clean command, only this worktree's generated `public/demo` and `public/ocr` were removed.

- `npm --prefix apps/web test`: asset preparation ran automatically; **9 files / 85 tests passed**.
- `npm --prefix apps/web run typecheck`: asset preparation ran automatically; **passed**. An initial implicit-`this` error in the new failure-injection test was corrected in `30eaabb` before the final clean run.
- `python3 scripts/check_code_structure.py`: **passed**, 71 Swift and 53 browser source files.
- `npm --prefix apps/web run format:check`: **passed**. Integrated production build results are recorded with the final integration gate.

The root `vercel.json` retains repository-root install/build/output and security headers, and adds only the exact entry-page rewrites `/demo`, `/login`, `/signup`, and `/app`. The sibling native-fixture prerequisite is documented consistently. JSON shape and the exact rule scope were inspected; no catch-all can match missing `/v1` or `/ocr` paths. [Vercel's configuration reference](https://vercel.com/docs/project-configuration/vercel-json) was consulted. This is configuration verification, not a hosted Vercel or authentication test; a rewrite alone does not implement account behavior. No deployment was attempted.

## Reconcile the uncommitted main-checkout overlap

The root integrator should apply these focused changes without incorporating account/landing work into a repair commit:

- Preserve main's account-aware store, including `scheduleSync()` after successful local commits. Add the optional original argument to `saveRecord` and thread attachments into the existing `edit` transaction. This automatically uses the store's correct per-user repository; imports must not return to the global attachment singleton.
- Apply the named navigation attributes to the existing six rail actions. Main also has an account-only **Log out** rail button whose span is hidden at tablet width; give that existing button `aria-label="Log out"` and `title="Log out"` when reconciling the same defect.
- Once root rewrites are present, remove the main checkout's untracked `apps/web/vercel.json` duplicate. Replace the contradictory README paragraph beginning **“On Vercel set the project root to `apps/web`”** with repository-root guidance. Preserve all surrounding account documentation and the existing root build/output/security settings.
- Any future direct external `VITE_REVA_API_ORIGIN` requires both an explicit permitted `connect-src` origin and backend CORS. The current root CSP remains same-origin; configuring that environment variable alone does not change it. No speculative backend origin or blanket CSP relaxation is part of these repairs.
