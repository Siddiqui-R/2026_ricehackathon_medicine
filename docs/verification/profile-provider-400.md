# Automatic medical-profile HTTP 400

The deployed automatic profile update returned Google's `400 INVALID_ARGUMENT` while a summary using the same configured key/model succeeded. A direct fictional profile request reproduced the failure. Lowering the output token budget did not resolve it; removing the five outer category `maxItems: 30` constraints did. The corrected adapter succeeded with all nine fictional demo records on `gemini-3.5-flash-lite`.

The provider schema retains exact fields and source-ID enums. The prompt and server result validator still enforce at most 30 facts per category, bounded text, unique valid evidence IDs, and rejection of incomplete or unexpected output. No validation limit was removed from the application. Google documents that complex schemas can be rejected; this particular correction was verified with actual requests: [structured outputs](https://ai.google.dev/gemini-api/docs/structured-output).

- [x] Reproduce the original profile failure with fictional input.
- [x] Confirm the same credential works for summaries.
- [x] Verify corrected profile extraction with nine fictional source records.
- [x] Keep tests rejecting oversized facts, fabricated sources and incomplete results.
- [x] Replace the generic permissions/credits message with status-specific, sanitized guidance.
- [x] Pass 10 backend tests (database integration skipped), 281 browser tests, production build and source structure checks.

Deployment verification is performed after publishing. No credentials or raw provider response bodies are included in this report.

Separate observation: preparation still uses its documented fixed `gemini-3.8-flash` model. Direct checks saw intermittent provider overload (503) and a later successful response. This is distinct from the reproducible profile schema error; model selection was not changed in this fix.
