// Purpose: Exercise the actual PDFKit/Vision import service against synthetic mixed-content PDFs.
// Inputs: Locally generated embedded headers plus rasterized fictional body text.
// Outputs: Assertions for body extraction, retained embedded text, warnings, page mapping and OCR limits.
// Side effects: Writes temporary synthetic PDFs; runs bounded local Vision OCR. No network or providers.

import CoreGraphics
import CoreText
import Foundation
import PDFKit

@main
struct DocumentImportChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RevaDocumentCheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mixed = directory.appendingPathComponent("mixed-content.pdf")
        try makePDF(at: mixed, rasterPages: 1, textOnlyLastPage: true)
        if CommandLine.arguments.count > 1 {
            try Data(contentsOf: mixed).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let pdf = PDFDocument(url: mixed)!
        precondition(pdf.page(at: 0)!.string!.contains("Received 2026-09-12"))
        precondition(
            !pdf.page(at: 0)!.string!.contains("100 mg"),
            "The body must be raster text, not an embedded font.")
        let importer = DocumentImportService()
        let result = try await importer.ingest(url: mixed)
        precondition(result.pageCount == 2 && result.pageTexts.count == 2)
        precondition(
            result.pageTexts[0].contains("100 mg"),
            "Mixed page must include the image body, not just the header.")
        precondition(result.pageTexts[0].contains("No fracture seen"))
        precondition(
            result.pageTexts[0].contains("Received 2026-09-12"), "Preserve embedded wording alongside OCR.")
        precondition(result.pageTexts[1].contains("Second page embedded source"))
        precondition(result.warnings.contains { $0.contains("OCR") && $0.contains("Review") })
        precondition(result.warnings.contains { $0.contains("Page 1 mixes") })
        precondition(!result.warnings.contains { $0.contains("Page 2 mixes") })
        print(
            "PASS mixed PDF: raster dose/negation plus embedded header, original page mapping and review warnings"
        )

        for (embedded, recognized) in [
            ("Dose 5", "Dose 50"), ("Dose 50", "Dose 5"), ("Value 10", "Value 70"),
        ] {
            let merged = DocumentImportService.mergeRecognizedText(embedded: embedded, recognized: recognized)
            let lines = merged.split(separator: "\n").map(String.init)
            precondition(
                lines.contains(embedded) && lines.contains(recognized),
                "Distinct numeric lines must survive deduplication")
        }
        precondition(
            DocumentImportService.mergeRecognizedText(embedded: "Dose 5", recognized: "Dose 5\nOther source")
                == "Dose 5\nOther source")
        print(
            "PASS numeric source disagreement: complete-line deduplication retains differing values and prefixes"
        )

        let bounded = directory.appendingPathComponent("ocr-bound.pdf")
        try makePDF(at: bounded, rasterPages: 11, textOnlyLastPage: false, lateLowTextScan: true)
        let limited = try await importer.ingest(url: bounded)
        precondition(limited.pageTexts.count == 11)
        precondition(limited.pageTexts.filter { $0.contains("100 mg") }.count == 10)
        precondition(limited.pageTexts[8].contains("100 mg"))
        precondition(!limited.pageTexts[9].contains("100 mg"))
        precondition(limited.pageTexts[9].contains("Received 2026-09-12"))
        precondition(limited.pageTexts[10].contains("100 mg"), "Late low-text scan must retain its OCR slot")
        precondition(limited.warnings.contains { $0.contains("Page 10") && $0.contains("10-page OCR limit") })
        precondition(
            !limited.warnings.contains { $0.contains("Page 11") && $0.contains("10-page OCR limit") })
        print(
            "PASS OCR priority/cap: late low-text page 11 recognized after ten graphical headers; page 10 retains header and review warning"
        )
    }

    private static func drawLine(_ text: String, in context: CGContext, y: CGFloat, size: CGFloat = 26) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        context.textPosition = CGPoint(x: 24, y: y)
        CTLineDraw(
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)),
            context)
    }

    private static func makePDF(
        at url: URL, rasterPages: Int, textOnlyLastPage: Bool, lateLowTextScan: Bool = false
    ) throws {
        let bitmap = CGContext(
            data: nil, width: 1100, height: 1200, bitsPerComponent: 8, bytesPerRow: 4400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1100, height: 1200))
        drawLine("SYNTHETIC MIXED PAGE", in: bitmap, y: 1060, size: 48)
        drawLine("Dose: 100 mg", in: bitmap, y: 900, size: 48)
        drawLine("No fracture seen", in: bitmap, y: 740, size: 48)
        drawLine("Fictional OCR regression only", in: bitmap, y: 580, size: 48)
        let image = bitmap.makeImage()!
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(url: url as CFURL)!
        let context = CGContext(consumer: consumer, mediaBox: &media, nil)!
        for index in 0..<rasterPages {
            context.beginPDFPage(nil)
            let header =
                lateLowTextScan && index == rasterPages - 1
                ? "Fax stamp" : "Received 2026-09-12 14:03 Page \(index + 1) - Synthetic"
            drawLine(header, in: context, y: 750, size: 14)
            context.draw(image, in: CGRect(x: 31, y: 80, width: 550, height: 600))
            context.endPDFPage()
        }
        if textOnlyLastPage {
            context.beginPDFPage(nil)
            drawLine("Second page embedded source remains complete.", in: context, y: 650, size: 18)
            context.endPDFPage()
        }
        context.closePDF()
    }
}
