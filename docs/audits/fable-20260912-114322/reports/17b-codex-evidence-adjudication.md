# Evidence runner continuation and adjudication

Author: Codex supervisor, 2026-09-12. This report supplements the original [Fable stage-one report](17-evidence-runner.md); it does not attribute Codex work to Fable. Source: the frozen snapshot in [the manifest](../snapshot-manifest.json).

## Saved browser stage two

Fable saved [76 capture measurements](../evidence/r2-ui-matrix.jsonl), each with a PNG and DOM snapshot in `../evidence/ui/`. There are twelve route/form states at each of 375, 390, 768, 1024, 1440 and 1920 CSS pixels, plus four tall 375-pixel captures. States include landing, login/signup placeholders, demo summary, records, visits, medical profile, settings, record/visit detail, import and symptom forms.

All 76 rows report no horizontal document overflow and `ok: true`. These are saved collector results, not 76 independently executed functional tests. The supervisor visually inspected the 1920-pixel Summary, 768-pixel Medical profile and 375-pixel symptom form. They show the intended heart palette, platform-specific layout, persistent profile separation and a visible form save/cancel area at the captured height. The symptom capture is 1400 pixels tall; it cannot prove usability at a short phone height or with its software keyboard open.

The matrix's `unlabeled: []` is not proof of accessible names. It records text present in the DOM even when responsive CSS hides that text. Track 14 independently identifies the tablet navigation naming defect. Several mobile `coveredBy` results refer to zero-size, intentionally hidden desktop sidebar controls; they are not evidence that the visible mobile navigation is blocked. No nonzero-size action in this saved matrix is reported covered by the mobile navigation.

Unverified: keyboard sequence, focus trapping/restoration, Escape, screen reader behavior, 200% zoom, Dynamic Type, short viewport with keyboard, completed multi-step import/report/export/reload journeys, actual print PDF, native simulator interaction, physical iPhone, Safari and Firefox. Screenshots cannot close these gates. Claude Desktop was last unavailable to the Computer tool during takeover; the Codex continuation did not fabricate further UI activity.

## Focused production native reproduction

The executable [ProviderContextRepro.swift](../evidence/codex-takeover/ProviderContextRepro.swift) is compiled by [the runner](../evidence/codex-takeover/run-provider-context-repro.py) with thirteen unchanged production Swift files and a deterministic synthetic provider transport double. [Source hashes](../evidence/codex-takeover/provider-context-production-hashes.json) identify the compiled production code. All state writes use a disposable directory under `/private/tmp`; no real account, patient data or provider is involved.

The [final output](../evidence/codex-takeover/provider-context-repro.txt) records compiler exit 0 and executable exit 0:

| Observation | Disposition |
| --- | --- |
| An owner-A summary publishes after the connection token changes to owner B. | Reproduces RVA-10-001 against production state methods. |
| A delayed owner-A call transcript persists into a replacement owner-B snapshot with the same booking ID. | Reproduces the second arm of RVA-10-001. Client stale publication; no server authentication bypass is claimed. |
| All three current browser signature goldens equal hashes emitted by the frozen Swift ReportEngine. | Closes RVA-06-002's missing native execution evidence. Browser equality is separately covered by the saved 77-test run. |
| Native visit projection orders 08:45Z before 10:00+02:00, although the latter is 08:00Z. | Reproduces the mixed-offset ordering defect, canonical RVA-04-001. |
| A startup repair write fails while valid `state.json` remains readable; the store retains a snapshot but sets `startupError`. | Reproduces RVA-03-001's state condition. RootView's recovery presentation is verified from source, not UI interaction. |
| The 1800-character excerpt ends in synthetic `dose: 10`, while the source ends in `dose: 100 mg`, with no omission marker. | Reproduces RVA-02-002 using production `ReportEngine.localExcerpt`. |
| A normal content line before `Source date:` is removed by the fixture-wrapper heuristic. | Reproduces RVA-02-005 using production `ReportEngine.localExcerpt`, which receives no demo provenance flag. |

The first attempt could not create the platform-default temporary attachment directory under the filesystem sandbox. The runner was changed to use the allowed `/private/tmp` directory. Compiler cache/FSEvents warnings remain in the successful log; they did not prevent compilation or execution. No compiler warnings were interpreted as application defects.

## Build and measurement boundaries

Reuse the stage-one report for the clean-install failure followed by successful asset preparation/build/typecheck, 77 browser tests, seven wrapper checks, native/server package tests, optimization checks, native-client/server integration, local server smoke, fail-closed PostgreSQL checks and simulator compilation. These commands were actually run by Fable against this snapshot; Codex did not rerun them merely to increase counts.

The recorded 50.7 MB raw distribution includes 47.8 MB of OCR assets. It is not initial page transfer size. CPU-contended command durations are not comparative performance benchmarks. Large-file memory/latency, camera scan peak memory, live model quality/latency, real PostgreSQL/Tiger operation and hosted Vercel behavior remain unverified.

All [267 frozen source hashes](../evidence/codex-takeover/snapshot-integrity.json) still match after the continuation checks. Raw Fable `.log` files are retained locally and indexed by hash; concise results, reports, JSON measurements and synthetic screenshots are versioned. No app fixes were made during this audit.
