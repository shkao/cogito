import Foundation
import PDFKit

/// Extracts plain text from PDFKit documents for use as LLM prompt context.
/// All methods are stateless and safe to call from any actor.
struct PDFTextExtractor {

    static func text(from page: PDFPage) -> String? {
        guard let raw = page.string, !raw.isEmpty else { return nil }
        return normalize(raw)
    }

    static func text(from document: PDFDocument, pages: Range<Int>) -> String {
        let clamped = max(0, pages.lowerBound) ..< min(document.pageCount, pages.upperBound)
        return clamped.compactMap { index -> String? in
            guard let page = document.page(at: index) else { return nil }
            return text(from: page)
        }.joined(separator: "\n\n")
    }

    /// Returns text from a window of pages around `centerPage`.
    /// A typical PDF page is ~500-800 tokens; default radius of 3 gives ~3,500-5,600 tokens.
    static func contextWindow(document: PDFDocument, centerPage: Int, radius: Int = 3) -> String {
        text(from: document, pages: (centerPage - radius) ..< (centerPage + radius + 1))
    }

    private static func normalize(_ text: String) -> String {
        // Collapse runs of blank lines to a single blank line.
        var result: [String] = []
        var lastWasBlank = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !lastWasBlank { result.append("") }
                lastWasBlank = true
            } else {
                result.append(trimmed)
                lastWasBlank = false
            }
        }
        return result.joined(separator: "\n")
    }
}
