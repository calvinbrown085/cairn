import Foundation
import PDFKit

/// Pulls what a `Post` needs out of a PDF's own bytes: page count, a
/// title/author from its document metadata (falling back to the shared
/// file's name), and its text.
///
/// The text feeds straight into `Post.searchText` via `applyPDF(...)` — the
/// same field the rest of search already reads for a web article, so search
/// gains no second path for a PDF.
enum PDFImportService {
    struct Result {
        var title: String
        var author: String?
        var pageCount: Int
        var text: String
    }

    /// Pure and safe to call off the main actor. Returns `nil` only when the
    /// bytes don't parse as a PDF at all. A PDF with little or no extractable
    /// text — a scanned page, say — is still a valid result; `text` is simply
    /// short or empty, and the reader is still readable because PDFKit
    /// renders the page image regardless of whether any text layer exists.
    static func extract(data: Data, fallbackTitle: String) -> Result? {
        guard let document = PDFDocument(data: data) else { return nil }

        let attributes = document.documentAttributes
        let rawTitle = (attributes?[PDFDocumentAttribute.titleAttribute] as? String)?.squeezed
        let rawAuthor = (attributes?[PDFDocumentAttribute.authorAttribute] as? String)?.squeezed

        return Result(
            title: (rawTitle?.isEmpty == false) ? rawTitle! : fallbackTitle,
            author: (rawAuthor?.isEmpty == false) ? rawAuthor : nil,
            pageCount: document.pageCount,
            text: document.string ?? ""
        )
    }
}
