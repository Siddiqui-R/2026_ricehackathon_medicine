// Purpose: Lay out a reviewable visit report as a paginated local PDF.
// Inputs: Title, subtitle, source sections and citation labels within export limits.
// Outputs: A complete PDF file URL or an explicit validation/layout error.
// Side effects: Writes one temporary export; failed output is removed.

import CoreText
import UIKit

// MARK: - Export section value
// Supply display content without introducing persistence or citation lookup inside the renderer.
struct PDFSection: Sendable {
    let title: String
    let body: String
}

// MARK: - Export failures
// Reject empty titles, excessive content and non-progressing layout.
enum ReportPDFError: LocalizedError {
    case emptyTitle, tooMuchContent, layoutFailed

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Add a report title before exporting."
        case .tooMuchContent:
            return "This report is too long to export. Shorten its text or source list and try again."
        case .layoutFailed:
            return "This report could not be formatted as a PDF. Try exporting a shorter report."
        }
    }
}

// MARK: - PDF layout and file output
// Measure exact page ranges before writing and enforce the page/character limits.
@MainActor
enum ReportPDFRenderer {
    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let bodyRect = CGRect(x: 44, y: 65, width: 524, height: 651)
    private static let maximumCharacters = 200_000
    private static let maximumPages = 100

    static func render(title: String, subtitle: String, sections: [PDFSection], sources: [String]) throws
        -> URL
    {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReportPDFError.emptyTitle
        }
        let totalCount =
            title.utf16.count + subtitle.utf16.count
            + sections.reduce(0) { $0 + $1.title.utf16.count + $1.body.utf16.count }
            + sources.reduce(0) { $0 + $1.utf16.count }
        guard totalCount <= maximumCharacters, sections.count <= 200, sources.count <= 500 else {
            throw ReportPDFError.tooMuchContent
        }
        let content = makeContent(title: title, subtitle: subtitle, sections: sections, sources: sources)
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        let textPath = CGPath(
            rect: CGRect(
                x: bodyRect.minX, y: page.height - bodyRect.maxY,
                width: bodyRect.width, height: bodyRect.height), transform: nil)
        // Determine exact page ranges first; this bounds work and allows Page x of y footers.
        var ranges: [CFRange] = []
        var position = 0
        while position < content.length {
            guard ranges.count < maximumPages else { throw ReportPDFError.tooMuchContent }
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: position, length: 0), textPath, nil)
            var length = CTFrameGetVisibleStringRange(frame).length
            guard length > 0 else { throw ReportPDFError.layoutFailed }
            // Avoid leaving a section heading alone at the foot of a page.
            if position + length < content.length {
                var effectiveRange = NSRange(location: 0, length: 0)
                let heading =
                    content.attribute(
                        .revaPDFHeading, at: position + length - 1, effectiveRange: &effectiveRange) as? Bool
                if heading == true, effectiveRange.location > position {
                    length = effectiveRange.location - position
                }
            }
            ranges.append(CFRange(location: position, length: length))
            position += length
        }
        guard !ranges.isEmpty else { throw ReportPDFError.layoutFailed }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RevaExports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let url = directory.appendingPathComponent("Reva-Report-\(UUID().uuidString).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Reva · on-device report export",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        do {
            try renderer.writePDF(to: url) { context in
                for (index, range) in ranges.enumerated() {
                    context.beginPage()
                    drawPageChrome(
                        context.cgContext, pageNumber: index + 1, pageCount: ranges.count,
                        sourceCount: sources.count)
                    context.cgContext.saveGState()
                    // UIKit text drawing can leave a flipped text matrix; Core Text needs identity.
                    context.cgContext.textMatrix = .identity
                    context.cgContext.translateBy(x: 0, y: page.height)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    let frame = CTFramesetterCreateFrame(framesetter, range, textPath, nil)
                    CTFrameDraw(frame, context.cgContext)
                    context.cgContext.restoreGState()
                }
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    // MARK: - Attributed report content
    // Build sections and citation labels with heading metadata used to avoid orphan headings.
    private static func makeContent(
        title: String, subtitle: String, sections: [PDFSection], sources: [String]
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")
        append(title, font: .systemFont(ofSize: 25, weight: .bold), color: heart, spacingAfter: 9, to: text)
        if !subtitle.isEmpty {
            append(subtitle, font: .systemFont(ofSize: 11), color: .darkGray, spacingAfter: 18, to: text)
        }
        for section in sections {
            if !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append(
                    section.title, font: .systemFont(ofSize: 14, weight: .semibold), color: heart,
                    spacingBefore: 10, spacingAfter: 6, heading: true, to: text)
            }
            append(
                section.body.isEmpty ? "No information entered." : section.body,
                font: .systemFont(ofSize: 11), color: .black, spacingAfter: 10, to: text)
        }
        append(
            "Sources", font: .systemFont(ofSize: 14, weight: .semibold), color: heart,
            spacingBefore: 12, spacingAfter: 6, heading: true, to: text)
        if sources.isEmpty {
            append(
                "No source citations were supplied for this export. Review the report before relying on it.",
                font: .systemFont(ofSize: 10), color: .darkGray, spacingAfter: 7, to: text)
        } else {
            for (index, source) in sources.enumerated() {
                append(
                    "\(index + 1). \(source)", font: .systemFont(ofSize: 10), color: .darkGray,
                    spacingAfter: 7, to: text)
            }
        }
        return text
    }

    private static func append(
        _ string: String, font: UIFont, color: UIColor, spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat, heading: Bool = false, to text: NSMutableAttributedString
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        paragraph.lineBreakMode = .byWordWrapping
        text.append(
            NSAttributedString(
                string: string + "\n",
                attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
                    .revaPDFHeading: heading,
                ]))
    }

    // MARK: - Page header and footer
    // Render stable navigation text and page counts without changing source content.
    private static func drawPageChrome(
        _ context: CGContext, pageNumber: Int, pageCount: Int, sourceCount: Int
    ) {
        let headerStyle: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: heart,
        ]
        ("REVA  /  VISIT PREPARATION" as NSString).draw(
            in: CGRect(x: 44, y: 32, width: 524, height: 16), withAttributes: headerStyle)
        context.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 44, y: 733))
        context.addLine(to: CGPoint(x: 568, y: 733))
        context.strokePath()
        let footer =
            sourceCount > 0
            ? "Source-based preparation · \(sourceCount) citation\(sourceCount == 1 ? "" : "s") in Sources · Review originals."
            : "Prepared on device · No source citations supplied · Review before use."
        let style: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray,
        ]
        (footer as NSString).draw(in: CGRect(x: 44, y: 742, width: 418, height: 25), withAttributes: style)
        let right = NSMutableParagraphStyle()
        right.alignment = .right
        ("\(pageNumber) / \(pageCount)" as NSString).draw(
            in: CGRect(x: 480, y: 742, width: 88, height: 20),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray,
                .paragraphStyle: right,
            ])
    }

    private static var heart: UIColor {
        UIColor(red: 184 / 255.0, green: 66 / 255.0, blue: 80 / 255.0, alpha: 1)
    }
}

private extension NSAttributedString.Key {
    static let revaPDFHeading = NSAttributedString.Key("RevaPDFHeading")
}
