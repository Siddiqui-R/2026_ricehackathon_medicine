#!/usr/bin/env python3
"""Purpose: Run native device policy regressions without requiring Apple device frameworks.
Inputs: Unchanged production PDF/save helpers and exact AudioRecorder transition methods.
Outputs: Compiled behavioral assertions for source preservation and recording failure/retry paths.
Side effects: Writes build/optimization-checks and synthetic temporary files; no microphone or network.
Boundary: Audio classes and observation are test doubles; PDFKit/Vision, AVFoundation and SwiftUI need Xcode.
"""

from pathlib import Path
import re

from check_optimization_fixes import BUILD, ROOT, configure_compiler, run_suite


# MARK: - Extract exact transition code with checked declaration boundaries
# Fail when an owned declaration moves or changes shape; never substitute a reimplemented method.
def one(source: str, pattern: str, name: str) -> str:
    matches = re.findall(pattern, source, flags=re.MULTILINE | re.DOTALL)
    if len(matches) != 1:
        raise SystemExit(f"Expected exactly one production {name}; adapt this harness before running checks.")
    return matches[0]


def recorder_transitions() -> Path:
    source = (ROOT / "apps/ios/Reva/Device/AudioServices.swift").read_text(encoding="utf-8")
    recorder = one(
        source, r"^final class AudioRecorder:.*?\n(.*?)^// MARK: - Original audio playback", "AudioRecorder body")
    fields = one(recorder, r"(    /// True while.*?)(?=    override init\(\))", "recorder state")
    methods = []
    for name in ["resume", "finish", "cancel", "cleanUpDraft"]:
        methods.append(one(recorder, rf"^    (?:private )?func {name}\(\).*?^    \}}", f"{name} method"))
    errors = one(source, r"^enum DeviceAudioError: LocalizedError \{.*?^\}", "device audio errors")
    # Notification setup, permission, timers and real codec behavior are outside this focused harness.
    setup = """
    init(testURL: URL) {
        recorder = AVAudioRecorder()
        ownedDraftURL = testURL
        audioURL = testURL
        isRecording = true
    }
    private func beginTicker() {}
"""
    destination = BUILD / "device-transition-inputs/AudioRecorder+Transitions.swift"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        "// Generated: exact production recorder fields/errors/transitions with test-only initialization.\n"
        "import Foundation\n" + errors + "\n@MainActor final class AudioRecorder {\n"
        + fields + setup + "\n".join(methods) + "\n}\n", encoding="utf-8")
    return destination


# MARK: - Exercise the actual intake-origin reset with plain observable-state stand-ins
def import_transitions() -> Path:
    source = (ROOT / "apps/ios/Reva/Features/Records/AddRecordView.swift").read_text(encoding="utf-8")
    method = one(source, r"^    private func setImported\(.*?^    \}", "setImported method")
    document_source = (ROOT / "apps/ios/Reva/Device/DocumentImportService.swift").read_text(encoding="utf-8")
    document = one(document_source, r"^struct ImportedDocument: Sendable \{.*?^\}", "imported document value")
    destination = BUILD / "device-transition-inputs/AddRecordReview+Transitions.swift"
    destination.write_text(
        "// Generated: exact production import value/reset; SwiftUI observation is outside this harness.\n"
        "import Foundation\n" + document + "\nfinal class AddRecordReview {\n"
        '    var imported: ImportedDocument?\n    var kind = "Notes"\n    var title = ""\n'
        '    var text = ""\n    var verified = false\n'
        "    func importDocument(_ item: ImportedDocument, scanned: Bool = false) {\n"
        "        setImported(item, scanned: scanned)\n    }\n" + method + "\n}\n", encoding="utf-8")
    return destination


# MARK: - Exercise the bounded production PDF loop with deterministic pages and OCR
def pdf_transitions() -> Path:
    source = (ROOT / "apps/ios/Reva/Device/DocumentImportService.swift").read_text(encoding="utf-8")
    extraction = one(source, r"^    private nonisolated func extractPDF\(.*?^    \}", "PDF extraction method")
    limiter = one(source, r"^    private nonisolated func limitedText\(.*?^    \}", "text budget method")
    errors = one(source, r"^enum DocumentImportError: LocalizedError \{.*?^\}", "document import errors")
    declarations = [one(source, rf"^    static let {name} = [^\n]+$", name)
                    for name in ["maximumPages", "maximumOCRPages", "maximumTextCharacters"]]
    declarations += [one(source, rf"^    private static let {name} =\n[^\n]+$", name)
                     for name in ["ocrReviewWarning", "textLimitWarning"]]
    adapters = """
    func importPDF(_ data: Data) throws -> ImportedDocument {
        try extractPDF(data: data, filename: "fictional-mixed.pdf")
    }
    private nonisolated func rasterize(_ page: PDFPage) -> PDFPage? {
        page.canRender ? page : nil
    }
    private nonisolated func recognize(_ page: PDFPage) throws -> (text: String, warnings: [String]) {
        PDFDocument.recognitionCount += 1
        return (page.recognizedText, [])
    }
"""
    destination = BUILD / "device-transition-inputs/PDFImport+Transitions.swift"
    destination.write_text(
        "// Generated: exact bounded PDF extraction/text budget; PDFKit/Vision are test doubles.\n"
        "import Foundation\n" + errors + "\nactor PDFImportHarness {\n"
        + "\n".join(declarations) + adapters + extraction + "\n" + limiter + "\n}\n", encoding="utf-8")
    return destination


# MARK: - Compile and run the focused policies together
def main() -> None:
    transitions = recorder_transitions()
    intake = import_transitions()
    pdf = pdf_transitions()
    run_suite(configure_compiler(), "DeviceChecks", [
        "Core/Models.swift", "Core/SymptomEntry.swift", "Device/PDFPageText.swift",
        "Device/RecordingSaveDraft.swift", str(transitions), str(intake), str(pdf),
    ], include_audio_helper=False)


if __name__ == "__main__":
    main()
