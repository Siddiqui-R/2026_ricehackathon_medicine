// Purpose: Check native device policies using real production helpers and fictional source values.
// Inputs: PDFPageText and recording-save coordination compiled without Apple device frameworks.
// Outputs: Named passing checks or an assertion failure on lost text, identity or original bytes.
// Side effects: Recording checks write only isolated temporary files; no microphone or network access.

import Foundation

// MARK: - Platform-independent device regression checks
@main struct DeviceChecks {
    @MainActor static func main() async throws {
        checkMixedPDFText()
        try await checkPDFExtraction()
        try checkRecordingSaveRetry()
        try checkFinalizationFailure()
        checkIntakeOrigin()
    }

    // MARK: - Preserve mixed PDF source text
    // OCR can contain the embedded header or differ from it; neither path may drop distinct words.
    private static func checkMixedPDFText() {
        let header = "Received 2026-09-12 14:03 Page 1/4"
        let imageText = "Fictional patient: report intermittent dizziness on standing."
        let mixed = PDFPageText.merge(embedded: header, recognized: imageText)
        precondition(mixed.text.contains(header), "Mixed PDF must retain its embedded header")
        precondition(mixed.text.contains(imageText), "Mixed PDF must retain the image's OCR text")
        precondition(mixed.needsOverlapReview, "Distinct representations must request overlap review")

        let contained = PDFPageText.merge(embedded: header, recognized: header + "\n" + imageText)
        precondition(contained.text == header + "\n" + imageText)
        precondition(!contained.needsOverlapReview, "Exact containment must not duplicate the header")
        let repeated = PDFPageText.merge(embedded: imageText, recognized: imageText)
        precondition(repeated.text == imageText && !repeated.needsOverlapReview)
        let failedOCR = PDFPageText.merge(embedded: header, recognized: "")
        precondition(failedOCR.text == header, "OCR failure must retain available embedded text")
        let imageOnly = PDFPageText.merge(embedded: "", recognized: imageText)
        precondition(imageOnly.text == imageText && !imageOnly.needsOverlapReview)
        let differingValues = PDFPageText.merge(embedded: "Value 10", recognized: "Value 70")
        precondition(differingValues.text.contains("Value 10") && differingValues.text.contains("Value 70"))
        precondition(
            differingValues.needsOverlapReview, "Fuzzy de-duplication must not erase differing values")
        for (embedded, recognized) in [("Dose 5", "Dose 50"), ("Dose 50", "Dose 5")] {
            let numericPrefix = PDFPageText.merge(embedded: embedded, recognized: recognized)
            let lines = numericPrefix.text.split(separator: "\n")
            precondition(lines.contains("Dose 5") && lines.contains("Dose 50"))
            precondition(
                numericPrefix.needsOverlapReview, "Numeric prefixes must remain distinct with review")
        }
        let completeLine = PDFPageText.merge(embedded: "Dose 5", recognized: "Header\nDose 5\nFooter")
        precondition(completeLine.text == "Header\nDose 5\nFooter" && !completeLine.needsOverlapReview)
        print(
            "PASS RVA-05-004: mixed PDF text, complete-line overlap, failed OCR and conflicting numeric prefixes"
        )
    }

    // MARK: - Run the production PDF loop against bounded synthetic page adapters
    // This catches the old embedded-header early return without claiming Vision recognized a real image.
    private static func checkPDFExtraction() async throws {
        let header = "Received 2026-09-12 14:03 Page 1/4"
        let imageText = "Fictional image body that must appear in extracted text."
        let data = Data("Fictional source bytes; PDFKit is replaced only in this harness".utf8)
        let importer = PDFImportHarness()
        PDFDocument.pages = [PDFPage(string: header, recognizedText: imageText)]
        PDFDocument.recognitionCount = 0
        let mixed = try await importer.importPDF(data)
        precondition(PDFDocument.recognitionCount == 1, "Embedded headers must not bypass recognition")
        precondition(mixed.pageTexts.count == 1 && mixed.pageTexts[0].contains(imageText))
        precondition(mixed.pageTexts[0].contains(header) && mixed.data == data)
        precondition(mixed.warnings.contains { $0.contains("OCR") && $0.contains("Review") })

        PDFDocument.pages = (1...11).map {
            PDFPage(string: "Fictional embedded header for page \($0)", recognizedText: "Image text \($0)")
        }
        PDFDocument.recognitionCount = 0
        let bounded = try await importer.importPDF(data)
        precondition(PDFDocument.recognitionCount == 10, "Recognition must respect the existing page budget")
        precondition(bounded.pageTexts.count == 11 && bounded.pageCount == 11)
        precondition(bounded.pageTexts[10] == "Fictional embedded header for page 11")
        precondition(bounded.warnings.contains { $0.contains("Page 11") && $0.contains("10-page OCR limit") })

        let textPages = (1...10).map { index in
            let embedded = "Fictional complete embedded text on page \(index)."
            return PDFPage(string: embedded, recognizedText: embedded)
        }
        for lateHeader in ["", "Fax stamp"] {
            PDFDocument.pages = textPages + [PDFPage(string: lateHeader, recognizedText: imageText)]
            PDFDocument.recognitionCount = 0
            let lateScan = try await importer.importPDF(data)
            precondition(PDFDocument.recognitionCount == 10)
            precondition(lateScan.pageTexts.count == 11 && lateScan.pageTexts[10].contains(imageText))
            for index in 0..<10 {
                precondition(lateScan.pageTexts[index] == textPages[index].string)
            }
            precondition(
                lateScan.warnings.contains { $0.contains("Page 10") && $0.contains("10-page OCR limit") })
            precondition(
                !lateScan.warnings.contains { $0.contains("Page 11") && $0.contains("10-page OCR limit") })
        }

        PDFDocument.pages = [PDFPage(string: header, recognizedText: imageText, canRender: false)]
        PDFDocument.recognitionCount = 0
        let failedRender = try await importer.importPDF(data)
        precondition(PDFDocument.recognitionCount == 0 && failedRender.pageTexts == [header])
        precondition(failedRender.warnings.contains { $0.contains("could not be rendered") })
        print(
            "PASS RVA-05-004: production PDF loop prioritizes late scans, bounds OCR, preserves page order and warns on skipped pages"
        )
    }

    // MARK: - Retain finalized audio through metadata failures
    // Only persistence repeats; failed finalization cannot create a pending or saved recording.
    private static func checkRecordingSaveRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fictional-original.m4a")
        let original = Data("Fictional bytes for save ownership; not playable audio".utf8)
        try original.write(to: url)
        let visit = Visit(
            title: "Fictional visit", type: "Consult", provider: "Fictional clinician", clinic: "Demo",
            date: "2026-09-12T14:00:00Z", concern: "Preparation", goal: "Discuss questions")
        var draft = RecordingSaveDraft()
        var finishes = 0
        var attempts: [VisitRecording] = []
        for _ in 0..<2 {
            do {
                _ = try draft.save(
                    visit: visit,
                    finishAudio: {
                        finishes += 1
                        return (url, 12.5)
                    },
                    persist: {
                        attempts.append($0)
                        throw SyntheticDeviceFailure.persistence
                    })
                preconditionFailure("Synthetic metadata write must fail")
            } catch SyntheticDeviceFailure.persistence {}
            precondition(draft.audioURL == url)
            precondition(draft.recording == attempts.first)
            let retained = try Data(contentsOf: url)
            precondition(retained == original, "Failed metadata writes must preserve the original bytes")
        }
        let savedID = try draft.save(
            visit: visit,
            finishAudio: {
                preconditionFailure("Retry must never finalize audio a second time")
            }, persist: { attempts.append($0) })
        precondition(finishes == 1 && attempts.count == 3)
        precondition(attempts.allSatisfy { $0 == attempts[0] }, "Retries must preserve every metadata value")
        precondition(savedID == attempts[0].id && attempts[0].audioFilename == url.lastPathComponent)
        precondition(draft.recording == nil && draft.audioURL == nil)
        let retained = try Data(contentsOf: url)
        precondition(retained == original, "Successful metadata persistence must keep the original audio")

        var failedDraft = RecordingSaveDraft()
        do {
            _ = try failedDraft.save(
                visit: visit, finishAudio: { throw SyntheticDeviceFailure.finalization },
                persist: { _ in preconditionFailure("Failed finalization must not reach persistence") })
            preconditionFailure("Synthetic finalization must fail")
        } catch SyntheticDeviceFailure.finalization {}
        precondition(failedDraft.recording == nil && failedDraft.audioURL == nil)
        print(
            "PASS RVA-05-008: repeated failed save, stable metadata retry, finalize once and original retention"
        )
    }

    // MARK: - Exercise exact production recorder transitions with audio doubles
    // This verifies finish/resume/cancel control flow; AVFoundation and microphone behavior need a native run.
    @MainActor private static func checkFinalizationFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalidURL = directory.appendingPathComponent("empty-draft.m4a")
        try Data().write(to: invalidURL)
        let invalid = AudioRecorder(testURL: invalidURL)
        AVAudioPlayer.testDuration = 0
        do {
            _ = try invalid.finish()
            preconditionFailure("Empty audio must fail finalization")
        } catch DeviceAudioError.emptyRecording {}
        precondition(invalid.hasFinalizationFailure && !invalid.isRecording && !invalid.isPaused)
        precondition(FileManager.default.fileExists(atPath: invalidURL.path), "Failure retains the draft")
        invalid.resume()
        precondition(invalid.errorMessage?.contains("start a new recording") == true)
        precondition(invalid.errorMessage?.contains("one-hour") == false)
        do {
            _ = try invalid.finish()
            preconditionFailure("Terminal finalization must not be repeated")
        } catch DeviceAudioError.finalizationFailed {}
        invalid.cancel()
        precondition(!invalid.hasFinalizationFailure && !invalid.isRecording && !invalid.isPaused)
        precondition(invalid.audioURL == nil && invalid.errorMessage == nil)
        precondition(
            !FileManager.default.fileExists(atPath: invalidURL.path), "Explicit discard removes the draft")

        let validURL = directory.appendingPathComponent("finalized-original.m4a")
        let original = Data("Fictional finalized bytes, validated by the audio double only".utf8)
        try original.write(to: validURL)
        let valid = AudioRecorder(testURL: validURL)
        AVAudioPlayer.testDuration = 12.5
        let finished = try valid.finish()
        precondition(finished == validURL && !valid.hasFinalizationFailure && !valid.isRecording)
        valid.cancel()
        let retained = try Data(contentsOf: validURL)
        precondition(retained == original, "Cancel after handoff must not delete finalized originals")
        print(
            "PASS RVA-05-002: terminal failed finish, accurate resume guidance, discard/reset and original handoff"
        )
    }

    // MARK: - Keep scanner identity after PDF encoding and reset new source choices
    private static func checkIntakeOrigin() {
        let review = AddRecordReview()
        let scan = ImportedDocument(
            filename: "fictional-scan.pdf", mimeType: "application/pdf", data: Data(),
            text: "Fictional camera scan", warnings: [], pageCount: 1)
        review.importDocument(scan, scanned: true)
        precondition(review.kind == "Scan", "A camera scan remains Scan when stored as a PDF")
        review.kind = "Labs"
        review.verified = true
        review.importDocument(scan)
        precondition(
            review.kind == "Notes" && !review.verified, "A new file resets prior category and review")
        let image = ImportedDocument(
            filename: "fictional-photo.jpg", mimeType: "image/jpeg", data: Data(),
            text: "Fictional photo", warnings: [], pageCount: 1)
        review.importDocument(image)
        precondition(review.kind == "Scan", "Image intake keeps the Scan default")
        let text = ImportedDocument(
            filename: "fictional-note.txt", mimeType: "text/plain", data: Data(),
            text: "Fictional note", warnings: [], pageCount: 1)
        review.importDocument(text)
        precondition(review.kind == "Notes", "A text file must not inherit a prior scan category")
        print("PASS RVA-04-006: scanner PDF identity, image default and source-kind/review reset")
    }
}

// MARK: - Deterministic Apple-framework stand-ins
// Production transition methods are extracted verbatim; these doubles own no system audio resources.
enum SyntheticDeviceFailure: Error {
    case persistence
    case finalization
}

@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

@MainActor final class AVAudioRecorder {
    var delegate: AnyObject?
    var currentTime: TimeInterval = 0
    func stop() {}
    func record(forDuration: TimeInterval) -> Bool { true }
}

@MainActor final class AVAudioPlayer {
    static var testDuration: TimeInterval = 0
    var duration: TimeInterval { Self.testDuration }
    init(contentsOf: URL) throws {}
}

@MainActor final class AVAudioSession {
    static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    var isInputAvailable: Bool { true }
}

@MainActor final class DeviceAudioSession {
    static let shared = DeviceAudioSession()
    func activate(owner: UUID, recording: Bool) throws {}
    func release(owner: UUID) {}
}

// MARK: - Deterministic PDF and recognition stand-ins
// Each page supplies fictional embedded/OCR wording; no real rasterization or recognition occurs here.
struct PDFPage {
    let string: String?
    let recognizedText: String
    var canRender = true
}

final class PDFDocument {
    static var pages: [PDFPage] = []
    static var recognitionCount = 0
    var isLocked: Bool { false }
    var pageCount: Int { Self.pages.count }
    init?(data: Data) {}
    func page(at index: Int) -> PDFPage? { Self.pages[index] }
}

#if os(Windows)
    func autoreleasepool<Value>(invoking body: () throws -> Value) rethrows -> Value { try body() }
#endif
