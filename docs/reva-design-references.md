# Reva — mobile design references

**Research date:** September 12, 2026  
**Purpose:** Compare real medical app screens before choosing Reva's style guide. These are references, not Reva mockups or finalized visual decisions.

**User decision, September 12:** Apple Health is the primary visual reference. Guava is acceptable only as a limited workflow reference; MyChart is acceptable for familiar medical information. One Medical is rejected as a design reference. The [current style plan](reva-style-plan.md) supersedes the earlier mixed-reference recommendation. Screens below remain a record of the comparison.

The screenshots below come from official product guides or App Store listings and were visually inspected during research. App Store images are marketing assets and may lag the shipping interface. Screenshots and brand assets belong to their respective owners; use the interaction lessons as references when designing Reva's own interface.

## 1. Four screens to compare first

| Apple Health — readable native dashboard | Guava — records timeline | One Medical — upcoming appointment | MyChart — clinical actions |
| --- | --- | --- | --- |
| [![Apple Health Summary](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/5f/6d/5a/5f6d5ade-1c75-6009-51e9-05a22a5506d0/Health_iPhone_Summary.001.jpeg/314x680bb.webp)](https://apps.apple.com/us/app/apple-health/id1242545199) | [![Guava medical records](https://s.guavahealth.com/article-img/ultimate-guide/records-page-1-2.png)](https://guavahealth.com/article/guava-ultimate-guide) | [![One Medical home](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/7d/ea/a9/7deaa9c5-74ef-e503-cee0-eeeb89c04c92/Home.png/314x680bb.webp)](https://apps.apple.com/us/app/one-medical/id393507802) | [![MyChart home](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/b0/bd/00/b0bd0029-082c-29f5-309f-2e7605067d1e/4b5b8fb6-cab7-4b16-962a-9d775460d761_1242_x_2688_-_1.png/314x680bb.webp)](https://apps.apple.com/us/app/mychart/id382952264) |

Each screenshot links to its official source. If an image does not load in a document viewer, open its linked source page.

## 2. What each reference contributes

### Apple Health

**Observe:** a prominent Summary heading, pinned cards, clear labels and dates, compact charts, and familiar bottom navigation. Dense underlying information is revealed progressively.

**Use for Reva:** native iPhone navigation, readable record/report typography, restrained card hierarchy, visible dates and units, and a clear path from overview to detail.

**Adapt:** Reva's primary card should be the upcoming visit/preparation status. Activity rings and wellness metrics would add scope without helping the user's stated workflow. Study the hierarchy, not the specific metric collection.

[Official App Store screenshots](https://apps.apple.com/us/app/apple-health/id1242545199)

### Guava

**Observe:** searchable medical records grouped chronologically, a Prepare for Visit entry, record-type icons, and a distinct visit-preparation flow. Its guide documents one-page tailored visit preparation with questions and relevant history.

**Use for Reva:** the clearest reference for turning a document library into appointment preparation. Study the relationship between the current profile, longitudinal history, visit goal, selected records, and report.

**Adapt:** keep the initial Reva scope narrower. Extensive tracking, integrations, and many medical categories could overwhelm an upload/preparation app. Make pending extraction and uncertain content clearer than a simple “file uploaded” state.

[Official product guide and screenshots](https://guavahealth.com/article/guava-ultimate-guide)

### One Medical

**Observe:** the upcoming appointment is prominent, with provider/context and explicit View details / Modify actions. Its booking screenshots show available times near provider information.

**User decision:** excluded from Reva's visual direction. This entry is retained only as part of the original comparison.

**Adapt:** One Medical has its own care network and appointment inventory. Reva must show the real states of phone-based booking: request ready, calling, needs input, proposed, and confirmed. Do not display live slots as though a scheduling API exists.

[Official App Store screenshots](https://apps.apple.com/us/app/one-medical/id393507802)

### MyChart

**Observe:** recognizable medical actions such as appointments, medications, results, and messages, alongside an upcoming office-visit card. The screenshot uses an angled phone in a promotional composition.

**Use for Reva:** familiar clinical vocabulary, understandable appointment metadata, obvious access to records and results, and date-first information.

**Adapt:** MyChart varies across healthcare organizations. Reva's manual-upload scope must be visible; avoid implying automatic hospital synchronization, provider messaging, or a live clinic account connection.

[Official App Store screenshots](https://apps.apple.com/us/app/mychart/id382952264)

## 3. Two more targeted references

| App | Relevant pattern | How it applies |
| --- | --- | --- |
| [PicnicHealth](https://picnichealth.com/explore-the-app) | Records timeline, condition/event pinboards, source-linked AI answers, printable Health Snapshot | Helps organize selected evidence into a coherent health story. Use feature illustrations for information structure; its [mobile guide](https://help.picnichealth.com/en/articles/4871296) confirms the member app's records/AI workflow. |
| [Ada — your health portal](https://apps.apple.com/us/app/ada-your-health-portal/id1099986434) | Guided intake and understandable questions | Useful for collecting visit concern, symptom timeline, and goal in manageable steps. Reva is not being designed as a diagnostic symptom checker. |

**Recording interaction:** [Abridge's current clinician recording guide](https://support.abridge.com/hc/en-us/articles/30207826574739-Recording-Basics) is useful for visible recording state, pause/resume, and deliberate finish. It is a clinician workflow; a current US patient-app listing was not verified, so old patient screenshots should not be treated as current design evidence.

## 4. Focused workflow examples

| Guava — collecting the visit goal | One Medical — selecting an appointment |
| --- | --- |
| [![Guava visit preparation](https://s.guavahealth.com/article-img/ultimate-guide/visit-prep-1.PNG)](https://guavahealth.com/article/guava-ultimate-guide) | [![One Medical appointment booking](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/0f/07/f8/0f07f84f-422a-1ea4-4134-87b10038e1ec/Booking.png/314x680bb.webp)](https://apps.apple.com/us/app/one-medical/id393507802) |

The Guava example includes a visit reason, symptoms/diagnoses, goal, and editable background context. The One Medical example illustrates readable provider/time choices. Reva can apply that visual clarity to a clinic's proposed slot, without suggesting a real-time inventory connector.

## 5. Original candidate directions and selected reference

| Direction | Reference combination | Best fit |
| --- | --- | --- |
| **Native and clinical** | Apple Health + MyChart | Immediate familiarity, large readable text, clear sections, practical medical labels. |
| **Personal record organizer** | Guava + PicnicHealth | A searchable timeline, polished document summaries, relevance selection, and obvious source access. |
| **Appointment companion** | One Medical + selected Ada intake patterns | An upcoming visit, preparation progress, questions, and recording anchor the app. |

**Selected direction:** Apple Health leads Reva's hierarchy, typography, surfaces, and native interaction. Guava contributes limited records-workflow ideas; MyChart contributes familiar medical labels. One Medical is excluded. Four palettes are presented in the [style plan](reva-style-plan.md); the user's color choice remains open.

## 6. Style-guide decisions after reference selection

The next planning pass should produce a small reusable system from the selected references:

| Area | Decision to make | Reva screen used to validate it |
| --- | --- | --- |
| Typography | Native text styles, size hierarchy, weights, numeric/unit treatment, Dynamic Type | Report with medical terms and a lab-result table |
| Color | Brand accent, background/surface/text roles, success/warning/error semantics, dark mode | Upload needing review; confirmed appointment |
| Layout | Spacing rhythm, margins, card/list use, section density | Home with one upcoming appointment and recent records |
| Navigation | Home/Records/Visits structure, account entry, contextual recording | Open appointment → prepare → record → review |
| Evidence | Source chip, page/timestamp link, AI label, uncertainty treatment | Report claim opening its original document page |
| Document presentation | Consistent header, summary, results, follow-ups, original view | Lab report, discharge note, camera scan |
| Forms and actions | Goal intake, add record, primary/secondary actions, destructive-action treatment | Create appointment and approve booking constraints |
| Processing states | Upload/OCR/summary progress, failed/partial/review-required states | Unreadable second page and a retryable model error |
| Recording | Timer, level/waveform if useful, pause, interruption, save/review | In-person visit with an incoming-call interruption |
| Accessibility | Contrast, tap targets, VoiceOver labels, scalable text, reduced motion | All key flows with large text and screen reader |
| Sharing | One-page brief and expandable detail; clean source appendix | Exported pre-visit PDF |

For the first design review, use a consistent set of synthetic content across candidate directions: one upcoming appointment, one ready report, one scan needing correction, one past visit, and a small records timeline. This makes the comparison about usability and visual hierarchy rather than different content.

Working product copy: **“Making every appointment count.”** Supporting copy: **“Your medical history shouldn't be a scavenger hunt.”** Avoid unsupported privacy, clinical-accuracy, or integration claims in the marketing design.
