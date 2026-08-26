import Foundation
import SwiftData
import Observation
import SwiftReadability

/// Turns a URL into an archived post: fetch, extract, pull the images down, save.
///
/// Runs on the main actor because it owns a `ModelContext`; the expensive parts
/// (parsing, image re-encoding) hop off it explicitly.
@MainActor
@Observable
final class ArchiveService {

    private let context: ModelContext
    private let fetcher = PageFetcher()
    private let imageArchiver = ImageArchiver()

    /// Posts currently being fetched, so the UI can show progress per row.
    private(set) var inFlight: Set<UUID> = []

    /// Below this, what came back is boilerplate rather than an article.
    /// Deliberately low: some legitimate posts really are two paragraphs.
    private static let minimumArticleWords = 40

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Entry points

    /// Saves a URL, or returns the existing post if it's already archived.
    @discardableResult
    func save(url: URL, tags: [String] = []) -> Post {
        let canonical = url.canonicalizedForArchive().absoluteString

        if let existing = findPost(canonicalURL: canonical) {
            // Re-saving something that previously failed should try again.
            if existing.state == .failed { retry(existing) }
            return existing
        }

        let post = Post(url: url)
        post.tagNames = tags
        context.insert(post)
        try? context.save()

        Task { await process(post) }
        return post
    }

    func retry(_ post: Post) {
        guard !inFlight.contains(post.id) else { return }
        post.state = .pending
        post.failureReason = nil
        Task { await process(post) }
    }

    /// Picks up everything the share extension left behind — links and PDFs
    /// both, drained through the one inbox.
    @discardableResult
    func drainSharedInbox() -> Int {
        let items = SharedInbox.drain()
        var saved = 0
        for item in items {
            switch item.kind {
            case .link:
                guard let url = URL.fromUserInput(item.url) else { continue }
                save(url: url)
                saved += 1

            case .pdf:
                guard let fileName = item.fileName else { continue }
                let fileURL = AppGroup.sharedFilesURL.appending(path: fileName)
                defer { try? FileManager.default.removeItem(at: fileURL) }
                guard savePDF(fileURL: fileURL, suggestedTitle: item.title) != nil else { continue }
                saved += 1
            }
        }
        return saved
    }

    /// Saves a PDF already sitting at `fileURL` — typically the copy the
    /// share extension left in the app group — or returns the existing post
    /// if an identical file is already archived. Returns `nil` only when the
    /// file at `fileURL` can't even be read.
    @discardableResult
    func savePDF(fileURL: URL, suggestedTitle: String?) -> Post? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let canonical = "cairn-pdf-sha256:\(Post.sha256Hex(data))"
        if let existing = findPost(canonicalURL: canonical) {
            if existing.state == .failed { retryPDF(existing) }
            return existing
        }

        let suggested = suggestedTitle?.squeezed
        let name = (suggested?.isEmpty == false) ? suggested! : fileURL.deletingPathExtension().lastPathComponent
        let post = Post(pdfNamed: name, data: data)
        context.insert(post)
        try? context.save()

        Task { await processPDF(post, data: data) }
        return post
    }

    private func retryPDF(_ post: Post) {
        guard !inFlight.contains(post.id), let data = post.pdfData else { return }
        post.state = .pending
        post.failureReason = nil
        Task { await processPDF(post, data: data) }
    }

    // MARK: - Pipeline

    func process(_ post: Post) async {
        guard let url = post.url else {
            fail(post, reason: FetchError.badURL.localizedDescription)
            return
        }
        guard !inFlight.contains(post.id) else { return }

        inFlight.insert(post.id)
        post.state = .fetching
        try? context.save()

        defer { inFlight.remove(post.id) }

        do {
            let page = try await fetcher.fetch(url)

            // Compressing the source alongside extraction keeps it off the main
            // actor too, and means a future extractor upgrade can re-derive
            // blocks from this post without a network re-fetch — see T-0007.
            async let compressedHTML = Self.compress(html: page.html)

            // Parsing a large page is CPU-bound; keep it off the main actor.
            let extracted = await Self.extract(html: page.html, url: page.finalURL)

            var content = extracted.content
            let archived = await downloadImages(for: content, referer: page.finalURL)

            // Attach each downloaded asset to its block and to the post.
            var assets: [StoredImage] = []
            for (index, result) in archived {
                guard case .image(var image) = content.blocks[index] else { continue }
                let stored = StoredImage(
                    data: result.data,
                    pixelWidth: result.width,
                    pixelHeight: result.height,
                    sourceURL: image.source
                )
                image.assetID = stored.id
                image.width = result.width
                image.height = result.height
                content.blocks[index] = .image(image)
                assets.append(stored)
            }

            // Images that failed to download would render as empty gaps.
            content.blocks.removeAll { block in
                if case .image(let image) = block { return image.assetID == nil }
                return false
            }

            for asset in assets {
                asset.post = post
                context.insert(asset)
            }

            post.apply(extracted, content: content)
            post.canonicalURLString = page.finalURL.canonicalizedForArchive().absoluteString
            post.host = Post.displayHost(for: page.finalURL)
            post.leadImageID = Self.chooseLeadImage(from: content, assets: assets, preferring: extracted.leadImageSource)
            // Kept even when extraction below turns up short: a page that reads
            // as boilerplate today may read as an article once the extractor
            // improves, and only the source makes that recoverable.
            post.originalHTMLData = await compressedHTML

            // A page that parsed but yielded almost no prose is link rot, a
            // paywall, or a page that builds itself in JavaScript. Saying so and
            // offering the original beats archiving six words of boilerplate.
            if content.wordCount < Self.minimumArticleWords {
                fail(post, reason: content.blocks.isEmpty
                     ? "No readable article was found on that page."
                     : "Only a few words could be read from that page. It may have moved, or it may need JavaScript to show its text.")
                return
            }

            try? context.save()

        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fail(post, reason: message)
        }
    }

    /// The PDF pipeline: no network fetch (the bytes are already local, and
    /// already on `post.pdfData` — see `Post.init(pdfNamed:data:)`), just
    /// parsing and text extraction, which is CPU-bound enough on a large
    /// document to keep off the main actor.
    ///
    /// Unlike a web article, a PDF that yields little or no text is not
    /// treated as a failure: the file itself — pages, not prose — is what
    /// "readable" means here, and PDFKit renders those regardless of whether
    /// a text layer exists. Only bytes that don't parse as a PDF at all fail.
    private func processPDF(_ post: Post, data: Data) async {
        guard !inFlight.contains(post.id) else { return }

        inFlight.insert(post.id)
        post.state = .fetching
        try? context.save()

        defer { inFlight.remove(post.id) }

        guard let imported = await Self.importPDF(data: data, fallbackTitle: post.title) else {
            fail(post, reason: "That file couldn't be opened as a PDF.")
            return
        }

        post.applyPDF(
            title: imported.title,
            author: imported.author,
            pageCount: imported.pageCount,
            text: imported.text
        )
        try? context.save()
    }

    private nonisolated static func importPDF(data: Data, fallbackTitle: String) async -> PDFImportService.Result? {
        await Task.detached(priority: .userInitiated) {
            PDFImportService.extract(data: data, fallbackTitle: fallbackTitle)
        }.value
    }

    /// Extraction is pure and self-contained, so it runs off the main actor.
    private nonisolated static func extract(html: String, url: URL) async -> ExtractedArticle {
        await Task.detached(priority: .userInitiated) {
            ArticleExtractor.extract(html: html, url: url)
        }.value
    }

    /// Compression is pure too, and runs concurrently with extraction rather
    /// than after it.
    private nonisolated static func compress(html: String) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            Post.compressedHTML(html)
        }.value
    }

    /// Downloads article images with bounded concurrency — a photo-heavy post can
    /// carry 40 of them, and firing all of those at once stalls everything else.
    private func downloadImages(
        for content: ArticleContent,
        referer: URL
    ) async -> [(index: Int, result: ImageArchiver.Result)] {
        let targets = content.imageSources
        guard !targets.isEmpty else { return [] }

        let archiver = imageArchiver
        let limit = 4

        return await withTaskGroup(
            of: (Int, ImageArchiver.Result?).self,
            returning: [(index: Int, result: ImageArchiver.Result)].self
        ) { group in
            var iterator = targets.makeIterator()

            func addNext() {
                guard let target = iterator.next() else { return }
                group.addTask {
                    (target.index, await archiver.archive(source: target.image.source, referer: referer))
                }
            }

            for _ in 0..<limit { addNext() }

            var output: [(index: Int, result: ImageArchiver.Result)] = []
            while let (index, result) = await group.next() {
                if let result { output.append((index, result)) }
                addNext()
            }

            return output.sorted { $0.index < $1.index }
        }
    }

    /// Prefers the image the page nominated as its social card; otherwise the
    /// first one in the body.
    private static func chooseLeadImage(
        from content: ArticleContent,
        assets: [StoredImage],
        preferring source: String?
    ) -> UUID? {
        if let source, let match = assets.first(where: { $0.sourceURL == source }) {
            return match.id
        }
        return content.imageSources.first?.image.assetID ?? assets.first?.id
    }

    private func fail(_ post: Post, reason: String) {
        post.state = .failed
        post.failureReason = reason
        try? context.save()
    }

    // MARK: - Lookup

    private func findPost(canonicalURL: String) -> Post? {
        var descriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.canonicalURLString == canonicalURL }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Mutations used by the UI

    func delete(_ posts: [Post]) {
        for post in posts { context.delete(post) }
        try? context.save()
    }

    func setTags(_ tags: [String], on post: Post) {
        post.tagNames = Self.normalizeTags(tags)
        post.refreshSearchText()
        try? context.save()
    }

    /// Tags are compared case-insensitively but keep the casing first used.
    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for tag in tags {
            let trimmed = tag.squeezed
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(trimmed)
        }
        return output.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
