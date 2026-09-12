// Purpose: Quote bounded complete source lines without changing values or source whitespace.
// Inputs: Original text, optional explicit fictional provenance and a selected line offset.
// Outputs: An exact source span plus a separate omission notice.
// Side effects: None; full original text and persisted records remain unchanged.

import Foundation

// MARK: - Source spans and honest preview limits
struct SourceExcerpt {
    let text: String
    let omitted: Bool

    var notice: String? {
        guard omitted else { return nil }
        return text.isEmpty
            ? "No complete source line fits this preview. Open the original or full source text to review it."
            : "This is a selected passage. Open the original or full source text for the omitted content."
    }

    // Only explicitly fictional records bearing the known wrapper may discard fixture metadata.
    static func sourceText(_ text: String, isDemo: Bool = false) -> String {
        let lines = contentLines(text)
        guard isDemo,
            lines.first?.trimmingCharacters(in: .whitespaces)
                == "SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD"
        else { return text }
        let metadata = lines.prefix(10).last { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return value.hasPrefix("Source date:") || value.hasPrefix("Week ending:")
        }
        let trailer = lines.last { $0.hasPrefix("Invented for Reva software demonstration.") }
        let start = metadata?.endIndex ?? text.startIndex
        let end = trailer?.startIndex ?? text.endIndex
        guard start < end else { return text }
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contentLines(_ text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // Complete lines prevent a numeric token or its same-line unit from being cut in half.
    // If a single line exceeds the budget, show an omission notice instead of a misleading quote.
    static func passage(_ source: String, startLine: Int = 0) -> SourceExcerpt {
        let lines = contentLines(source)
        guard !lines.isEmpty else { return SourceExcerpt(text: "", omitted: false) }
        let start = min(max(0, startLine), lines.count - 1)
        let lower = lines[start].startIndex
        var upper = lower
        for line in lines.dropFirst(start).prefix(24) {
            guard source[lower..<line.endIndex].count <= 1800 else { break }
            upper = line.endIndex
        }
        return SourceExcerpt(
            text: String(source[lower..<upper]), omitted: start > 0 || upper != lines.last!.endIndex)
    }
}
