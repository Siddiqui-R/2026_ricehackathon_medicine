# 04 — Heart red palette and outlined treatment (applied to main)

Applied directly in the main checkout on September 12, 2026, on top of 1f1d90c, after the user chose comparison option M (heart red and ivory, outlined layout) with a slightly softer red. Not committed, not built by Claude. A first pass had landed only in `.worktrees/final-review`, which is why an Xcode rebuild from main still showed the Sky-blue canvas; this pass ports the same change into main's `Features/` layout by content.

## Tokens (`apps/ios/Reva/Features/Shared/Theme.swift`)

Main forces light appearance, so tokens stay fixed sRGB values with no adaptive substitution, matching the file's existing standard.

| Token | Value | Role |
| --- | --- | --- |
| canvas | `#FBF7F5` blush ivory | Page and form background (was Sky `#E1ECEE`) |
| surface | `#FFFFFF` | Outlined cards, tiles, unselected filter chips, form rows (was Ivory) |
| accent | `#B84250` heart red | Primary buttons, tint and selected tab, heart glyph, row icons (was Teal) |
| accentText (new) | `#8C2F3B` deep red | Chip labels, mode badges, profile initials |
| soft | `#FAE6E5` petal | Chips, notices, circular icon fills (was Sky) |
| hairline (new) | `#DBCBC9` linen | Card, tile and chip outlines |
| buttonText | `#FFFFFF` | Text on filled buttons (was Ivory) |

The six supplied constants `ivory`, `gold`, `slate`, `teal`, `aqua`, `sky` are removed; no view referenced them. The red was softened from the comparison's `#C0273A` to `#B84250`.

Contrast (WCAG 2.x): white on accent 5.34, accent on canvas 5.01, accentText on soft 6.78, accentText on surface 8.12. Accent on soft is 4.45, which is why chip and badge text uses accentText. Reserved dark roles are recorded in `design/palette.json` but not wired.

## Components (`Features/Shared/ViewComponents.swift`)

- `View.outlined(radius:)` (new): white surface, 16 pt radius, 1 pt hairline border. This is the layout treatment.
- `RevaCard`: filled 22 pt card with 20 pt padding → outlined 16 pt card with 18 pt padding.
- `PrimaryButtonStyle`: radius 15 → 12.
- `IconTile`: 44 pt rounded square → 42 pt circle, petal fill, red glyph.
- `ModeBadge`: text accent → accentText.
- `StatusChip` (new): caption semibold accentText on a petal capsule, optional SF Symbol.
- Unchanged: `SectionHeading`, `DetailLine`, `StatusNotice`, `Page`, `RevaForm` (white rows on blush canvas through the tokens).

## Views

- `Features/Shared/SummaryView.swift`: "UPCOMING" caption → `StatusChip("Upcoming")`; the add tile and quick-action tiles use `outlined()`; toolbar initials use accentText.
- `Features/Shared/RecordRow.swift`: "Review extraction" label → `StatusChip`.
- `Features/Preparation/VisitsView.swift`: brief state label on each visit card → `StatusChip` with the same text and symbol.
- `Features/Preparation/VisitDetailView.swift`: booking status caption → `StatusChip`.
- `Features/Records/RecordsView.swift`: unselected filter capsules gain a hairline outline; the selected capsule stays filled red.
- No files added or removed, so `scripts/generate_project.py` does not need to run.

## Design files and docs

- `design/palette.json` → renamed `design/palette-supplied.json` (sampled Ivory/Gold/Slate/Teal/Aqua/Sky, unchanged, provenance).
- New `design/palette.json`: selected palette, roles, contrast figures, treatment, reserved dark roles, notes.
- `scripts/extract_palette.py`: writes `design/palette-supplied.json` so a re-run cannot overwrite the selection.
- `design/README.md`: new lead paragraph; the supplied-swatch section retained under a "superseded" heading.
- `docs/reva-style-plan.md`: the authority blockquote and "Selected palette" section replaced; the rest, including the historical A–D table, untouched.
- Not updated, owner's call: `README.md`, `docs/build-progress.md`, `docs/team-workflow.md`, `docs/verification/profile-symptoms.md` still describe the Sky/Ivory/Teal palette as current.

## Manual checks

1. Build in Xcode; the only new API surface is `outlined(radius:)`, `StatusChip`, `RevaTheme.accentText`, `RevaTheme.hairline`.
2. Summary: blush canvas, white outlined cards, red primary button, "Upcoming" chip, red heart tab icon and tint.
3. Records: outlined unselected filter chips, filled red selected chip, petal circles behind row icons, a needs-review record shows a chip.
4. Visits list: each card ends with a "Ready to prepare" / "Brief ready" / "Brief needs an update" chip. Visit detail: booking rows end with a status chip.
5. Forms (visit editor, record editor, profile): white rows on the blush canvas.
6. Larger text (AX1): chips wrap rather than clip; card outlines stay 1 pt.
7. Destructive actions and alerts still use system red; confirm the brand red on the same screen does not read as an error.

## Not changed

Models, engines, `AppStore`, provider clients, server, tests, web client, and the uncommitted server edits already present in main (`Models.swift`, `Providers/VoiceTransport.swift`, `VoiceProviderTests.swift`), which belong to another session.
