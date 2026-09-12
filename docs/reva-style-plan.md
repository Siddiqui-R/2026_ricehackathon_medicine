# Reva — iPhone style plan

**Date:** September 12, 2026  
**Status:** Implementation authorized by the later user goal. Apple Health-led visual direction; the user's supplied palette supersedes the four earlier candidates. Exact source colors are in [palette.json](../design/palette.json).

## Selected palette — authoritative update

Ivory `#FAF4F4`, Gold `#C8A07D`, Slate `#A2B7BC`, Teal `#0A5B6C`, Aqua `#6FABB6`, Sky `#E1ECEE`. All six values were extracted from uniform 40 × 40 pixel interior samples of the original sRGB image. Preserve these source tokens; use Teal for primary actions, Ivory as the warm canvas, Sky for soft emphasis, and Gold/Slate/Aqua sparingly. Extra neutral/status/dark colors are derived implementation tokens. See the [extraction method and roles](../design/README.md). Earlier A–D options below are historical, not pending choices.

## 1. Design direction

**A calm, native medical companion built around readable information and appointment preparation.** Apple Health is the primary visual reference: prominent page titles, generous type, quiet grouped cards, familiar navigation, and a clear path from summary to detail. Reva's own content is uploaded records, appointment preparation, booking, and visit recording.

The user's latest feedback supersedes the earlier mixed-reference recommendation in [the reference sheet](reva-design-references.md):

| Reference | Role in Reva |
| --- | --- |
| **Apple Health — preferred** | Primary reference for hierarchy, typography, surfaces, density, and native interaction. |
| Guava — acceptable | Limited workflow reference for organizing records and preparing for a visit. It does not set the visual style. |
| MyChart — acceptable | Familiar medical vocabulary and appointment metadata. |
| One Medical — rejected | Excluded from the design direction and subsequent mockup references. |

Reva should feel personal and composed. Use color to clarify a useful action or state. Keep medical content visually neutral, with dates, source names, and plain-language labels doing most of the work. A future logo may provide character; the reading experience should remain simple.

## 2. Navigation and page hierarchy

Use three persistent native tabs:

| Tab | Purpose | First-level content |
| --- | --- | --- |
| **Summary** | Home and the next useful action | Upcoming visit, preparation status, items needing review, recent records. |
| **Records** | Search and review the user's uploaded history | Search, compact category filters, chronological records, Add Record. |
| **Visits** | Prepare for and review appointments | Upcoming visits, active booking requests, past visits and recordings. |

The home screen's large title is **Summary**. Account and settings live behind an accessible profile button in the top-right corner. Use native push navigation for record and visit detail; use sheets for short tasks such as choosing an upload source or entering a visit goal. Keep the main tabs visible on ordinary detail screens and use a focused full-screen experience where scanning or recording requires it.

The core route is **Summary → upcoming visit → pre-visit report → source evidence**. Records can also be opened directly. A visit detail page holds preparation, booking details, recording, and post-visit notes together so the user does not have to remember which part of the app owns them.

## 3. Typography

Use the iPhone system font, SF Pro, through native text styles. The sizes below are design targets at the default text-size setting; implementation should use scalable semantic styles. Apple's guidance supports system text styles, Dynamic Type, adapting layouts to larger text, and limiting truncation. [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

| Role | Native style / default target | Treatment |
| --- | --- | --- |
| Main page title | Large Title / 34 pt | Bold; one prominent title per page. |
| Major section | Title 2 / 22 pt | Bold; clear space above. |
| Detail heading | Title 3 / 20 pt | Semibold. |
| Card or row title | Headline / 17 pt | Semibold; wraps when needed. |
| Medical content, questions, input | Body / 17 pt | Regular; comfortable paragraph spacing. |
| Supporting metadata | Subheadline / 15 pt | Secondary text color. |
| Source/date annotation | Footnote / 13 pt | Short supporting information only. |

Use sentence case. Keep medical doses, units, dates, and instructions in body-size text when they affect interpretation. Use tabular digits for a recording timer. Long report paragraphs should become short, clearly titled sections; avoid tiny text as a way to fit more content.

## 4. Layout and surfaces

These are Reva design targets, subject to checking on real iPhone sizes:

| Token | Proposed value | Application |
| --- | --- | --- |
| Horizontal content margin | 20 pt | Main reading column, respecting system safe areas. |
| Card padding | 16 pt | Content inside cards and grouped sections. |
| Small spacing | 4 / 8 pt | Icon-label gaps and related metadata. |
| Standard spacing | 12 / 16 pt | Between rows, content blocks, and cards. |
| Section spacing | 28–32 pt | Between distinct tasks or topics. |
| Card corner radius | 20 pt | Continuous rounded shape; neutral fill. |
| Small inset surface radius | 12 pt | Source previews and short state messages. |
| Primary action height | At least 50 pt | Grows with text; one prominent action per task. |

Use a pale grouped canvas and white content surfaces in light mode. Use thin separators within a group when several rows belong together. Avoid making every data field a separate card. Cards have no routine drop shadow; separation comes from the background and spacing. Icons are restrained, consistent SF Symbols, typically 20–24 pt in rows. Category labels accompany them.

Use native navigation and controls so system appearance and accessibility behaviors remain familiar. Large medical text areas and document pages stay on opaque surfaces. Decorative gradients, colored hero banners, charts without meaningful data, and oversized AI badges are outside this direction. No wellness metrics, activity rings, readiness percentages, or invented health/AI scores.

## 5. Color candidates — choose one

All four options share the same layout and neutral foundation. The choice changes the app's accent and soft emphasis color, not its information hierarchy. These are proposed design swatches, not hard-coded replacements for system semantic colors. Native system backgrounds, labels, and separators should remain adaptive; custom accents need light, dark, and increased-contrast variants. [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)

| Candidate | Light accent | Light wash | Dark accent | Dark wash | Character |
| --- | --- | --- | --- | --- | --- |
| **A · Clear Blue** | `#0066CC` | `#EAF3FF` | `#66B3FF` | `#152C43` | Familiar, direct, closest to a standard iPhone utility. |
| **B · Deep Teal** | `#08777C` | `#E8F5F4` | `#55D5CE` | `#123330` | Calm and more distinctive, with a green-blue accent. |
| **C · Soft Indigo** | `#6355C7` | `#F0EDFC` | `#B7A8FF` | `#2A2342` | Quiet and polished, with a more recognizable brand accent. |
| **D · Warm Rose** | `#AE4565` | `#FBEFF3` | `#F59DB5` | `#3A202A` | Gentle and personal; needs particular care to stay distinct from error red. |

**Recommendation for the user to consider: A · Clear Blue.** It best supports the requested native familiarity. B is the strongest alternative if Reva should have a little more visual identity. No palette is finalized until the user chooses.

Computed flat-color contrast for the light accent against white: A **5.57:1**, B **5.33:1**, C **5.75:1**, D **5.47:1**. Each also exceeds 4.5:1 against the shared light canvas and its own proposed wash. These are swatch checks; final components, states, and dark-mode combinations still need review.

### Shared foundation

| Role | Light reference | Dark reference |
| --- | --- | --- |
| Canvas | `#F2F2F7` | `#000000` |
| Card surface | `#FFFFFF` | `#1C1C1E` |
| Primary text | `#1C1C1E` | `#F5F5F7` |
| Secondary text | `#62626B` | `#AEAEB6` |
| Text on filled accent button | `#FFFFFF` | `#101014` |

Use the accent for the selected tab, links, primary actions, and an occasional small meaningful icon. Use the wash sparingly for a ready-report panel or selected option. A mostly neutral screen is intentional. In dark mode, the pale light-mode washes must become darker tinted surfaces; they are not carried across unchanged. Use dark foreground text on bright filled dark-mode accent buttons; check contrast on the actual components.

### Shared semantic states

| Meaning | Light candidate | Dark candidate | Always paired with |
| --- | --- | --- | --- |
| Completed / confirmed | `#287449` | `#74D99C` | Checkmark plus “Ready” or “Confirmed.” |
| Review / attention | `#946000` | `#F2C66D` | Attention icon plus specific explanation. |
| Failed / destructive | `#C03436` | `#FF8E93` | Error icon plus recovery action, or an explicit destructive-action label. |

State colors describe processing or booking status. They do not imply a medical assessment. A “Ready” report means preparation finished. It is not a declaration that the person is healthy. For D, error treatment uses its explicit label and icon, with rose reserved for ordinary interaction.

## 6. Screen and component plans

### Summary

Top to bottom: large Summary title and profile button; one upcoming-visit card; an attention section when action is needed; recent records; a compact Add Record entry. With no appointment entered, the main card explains what a visit goal enables and offers **Add a visit**. Do not display empty analytics or placeholder medical numbers.

The upcoming-visit card contains appointment type, provider if known, date/time, short visit goal, report state, and one primary action. Example: “Orthopedics · Sep 18, 10:30 AM,” “Review ongoing knee pain,” “Pre-visit report ready,” **View report**. A scan needing correction appears in a separate concise row: “Review text · 1 page needs a clearer scan.”

### Records list and record detail

Each list row has one document-type icon, a useful document title, medical record date, source/provider when available, and explicit processing status. Group by month. Search stays easy to reach. Filters use plain terms such as All, Labs, Notes, Scans, and Recordings.

Detail opens with a consistent header: title, document type, record date, source, and processing state. Then show **Summary**, relevant structured content, **Source details**, and **Original document**. Use the same framework for labs, discharge notes, images, and other uploads, but show only sections supported by that item. Preserve units and reported reference ranges when present; make missing or unclear values explicit. The original remains readily accessible.

### Pre-visit report

Begin with the appointment and the user's stated goal. Show “Prepared from 6 records · Updated Sep 12” as factual provenance, with the actual count/date. The report contains: **What to discuss**, **Relevant history**, **Questions to ask**, and any supported **Medications and allergies** or **Items to clarify**. Favor a short first view with expandable detail, not a long feed of equally prominent cards.

Every factual claim has an adjacent source reference, such as **Visit note · Jun 4 · p. 2**. Tapping it opens the original page and highlights the supporting passage when possible. A question generated for discussion is labeled as a suggestion; it is distinct from a fact extracted from a record. Users can edit questions and visit goals. A visible update state explains when newly added or corrected records require regeneration. Export should preserve the same hierarchy and readable source references.

### Scanner and extraction review

Use the native document scanner for capture. After capture, show page thumbnails with clear retake, rotate, crop, and remove controls. The review screen pairs a page preview with its extracted text; on an iPhone, use a readable vertical arrangement or a toggle instead of squeezing both into narrow columns.

Highlight the specific uncertain passage and explain the action needed: “Check this dose” or “Retake page 2; text is blurred.” Make corrections possible next to source context. Distinguish “Page saved,” “Reading text,” “Needs review,” and “Summary ready.” Do not visually promise that scanning is flawless or hide a missing page behind a success checkmark.

### Booking request and status

Show the requested clinic, appointment reason, acceptable dates/times, and relevant call constraints in a plain review sheet before the request is placed. The active status surface shows **Request submitted → Calling → Proposed time / Needs your input → Confirmed**, with only actual completed stages marked complete.

A proposed slot has readable date, time, time zone where relevant, provider, location, and an explicit next action. Busy lines, failed calls, and callbacks have direct status text and a retry or edit path. Use **Confirmed** only when confirmation is actually obtained. Do not show a fabricated live availability grid. The call summary can expand below the current status.

### Visit recording and transcript

Open from the relevant visit. The focused recording screen displays visit title, unmistakable Recording/Paused state, elapsed time, and large Pause/Resume and Finish controls. A simple audio-level indicator can confirm input, but is secondary to those controls. A brief consent acknowledgement belongs before starting; technical transcription provider names do not belong in this flow.

When interrupted, show what was saved and the next available action. After finishing, show upload/transcription progress, then a timestamped transcript and summary linked back to the visit. Unclear speech receives an explicit mark and a way to replay that timestamp. The transcript editor retains source-audio access. Empty audio and transcription failure each have a specific recovery state.

## 7. Common states and evidence rules

| State | Presentation | Useful action |
| --- | --- | --- |
| Empty | One short explanation and an appropriate illustration/icon only if useful. | Add record or add visit. |
| Uploading / processing | Named stage and real progress when available; otherwise an indeterminate indicator. | Leave the page and return later. |
| Partial / needs review | State what is missing or uncertain beside the affected item. | Review text, retake, or replace file. |
| Failed | Specific plain-language reason when known; preserve saved work. | Retry or change input. |
| Ready | Quiet completion label and access to the result. | Read summary or view report. |
| Report needs update | Explain which new/corrected record changed the evidence set. | Update report. |
| Offline | Show what is available and which action requires a connection. | Continue with available content. |

AI summaries are labeled **AI summary** near the section heading. Do not use a large assistant avatar, sparkle animation, or numerical confidence score as an authority cue. Source-linked facts, user-entered details, and generated questions must be distinguishable. Show dates in compact, locale-aware form: **Sep 12**, **Jun 4, 2024**, or **Today, 10:30 AM** when appropriate. Use the full date in detail views and accessible labels; distinguish the medical event date from the upload date.

## 8. Accessibility and interaction requirements

Reva's reading and review workflows must work with large text and assistive technology. Apple recommends Dynamic Type, readable default text, and alternate ways to communicate information beyond color. [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Project acceptance targets:

- Tap targets of at least 44 × 44 pt; important controls remain reachable without precise tapping.
- Body text contrast of at least 4.5:1; large text and essential interface graphics at least 3:1 against their actual background.
- All key workflows checked at the largest accessibility text sizes. Rows grow; side-by-side layouts stack; source links remain usable.
- VoiceOver labels identify document title, date, type, and status coherently. Headings support navigation, and processing completion is announced without repeatedly interrupting reading.
- Status always includes text or an icon with an accessible label. Increase Contrast and Reduce Transparency receive deliberate review.
- Respect Reduce Motion. Use small native transitions, with no pulsing medical values or decorative animated backgrounds.
- Medical values, uncertainty messages, questions, and confirmation actions never rely on ellipsis to fit.

## 9. Next design review

The user's next decision is **A, B, C, or D**. The palette comparison should show identical synthetic content and the same card structure so the choice is about color. After selection, the next planning deliverable is a focused set of screen mockups: Summary, Records, record detail, pre-visit report, scan review, booking status, and recording. Validate the selected palette in light mode, dark mode, and larger text before freezing tokens.

Working marketing line: **“Making every appointment count.”** Use it on the welcome screen or marketing material. Day-to-day screens should use task-specific copy, such as “Your report is ready” and “Add records for your next visit.”
