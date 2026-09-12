// Purpose: Combine a PDF page's embedded and recognized text without dropping distinct source wording.
// Inputs: Embedded PDF text and the bounded OCR result for the same original page.
// Outputs: Preserved page text and a flag when the two representations need overlap review.
// Side effects: None; callers retain page mapping and enforce the document text budget.

// MARK: - Preserve distinct page evidence
// Remove only identical complete lines; substring prefixes may be conflicting dates, values or names.
enum PDFPageText {
    static func merge(embedded: String, recognized: String) -> (text: String, needsOverlapReview: Bool) {
        if embedded.isEmpty { return (recognized, false) }
        if recognized.isEmpty || embedded == recognized { return (embedded, false) }
        // Line boundaries prevent a value such as "Dose 5" from disappearing inside "Dose 50".
        let embeddedLines = "\n" + embedded + "\n"
        let recognizedLines = "\n" + recognized + "\n"
        if embeddedLines.contains(recognizedLines) { return (embedded, false) }
        if recognizedLines.contains(embeddedLines) { return (recognized, false) }
        return (embedded + "\n\n" + recognized, true)
    }
}
