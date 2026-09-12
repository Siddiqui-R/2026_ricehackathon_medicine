# Preserved repository integration — September 12, 2026

The user requested integration of concurrent repository work, deliberate conflict resolution, and preservation of both the latest local behavior and teammate contributions.

## Recovery and branch history

- Saved all 100 changed/new main files in `e04b9bd`; `backup/local-work-20260912-203412` preserves that checkpoint.
- Backed up 136 changed/new files across five dirty worktrees at `/tmp/reva-integration-backup-20260912T203412Z`, including staged/unstaged patches, original file archives, and SHA-256 manifests. Existing review worktrees and their edits remain intact.
- Merged remote `afed8e0` in `f3986e6`, retaining the ElevenLabs agent setup and synthetic test documentation.
- Merged original browser, native, and evidence branch histories in `4270aff`, `f292f0e`, and `69f27a2`. Browser/native commits were patch-equivalent to already integrated commits. Evidence commit `6cc7d64` was also present through `e54cbdd`, whose browser import additionally commits originals and metadata atomically. Conflict resolution retained that stronger implementation.
- Confirmed `origin/main`, all four `fix/audit-*` branches, `review/final`, and `review/implementation` are ancestors of the integrated history. A final fetch found no additional remote commits.
- Reviewed old dirty worktrees by content: heart palette and outlined components, editor/source-version rules, PDF page navigation, landing routes/provider defaults, and demo-kind normalization are already integrated or superseded by the later account implementation. Historical files were not copied over newer feature modules.

## Features retained

The approved native glass tab lens, rooted stretch/snap behavior and smaller held state are unchanged by these merges. Both clients retain `America/Chicago` defaults with CST/CDT transitions and explicit historical zones. Account sign-up/login/session settings and auto-sync, the landing page, three isolated demo profiles, profile/symptom editing, streamlined record status, OCR/camera originals, exact page/version evidence, cited briefs/PDFs, recording recovery/transcription/memory, provider cancellation guards, and durable booking receipts remain present.

The application tree after branch merges differs from checkpoint `e04b9bd` only in the six incoming ElevenLabs documentation files. Subsequent code changes are limited to the integration defects below.

## Integration defects repaired

1. Browser source/audio previews and capture had still used the global demo repository in account mode. Store-bound original reads now use the active repository. Recording metadata and bytes commit together, so failures and stale writes cannot leave partial recordings or overwrite saved originals.
2. Full-line SQL comments in the new account migration contained semicolons. The migration runner now removes those comments before splitting bundled statements; tests inspect the real migration resources.
3. Local account registry `accounts.json` collided with the valid static owner ID `accounts`. The registry now uses `.accounts.json`. Shape-checked legacy migration preserves owner documents and fails closed on mixed/corrupt data.
4. Password replacement and other-session revocation previously used separate operations. They now commit atomically, while session issuance rechecks the verified hash under the same actor/database user lock. Tests cover concurrent old-password login and competing password updates.

Current contracts are recorded in [architecture](../architecture.md), [accounts and Tiger](../task-specs/accounts-and-tiger.md), and the [server guide](../../server/README.md).

## Verification

| Check | Result |
| --- | --- |
| Browser unit/regression suite | 197 passed across 17 files, including five new account attachment/atomic recording tests |
| Browser preview-server HTTP checks | 7 passed |
| Browser typecheck, production build, whole-source Prettier check | Passed |
| Core Swift package | 57 passed; one opt-in local-server test initially skipped, then passed separately below |
| Native state/audio harness | Passed, including 72 stale provider outcomes, cancellation, edit conflicts and recording recovery |
| Server suite | 59 passed; two credential-gated PostgreSQL tests skipped; ten new persistence/password regressions passed |
| Server build | Passed with cached dependencies |
| Real local native client ↔ Vapor API | Passed: authentication, owner isolation, full snapshot domains, stale conflicts, nine originals, Unicode metadata and deletion tombstones |
| Tiger provisioning mocks | 24 passed |
| iOS Simulator build | Passed from the merged source using an isolated derived-data directory |
| Real PDFKit/Vision synthetic checks | Passed: raster/embedded text, distinct numeric lines, page mapping and ten-page OCR priority/cap |
| Swift formatting, source contracts and diff whitespace | Passed; 73 Swift and 75 browser files checked for contracts/sections |
| Generated Xcode project | Regenerated with no changes: 55 app Swift files and 15 resources |
| Manual simulator smoke | Summary → drag/snap to Records → diary → rendered original → Summary passed |
| Manual production browser smoke | Demo dashboard → diary → original preview passed; signed-out `/app` redirected to login |

Core/native tests were run against the checkpointed application sources, which remained byte-identical through the branch merges. Final web/server checks ran after their integration fixes. All checked-in demo/native fixture copies remain aligned. Root `.env` is empty and ignored; no real credentials were added.

Live PostgreSQL/Tiger, real microphone/phone hardware, paid providers and outbound clinic calls were not exercised. The incoming ElevenLabs results are retained teammate evidence, not a claim of a new live run. Hosted deployment was not part of this integration.
