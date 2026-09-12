# Track 14 — Browser presentation, landing, and accessibility

**Codex continuation.** This report completes a missing Fable track after the user reported Claude account limits. It was produced by the existing Codex subagent `/root/symptom_entries`; no new Fable worker or Fable/Ultracode execution is claimed. Model/effort are inherited from the parent Codex task and were not independently selectable here.

**Snapshot:** `fable-audit-20260912-114322 @ cfe0997+wip`, source `/Users/tempadmin/Documents/Reva/.worktrees/fable-audit-20260912-114322`. Only this frozen source, the audit packet, and saved evidence were read. `START-HERE.md`, checklist, assigned track instructions, finding schema, supervisor brief and Addendum 1, refreshed frozen specification, and handoff ledger were consulted. No application edits, Git operations, builds/tests, listeners, UI controls, credentials, or live services were used by this continuation. Existing runner outputs are attributed to their actual producer. Findings require independent coordinator validation.

## Result

Two actionable source-proven accessibility findings survive: **RVA-14-001 (P2)**, unnamed tablet navigation after CSS hides its labels; **RVA-14-002 (P3)**, low-contrast text selection. Their exact triggers, lines, impacts, minimal fixes, and checks are in `track-14-findings.json`.

The captured workspace presents clear clinical groupings, distinct local/demo/AI labels, Records and appointment navigation, and the approved heart palette. The public landing is a minimal prototype page. Signup/login are explanatory gates in this snapshot, not working account forms. The required real forms, `/app`, sessions, and account isolation remain **WIP** under the refreshed specification; the stale “accounts are deferred” comment at `landing/AccountGate.tsx:9` does not override that authority.

## Assigned inventory and inspection

All 13 assigned production files were inventoried. Direct source inspection concentrated on routing, control labels, responsive selectors, palette/selection states, modal behavior, landing copy, and feedback; this is not a claim that every CSS rule was manually traced. Supporting feature source was consulted only to resolve navigation evidence:

- `apps/web/src/App.tsx`, `main.tsx`.
- `apps/web/src/landing/Landing.tsx`, `AccountGate.tsx`.
- `apps/web/src/components/Brand.tsx`, `ui.tsx`.
- `apps/web/src/styles/tokens.css`, `layout.css`, `components.css`, `features.css`, `landing.css`.
- `apps/web/src/features/Dashboard.tsx`, `SettingsPage.tsx`.

Supporting reads: Records query/dialog routing and detail back-link markup; Medical Profile settings link; frozen design palette and current specification.

## Evidence and coverage

The saved `evidence/r2-ui-matrix.jsonl` has **76 captures**, covering 12 routes/states at each width **375, 390, 768, 1024, 1440, 1920**, plus four additional 375-wide captures. Every row reports no horizontal overflow and no footer/mobile-nav intersection. These are captured-layout observations, not a full interactive journey or screen-reader audit. The principal matrix uses height 1400; the additional height 900 captures are not a 200% zoom or short-phone keyboard test.

Codex visually inspected saved images with `view_image`: `demo-summary-1440.png`, `demo-profile-768.png`, `demo-records-add-symptom-375.png`, `landing-390.png`, and `demo-record-detail-375.png`. Matching saved DOM was consulted. The symptom form clearly distinguishes required symptom/time from optional details and shows Save/Cancel; the desktop dashboard is coherent and the tablet rail visibly collapses to icons.

| Requirement | Status | Evidence and boundary |
| --- | --- | --- |
| C02 | WIP | `main.tsx:20–34` implements landing, demo, placeholder login/signup, and legacy hash forwarding. App hash routing and route focus are at `App.tsx:39–63`; the matrix renders its main/detail/intake routes. `/app` and real account forms are absent from the captured WIP. Cancel/reopen and history were source-reviewed, not newly exercised. |
| C03 | Pass | `Dashboard.tsx:60–90` provides upload/symptom/visit actions; the recent-record footer reaches Records and Medical Profile is linked. Screenshot `demo-summary-1440.png` shows those controls. Settings has no Appearance control and the obsolete history-retention tile is absent. |
| K01 | Pass | `tokens.css:8–19` matches all six current light roles; the exact palette is visible in saved screens. Computed normal action white/red and deep-red/petal pairs are 5.3392:1 and 6.7760:1. The selection-state defect is separately classified under K04. |
| K02 | Pass | Saved desktop dashboard, tablet profile, phone source, and landing images support appropriate platform hierarchy and clearly fictional prototype labeling. Native Apple Health-like hierarchy belongs to the native track; no new native UI inspection was performed here. |
| K03 | Unverified | The recorded 76-row width matrix passes its overflow/overlap checks. Actual zoom/large text, short phone height with software keyboard, all editor validation states, and complete interaction coverage are not established. |
| K04 | Defect | RVA-14-001 and RVA-14-002. Positive source evidence includes `ui.tsx:95–118` native modal/showModal/Escape/focus restoration, explicit labels, `App.tsx:93–102` skip link, `App.tsx:234–248` alert/status feedback, and `tokens.css:188–195` reduced-motion override. Actual focus trap/restoration and assistive technology remain unverified. |
| K05 | Unverified | No saved Safari/Firefox/iPhone hardware execution or real audio/export evidence in this track. The browser guide distinguishes local IndexedDB from an offline-launch service worker; codec/permission support remains platform-dependent. |

## False-positive checks

The matrix's zero-sized sidebar “Log a symptom,” brand, and Settings targets at phone widths are hidden desktop duplicates, not missing mobile controls: Dashboard supplies a visible symptom action and App supplies mobile brand/settings. “View original” was not found because the actual button is named **Open original**. “Update brief” is absent on an unprepared visit that instead exposes **Prepare my visit**. Those selector mismatches are not defects.

The record detail's **All records** link uses the global `breadcrumb` class (`RecordDetail.tsx:107`), so the phone CSS hides that top link. The visible bottom **Records** tab still reaches the list; this is a consistency observation rather than an inaccessible navigation dead end. Small isolated back links are not automatically target-size failures without checking the spacing exception. No quota of visual findings was imposed.

The matrix's label inventory is based on DOM text, which includes `display:none` descendants; it does not refute the tablet accessibility-name defect. Screenshot labels and accessible names are different evidence.

## Evidence requests and limitations

Sent promptly to the coordinator: at width 768 inspect the computed accessibility names of `.desktop-nav a`, `.sidebar-log`, and sidebar Settings; inspect the computed `::selection` colors while selecting source text. Also requested one bounded Tab/Shift-Tab/Escape/return-focus check on a query-opened symptom dialog at 375×667 and a zoom check if available. No such fresh execution is claimed in this report. The account/deployment delta must be reviewed only after an explicit completed checkpoint; this report does not blend later live files into the frozen snapshot.
