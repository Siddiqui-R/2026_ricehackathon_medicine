// Purpose: Extract reviewable text while retaining original document bytes and page mapping.
// Inputs: A security-scoped file URL or image bytes within configured limits.
// Outputs: ImportedDocument text, warnings, page mapping and preserved original data.
// Side effects: Reads files and runs bounded on-device PDF/image/OCR work; no AI or app-state writes.

import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

// MARK: - Reviewable extraction value
// Preserve original bytes alongside extracted text; warnings explicitly record uncertainty.
struct ImportedDocument: Sendable {
    let filename: String
    let mimeType: String
    let data: Data
    let text: String
    let warnings: [String]
    let pageCount: Int
    let pageTexts: [String]

    init(
        filename: String, mimeType: String, data: Data, text: String,
        warnings: [String], pageCount: Int, pageTexts: [String] = []
    ) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.text = text
        self.warnings = warnings
        self.pageCount = pageCount
        self.pageTexts = pageTexts
    }
}

// MARK: - Intake failures
// Reject unreadable, unsupported or excessive input without inventing extracted text.
enum DocumentImportError: LocalizedError {
    case notLocalFile, emptyFile, tooLarge, unsupportedType, unreadableFile
    case invalidPDF, lockedPDF, tooManyPages, invalidImage, imageTooLarge, invalidText

    var errorDescription: String? {
        switch self {
        case .notLocalFile: return "Choose a document from Files or a photo on this device."
        case .emptyFile: return "This file is empty. Choose a file that contains a document."
        case .tooLarge:
            return "This file exceeds the 16 MB import limit. Export a smaller copy and try again."
        case .unsupportedType:
            return "This file type is not supported. Choose a PDF, plain text file, JPEG, PNG, or HEIC image."
        case .unreadableFile:
            return "This file could not be read. Download it in Files first, then try again."
        case .invalidPDF:
            return "This PDF is damaged or contains no readable pages. Export a new PDF and try again."
        case .lockedPDF:
            return "This PDF is password-protected. Unlock it and export a copy before importing."
        case .tooManyPages: return "This PDF exceeds the 30-page limit. Split it into smaller documents."
        case .invalidImage: return "This image could not be opened. Export it as JPEG or PNG and try again."
        case .imageTooLarge: return "This image exceeds 40 million pixels. Resize or export a smaller copy."
        case .invalidText:
            return "This text file could not be decoded. Save it as UTF-8 or UTF-16 plain text."
        }
    }
}

/// One service instance serializes memory-intensive work away from the main actor.
// MARK: - On-device extraction boundary
// Bound bytes, page count, pixel count and text output before expensive operations.
actor DocumentImportService {
    static let maximumBytes = 16 * 1_024 * 1_024
    static let maximumPages = 30
    static let maximumOCRPages = 10
    static let maximumImagePixels = 40_000_000
    static let maximumOCREdge = 2_600
    static let maximumTextCharacters = 200_000

    func ingest(url: URL) async throws -> ImportedDocument {
        guard url.isFileURL else { throw DocumentImportError.notLocalFile }
        try Task.checkCancellation()
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        // A false security-scope result is normal for app-owned files, so still try reading.
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            readResult = Result { try Self.readBoundedData(at: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw DocumentImportError.unreadableFile }
        let data = try readResult.get()
        let filename = Self.safeFilename(url.lastPathComponent)
        let type = UTType(filenameExtension: url.pathExtension)
        if data.starts(with: Data("%PDF-".utf8)) || type?.conforms(to: .pdf) == true {
            return try extractPDF(data: data, filename: filename)
        }
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        let hasImageType = imageSource.flatMap { CGImageSourceGetType($0) } != nil
        if hasImageType || type?.conforms(to: .image) == true {
            return try extractImage(data: data, filename: filename)
        }
        if type?.conforms(to: .plainText) == true
            || ["txt", "text", "md"].contains(url.pathExtension.lowercased())
        {
            return try extractPlainText(data: data, filename: filename)
        }
        throw DocumentImportError.unsupportedType
    }

    func ingest(imageData: Data, filename: String) async throws -> ImportedDocument {
        try Task.checkCancellation()
        try Self.validateData(imageData)
        return try extractImage(data: imageData, filename: Self.safeFilename(filename))
    }

    private static func readBoundedData(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw DocumentImportError.unreadableFile }
        if let size = values.fileSize, size > maximumBytes { throw DocumentImportError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let remaining = maximumBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(1_024 * 1_024, remaining)), !chunk.isEmpty else {
                break
            }
            data.append(chunk)
            if data.count > maximumBytes { throw DocumentImportError.tooLarge }
        }
        try validateData(data)
        return data
    }

    private static func validateData(_ data: Data) throws {
        guard !data.isEmpty else { throw DocumentImportError.emptyFile }
        guard data.count <= maximumBytes else { throw DocumentImportError.tooLarge }
    }

    private static func safeFilename(_ filename: String) -> String {
        let leaf =
            filename.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)
            ?? "document"
        let cleaned = leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "document" : String(result.prefix(180))
    }

    // MARK: - Text-file decoding
    // Accept supported Unicode encodings and reject binary control characters before producing source text.
    private nonisolated func extractPlainText(data: Data, filename: String) throws -> ImportedDocument {
        let decoded: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            decoded = String(data: data, encoding: .utf16)
        } else {
            decoded = String(data: data, encoding: .utf8)
        }
        guard let decoded, !decoded.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw DocumentImportError.invalidText
        }
        let illegal = decoded.unicodeScalars.filter {
            CharacterSet.controlCharacters.contains($0) && ![9, 10, 13].contains($0.value)
        }.count
        guard illegal == 0 else { throw DocumentImportError.invalidText }
        let cleaned = decoded.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        var warnings: [String] = []
        var remaining = Self.maximumTextCharacters
        let text = limitedText(cleaned, remaining: &remaining, warnings: &warnings)
        if text.isEmpty {
            warnings.append("No readable text was found. Review the original and enter text manually.")
        }
        return ImportedDocument(
            filename: filename, mimeType: "text/plain", data: data,
            text: text, warnings: warnings, pageCount: 1, pageTexts: [text])
    }

    // MARK: - Image OCR
    // Downsample for recognition while retaining the original data and explicit OCR warnings.
    private nonisolated func extractImage(data: Data, filename: String) throws -> ImportedDocument {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0
        else {
            throw DocumentImportError.invalidImage
        }
        let image = try downsample(source)
        var warnings = [Self.ocrReviewWarning]
        if CGImageSourceGetCount(source) > 1 {
            warnings.append(
                "Only the first image frame was read. The original file retains all frames; review it for additional content."
            )
        }
        let result = try recognize(image)
        warnings.append(contentsOf: result.warnings)
        var remaining = Self.maximumTextCharacters
        let text = limitedText(result.text, remaining: &remaining, warnings: &warnings)
        if text.isEmpty {
            warnings.append(
                "No readable text was found in this image. Review the original and enter text manually or scan it again."
            )
        }
        let mimeType =
            CGImageSourceGetType(source).flatMap { UTType($0 as String)?.preferredMIMEType }
            ?? "application/octet-stream"
        return ImportedDocument(
            filename: filename, mimeType: mimeType, data: data,
            text: text, warnings: warnings, pageCount: 1, pageTexts: [text])
    }

    private nonisolated func downsample(_ source: CGImageSource) throws -> CGImage {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width.isFinite, height.isFinite, width > 0, height > 0
        else { throw DocumentImportError.invalidImage }
        guard width * height <= Double(Self.maximumImagePixels) else {
            throw DocumentImportError.imageTooLarge
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumOCREdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DocumentImportError.invalidImage
        }
        return image
    }

    // MARK: - PDF page extraction
    // Prefer embedded text on text-only pages, OCR raster-bearing or weak pages, and keep one mapping slot per original page.
    private nonisolated func extractPDF(data: Data, filename: String) throws -> ImportedDocument {
        guard let document = PDFDocument(data: data) else { throw DocumentImportError.invalidPDF }
        guard !document.isLocked else { throw DocumentImportError.lockedPDF }
        guard document.pageCount > 0 else { throw DocumentImportError.invalidPDF }
        guard document.pageCount <= Self.maximumPages else { throw DocumentImportError.tooManyPages }
        var pageTexts: [String] = []
        var warnings: [String] = []
        var ocrCount = 0
        var remaining = Self.maximumTextCharacters
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard remaining > 0 else {
                pageTexts.append("")
                if !warnings.contains(Self.textLimitWarning) { warnings.append(Self.textLimitWarning) }
                continue
            }
            let pageText: String = try autoreleasepool {
                guard let page = document.page(at: index) else {
                    warnings.append(
                        "Page \(index + 1) could not be opened. Review that page in the original.")
                    return ""
                }
                let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let mayContainRasterText = Self.hasRasterOrUninspectedContent(page)
                if embedded.count >= 20 && !mayContainRasterText { return embedded }
                guard ocrCount < Self.maximumOCRPages else {
                    warnings.append(
                        "Page \(index + 1) needs OCR beyond the 10-page OCR limit. Review this page or import a smaller PDF."
                    )
                    return embedded
                }
                ocrCount += 1
                if !warnings.contains(Self.ocrReviewWarning) { warnings.append(Self.ocrReviewWarning) }
                guard let image = rasterize(page) else {
                    warnings.append(
                        "Page \(index + 1) could not be rendered for text recognition. Review the original.")
                    return embedded
                }
                let result = try recognize(image)
                warnings.append(contentsOf: result.warnings.map { "Page \(index + 1): \($0)" })
                if result.text.isEmpty {
                    warnings.append(
                        "No readable text was found on page \(index + 1). Review the original and add any missing text."
                    )
                }
                if !embedded.isEmpty && mayContainRasterText {
                    warnings.append(
                        "Page \(index + 1) mixes embedded text with graphics. Recognized text was added after embedded text and may repeat it; review the complete original page."
                    )
                }
                return Self.mergeRecognizedText(embedded: embedded, recognized: result.text)
            }
            pageTexts.append(limitedText(pageText, remaining: &remaining, warnings: &warnings))
        }
        let text = pageTexts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        if text.isEmpty {
            warnings.append(
                "No readable text was extracted from this PDF. The original is preserved for manual review.")
        }
        return ImportedDocument(
            filename: filename, mimeType: "application/pdf", data: data, text: text,
            warnings: warnings, pageCount: document.pageCount, pageTexts: pageTexts)
    }

    // Inspect actual painting operations, including inline images. A Form XObject is treated
    // conservatively: it can contain nested raster text. Unknown/unreadable content also needs review.
    private nonisolated static func hasRasterOrUninspectedContent(_ page: PDFPage) -> Bool {
        guard let pageRef = page.pageRef, let operators = CGPDFOperatorTableCreate() else { return true }
        let content = CGPDFContentStreamCreateWithPage(pageRef)
        CGPDFOperatorTableSetCallback(operators, "BI") { _, info in
            info?.assumingMemoryBound(to: Bool.self).pointee = true
        }
        CGPDFOperatorTableSetCallback(operators, "Do") { scanner, info in
            guard let flag = info?.assumingMemoryBound(to: Bool.self) else { return }
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                let object = CGPDFContentStreamGetResource(
                    CGPDFScannerGetContentStream(scanner), "XObject", name)
            else {
                flag.pointee = true
                return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream else {
                flag.pointee = true
                return
            }
            var subtype: UnsafePointer<CChar>?
            guard let dictionary = CGPDFStreamGetDictionary(stream),
                CGPDFDictionaryGetName(dictionary, "Subtype", &subtype),
                let subtype
            else {
                flag.pointee = true
                return
            }
            if ["Image", "Form"].contains(String(cString: subtype)) { flag.pointee = true }
        }
        var requiresOCR = false
        let scanned = withUnsafeMutablePointer(to: &requiresOCR) { flag in
            CGPDFScannerScan(CGPDFScannerCreate(content, operators, flag))
        }
        return requiresOCR || !scanned
    }

    private nonisolated static func mergeRecognizedText(embedded: String, recognized: String) -> String {
        if embedded.isEmpty { return recognized }
        let known = Set(
            embedded.components(separatedBy: .newlines).map {
                $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            })
        let additional = recognized.components(separatedBy: .newlines).filter {
            !known.contains($0.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return additional.isEmpty ? embedded : embedded + "\n" + additional
    }

    // MARK: - Bounded PDF rasterization
    // Honor page rotation and cap the recognition image edge to limit memory use.
    private nonisolated func rasterize(_ page: PDFPage) -> CGImage? {
        guard let pdfPage = page.pageRef else { return nil }
        let bounds = pdfPage.getBoxRect(.cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let rotated = abs(pdfPage.rotationAngle) % 180 == 90
        let pageWidth = rotated ? bounds.height : bounds.width
        let pageHeight = rotated ? bounds.width : bounds.height
        let scale = CGFloat(Self.maximumOCREdge) / max(pageWidth, pageHeight)
        let width = max(1, Int((pageWidth * scale).rounded()))
        let height = max(1, Int((pageHeight * scale).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(
            pdfPage.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(pdfPage)
        return context.makeImage()
    }

    // MARK: - Vision recognition
    // Keep original recognized wording, surface low confidence, and propagate cancellation.
    private nonisolated func recognize(_ image: CGImage) throws -> (text: String, warnings: [String]) {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            let text = candidates.map(\.string).joined(separator: "\n").trimmingCharacters(
                in: .whitespacesAndNewlines)
            let warnings =
                candidates.contains(where: { $0.confidence < 0.8 })
                ? [
                    "Some recognized text has low confidence. Check numbers, dates, names, and medication details against the original."
                ] : []
            return (text, warnings)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (
                "",
                [
                    "Text recognition did not complete on this device. Review the source and enter text manually."
                ]
            )
        }
    }

    // MARK: - Shared text budget
    // Consume the remaining character budget and warn when original content exceeds extracted output.
    private nonisolated func limitedText(_ text: String, remaining: inout Int, warnings: inout [String])
        -> String
    {
        if text.count <= remaining {
            remaining -= text.count
            return text
        }
        let prefix = String(text.prefix(remaining))
        remaining = 0
        if !warnings.contains(Self.textLimitWarning) { warnings.append(Self.textLimitWarning) }
        return prefix
    }

    private static let ocrReviewWarning =
        "Text was recognized on this device with OCR and may contain mistakes or omissions. Review it against the original before using it for an appointment."
    private static let textLimitWarning =
        "Text extraction stopped at 200,000 characters. The complete original is preserved; review any remaining content."
}
