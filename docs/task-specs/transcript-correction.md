# Transcript correction and memory provenance

Written before implementation. Authority: the primary agent's bounded acceptance-audit assignment for T23/T24, using the current main checkout in `/Users/tempadmin/Documents/Reva`.

## Ownership and exclusions

Change only the transcript-related UI in `apps/ios/Reva/UI/RecordingViews.swift`, the `saveMemory` method in `apps/ios/Reva/State/AppStore.swift`, an optional `MedicalRecord.sourceRecordingID` field in `apps/ios/Reva/Core/Models.swift`, the minimal source-transcript navigation in `apps/ios/Reva/UI/RecordsView.swift`, and this specification. Preserve unrelated in-flight changes. Do not use an old review worktree, change audio adapters/services, run the simulator, commit, or push.

## Required behavior and design

- Existing nonempty transcripts offer an editor for segment text only. Speaker labels, segment IDs, recording-relative start/end timestamps, original audio filename, and sample origin remain unchanged. No segments are invented or added to a real recording with no transcript.
- Save corrections persist through the existing local repository. Validation rejects blank segment text, oversized input, or a source transcript whose segment identities changed while the editor was open.
- `VisitRecording.summary` remains the independently editable visit-notes field. Transcript correction never overwrites those notes or claims to regenerate them. The detail UI labels notes as separate from the transcript and displays a plainly labeled local excerpt computed from current transcript text.
- Extend the existing `saveMemory(recordingID:)` operation with an optional text-by-segment-ID correction payload. A correction updates the recording and any existing saved memory together in one `mutate`/repository write. It does not create a Records item unless the user separately saves memory. A normal save creates or updates the stable `memory-<recordingID>` item without duplicates.
- Saved memory summary is a current local excerpt of its transcript (or entered notes if there is no transcript). Independent visit notes remain separately labeled in the record notes. Preserve original sample origin. Advance source version only when source content/summary/state changes, so existing briefs can become stale.
- Add `MedicalRecord.sourceRecordingID: String? = nil` for backward-compatible existing fixture/snapshot decoding. Saved memories carry the originating recording ID. Record detail shows “Open visit transcript” when that source exists, otherwise an explicit source-unavailable notice. Deleting a recording retains saved memory and produces the missing-source state.
- Additional primary-agent audit request: the existing Records search string also includes summary, ISO record date, and the displayed record date. Keep its existing type/review filtering intact.

## Verification

The primary agent owns simulator/UI testing. Locally compile/typecheck the changed code with the current app sources without touching the Xcode project or simulator. Exercise optional-field backward decoding and memory correction semantics in an isolated temporary Swift harness if practical. Do not add broad domain abstractions just to create tests. Record exact commands/results and remaining UI checks below.

## Implementation and evidence

Implemented all assigned changes. `saveMemory(recordingID:correctedSegmentTexts:)` defaults the correction dictionary to nil, preserving the original call sites. Correction saves use a single `mutate` operation for the recording and any existing memory; they leave separate recording notes and any independently edited saved-record notes untouched. A normal explicit memory save refreshes its transcript/notes snapshot and uses a local excerpt as summary. Existing title/provider/date metadata is retained on refresh, and content changes advance the record source version. The editor is available only for an existing nonempty segment list and cannot add segments to real audio. Summary UI now distinguishes the current transcript excerpt from independently editable visit notes.

The optional `sourceRecordingID` decodes as nil in old fixtures. Newly saved or refreshed memories receive the source reference; old memories without it can be refreshed through their recording. Record detail resolves the link dynamically and shows a clear missing-source state after recording deletion. The existing Records filter logic is unchanged; its search string now includes `record.summary`, `record.date`, and `RevaDate.display(record.date)`.

### Compiler check

Full current app source typecheck passed (exit 0), without project or simulator operations:

```sh
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -typecheck -swift-version 5 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.4.sdk -target arm64-apple-ios18.0-simulator -module-cache-path /private/tmp/reva-device-module-cache apps/ios/Reva/Core/*.swift apps/ios/Reva/Device/*.swift apps/ios/Reva/State/*.swift apps/ios/Reva/UI/*.swift apps/ios/Reva/RevaApp.swift
```

### Persistence regression checks

An isolated macOS Swift harness compiled the actual current Core sources and an exact AppStore copy with only its initializer's storage path redirected to `/private/tmp/reva-transcript-qa/State`. No application/user storage was touched. The temporary harness and results are `/private/tmp/reva-transcript-qa/Harness.swift` and `/private/tmp/reva-transcript-qa/results.txt`. The first compile required adding an explicit macOS SDK/target because the compiler's default macOS target could not load the standard library; the explicit SDK build and execution passed.

All 17 checks passed:

1. Old fixture records decode the optional recording reference as nil.
2. Correction changes the intended segment text.
3. Segment IDs, speakers, start and end times remain identical.
4. Separate visit notes, fictional origin, and audio filename remain identical.
5. Correcting before memory creation does not add a Records item.
6. Saving memory links the correct recording and includes its timestamp ranges.
7. Memory summary is the current transcript's local excerpt; separate notes remain available.
8. Repeated unchanged save neither duplicates records nor increments source version.
9. A later correction refreshes saved memory and advances its source version.
10. Both independent saved-record notes and separate visit notes survive correction.
11. Blank segments are rejected.
12. Changed/missing segment identities are rejected.
13. Failed correction leaves recording and saved memory unchanged.
14. Corrections and source references survive repository reload.
15. Text correction cannot invent segments for real audio without a transcript.
16. Real-audio notes preserve real origin and do not create a fake transcript.
17. Deleting the source recording retains the memory and leaves a detectable missing reference.

Primary still owns the actual UI walkthrough: sample recording → Edit transcript text → Save corrections → save/update Records memory → Open visit transcript, plus deleted-source notice and summary/date search. No simulator operations, commits, or pushes were performed for this subtask.
