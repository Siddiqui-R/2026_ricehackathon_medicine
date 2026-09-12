# Reva review decisions

## Claude architecture review — Fable 5.1 Extra

Desktop Code task `local_3c7583ff-a1c1-44ed-a2f1-a225a45f2e72`, working folder `/Users/tempadmin/Documents/Reva`. Report: `01-architecture.md`. Bounded review; no live provider data. Accepted concerns about explicit local authority, summary origin, source-page mapping, interrupted booking recovery, real-versus-sample audio, scenario tests, server config boundaries and dark contrast. Resulting implementation contract records the selected solutions.

## Claude implementation review — checkpoint eb2ec3a

Same desktop task; isolated worktree `.worktrees/implementation-review`, branch `review/implementation`. Full source review, report `02-implementation.md`. Primary independently read the report, Core, AppStore, device adapters, HTTP auth/routes, configuration, SQL and transactional stores. Important accepted fixes:

1. Remove recognizable source wrapper headers from excerpts, include useful exact values and negations, prioritize structured implant inventory page for an implant question. Tests now require the actual excerpt to contain the fixture's evidence phrase, and the source to map to the right page.
2. Make visit questions/notes authoritative, mirror them into existing briefs and use them for regeneration/export.
3. Canonicalize appointment date instants in signatures so offset formatting alone does not stale a brief.
4. Preserve synthetic origin and page text on metadata-only record edits; targeted revision assigned to Claude in the worktree, application pending.
5. Execute every fixture inclusion/exclusion/pinning/review check through Swift, not a port. All 23 root tests passed after primary fixes; an additional date/question regression added next.
6. Explicit developer sync remains a manual snapshot demonstration. A conflicting write is rejected; local state remains intact. Further recovery UI review pending. Attachment IDs use SHA256 filenames and sanitized ASCII metadata.
7. Deleted/reset sources are retained as recoverable files; this is disclosed in Settings. Automatic permanent purge is outside this bounded demo, with backups useful for checkpoint recovery.

Device adapter contributor ran 26 simulator checks covering faithful bytes, OCR warnings/limits, page mapping, paginated export and actual tone playback. Primary inspected the output and rendered PDF. Real microphone capture and physical camera remain manual device checks.

## Resource observations

No reset credit was redeemed by the agent. Initial Codex weekly usage was64%; later65%; at the next fresh check on September12 06:55CDT the tool reported0% used with the same one reset credit still available. Claude used4% of its five-hour limit after architecture review, and later displayed3% weekly Fable usage after implementation review. No paid resources or upgrades were purchased.
