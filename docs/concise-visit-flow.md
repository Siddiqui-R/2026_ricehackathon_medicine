# Web pre-visit preparation and recording

Home provides **Upcoming visit** and **Record session**. The appointment list is no longer a navigation destination. Existing appointments, reports and audio remain intact; old visit URLs still open.

Upcoming visit accepts a visit type, optional concern and up to three questions. Each Run pre-visit brief click calls authenticated `POST /v1/ai/prepare`. Both servers start each analysis on `gemini-flash-latest`, then immediately try the fixed `gemini-flash-lite-latest` alias once after a transient provider failure. Missing/blank settings and prior `gemini-3.8-flash`, `gemini-3.5-flash-lite` or `gemini-flash-lite-latest` settings migrate to the Flash primary; other explicit `GEMINI_MODEL` values remain shared primary overrides. Further Lite-only retries wait 60, 120, 240 seconds and so on, honoring a longer server delay. Browser and native brief validation accept the attributed model without pinning one release. A working server key with access to the configured model is required. Errors are shown; this flow has no local or cached fallback.

The request contains original readable records plus an explicitly patient-provided medical profile. Responses are limited to 180 words, three short questions and six source references. Source/identity changes invalidate pending results. The brief stays in memory until the user downloads the PDF or closes the flow; no scheduled visit or report is persisted by this flow.

The PDF uses one letter-size page, an embedded licensed Noto Sans font, patient details, concise body, questions and source titles/dates. Overflow fails rather than clipping clinical content or shrinking type. The client never reconstructs or repeats source excerpts. PDF libraries and the font load only on generation.

Record session opens consent-gated capture on home. Saved sessions are listed there with existing audio, transcription and summary controls. Standalone recordings use an empty `visitID`; nonempty IDs must still reference a visit. Web and Swift aggregate validators accept this representation. Audio and metadata retain their atomic persistence boundary.

The native iOS screens retain their existing navigation; this change targets the web product. Its shared snapshot validator and local server provider are updated for compatibility.
