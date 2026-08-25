import Foundation
import SwiftData
import Observation
import SwiftReadability

/// Rebuilds a post's blocks from the original HTML captured alongside it —
/// the repair path for an extractor that gets better after a post was
/// archived. Nothing is fetched from the network: the stored HTML is the
/// only source, so a page that has since changed or vanished is still
/// recoverable, and a post saved before that HTML was kept (see T-0007) has
/// nothing to rebuild from and is left exactly as it was.
///
/// Highlights anchor to `(blockIndex, start, length)`, and rebuilding blocks
/// can move both. Silently keeping the old coordinates would point a
/// highlight at whatever text happens to sit there now — a worse outcome
/// than losing it visibly. So each highlight's stored `text` is searched for
/// in the rebuilt blocks: found exactly once, it is rebound to its new
/// location; found nowhere, or found more than once (which would make
/// rebinding a guess rather than a fact), it is left as "at risk" and the
/// post is not touched unless the caller has already shown that count to the
/// user and been told to continue. No highlight is ever dropped without that
/// confirmation — Constitution P7.
@MainActor
@Observable
final class ReExtractionService {

    /// Set for the duration of a whole-library pass, so the UI can show
    /// progress and offer to cancel it.
    private(set) var isRunning = false
    private(set) var progress: (completed: Int, total: Int)?
    /// The result of the most recently finished (or cancelled) library pass,
    /// left in place until the view that shows it dismisses it.
    private(set) var lastSummary: LibrarySummary?

    private var runningTask: Task<Void, Never>?

    // MARK: - Outcomes

    /// What happened to one post.
    struct PostOutcome {
        var rebuilt = false
        var skippedNoSource = false
        var newBlockCount = 0
        var highlightsReanchored = 0
        /// Highlights whose text couldn't be matched unambiguously against the
        /// rebuilt blocks. Non-zero alongside `rebuilt == false` means nothing
        /// was written at all — the caller has to ask before any are dropped.
        var highlightsAtRisk = 0
        /// Of those at-risk highlights, how many were actually deleted — only
        /// non-zero when the caller passed `dropAtRiskHighlights: true` and the
        /// post *was* rebuilt. Distinct from `highlightsAtRisk` on purpose: the
        /// destructive path is the one that most needs to be reported plainly.
        var highlightsDropped = 0
    }

    /// What happened across a whole-library pass.
    struct LibrarySummary {
        var rebuilt = 0
        var skippedNoSource = 0
        var skippedAtRisk = 0
        var highlightsReanchored = 0
        var highlightsAtRisk = 0
        var highlightsDropped = 0
        var cancelled = false
    }

    // MARK: - One post

    /// Rebuilds a single post's blocks from its stored HTML.
    ///
    /// `dropAtRiskHighlights` only matters when the plan found highlights it
    /// can't safely relocate: leave it `false` to have the call report the
    /// risk without writing anything, and pass `true` only after the caller
    /// has shown that exact count to the user and they chose to continue.
    @discardableResult
    func reExtract(_ post: Post, in context: ModelContext, dropAtRiskHighlights: Bool = false) async -> PostOutcome {
        var outcome = PostOutcome()

        guard let html = post.originalHTML, let url = post.url else {
            outcome.skippedNoSource = true
            return outcome
        }

        let extracted = await Self.extract(html: html, url: url)
        var content = extracted.content
        Self.reattachImages(&content, post: post)

        let plan = Self.planHighlights(post.highlights ?? [], against: content)
        outcome.highlightsReanchored = plan.reanchored.count
        outcome.highlightsAtRisk = plan.atRisk.count

        guard plan.atRisk.isEmpty || dropAtRiskHighlights else {
            return outcome // Nothing written — the caller must confirm first.
        }

        for match in plan.reanchored {
            match.highlight.blockIndex = match.blockIndex
            match.highlight.start = match.start
            match.highlight.length = match.length
        }
        if !plan.atRisk.isEmpty {
            for highlight in plan.atRisk {
                context.delete(highlight)
            }
            outcome.highlightsDropped = plan.atRisk.count
        }

        post.apply(extracted, content: content)
        post.leadImageID = Self.chooseLeadImage(from: content, preferring: extracted.leadImageSource, post: post)
        try? context.save()

        outcome.rebuilt = true
        outcome.newBlockCount = content.blocks.count
        return outcome
    }

    // MARK: - Whole library

    /// Walks every archived post, rebuilding what it can. Cancellable only
    /// between posts, never mid-post — each one is either fully rebuilt and
    /// saved, or left completely untouched, so a cancel can never leave the
    /// store half-written.
    func reExtractLibrary(in context: ModelContext, dropAtRiskHighlights: Bool = false) {
        guard !isRunning else { return }
        isRunning = true
        lastSummary = nil

        runningTask = Task {
            let summary = await self.runLibraryPass(in: context, dropAtRiskHighlights: dropAtRiskHighlights)
            self.lastSummary = summary
            self.isRunning = false
            self.progress = nil
            self.runningTask = nil
        }
    }

    /// Asks a running pass to stop. It finishes whatever post is mid-flight
    /// and then reports what it managed before the request came in.
    func cancel() {
        runningTask?.cancel()
    }

    func dismissSummary() {
        lastSummary = nil
    }

    private func runLibraryPass(in context: ModelContext, dropAtRiskHighlights: Bool) async -> LibrarySummary {
        var summary = LibrarySummary()
        let posts = (try? context.fetch(FetchDescriptor<Post>())) ?? []
        progress = (0, posts.count)

        for (index, post) in posts.enumerated() {
            if Task.isCancelled {
                summary.cancelled = true
                break
            }

            let outcome = await reExtract(post, in: context, dropAtRiskHighlights: dropAtRiskHighlights)
            if outcome.rebuilt {
                summary.rebuilt += 1
                summary.highlightsReanchored += outcome.highlightsReanchored
                summary.highlightsDropped += outcome.highlightsDropped
            } else if outcome.skippedNoSource {
                summary.skippedNoSource += 1
            } else {
                summary.skippedAtRisk += 1
                summary.highlightsAtRisk += outcome.highlightsAtRisk
            }

            // Set only once the post above has actually finished, so a
            // cancel can never report a post as "completed" that was never
            // attempted.
            progress = (index + 1, posts.count)
        }

        return summary
    }

    // MARK: - Extraction

    /// Extraction is pure and CPU-bound, so it runs off the main actor —
    /// the same split `ArchiveService` uses for a fresh fetch.
    private nonisolated static func extract(html: String, url: URL) async -> ExtractedArticle {
        await Task.detached(priority: .userInitiated) {
            ArticleExtractor.extract(html: html, url: url)
        }.value
    }

    // MARK: - Images

    /// A rebuilt block list knows nothing about downloaded bytes; it only has
    /// the source URLs the new extraction found. Existing `StoredImage` rows
    /// are still on disk, keyed by the source they were fetched from, so an
    /// image block whose source matches one is wired back up to it. A source
    /// with no match is content the extractor found this time that was never
    /// downloaded — re-extraction never touches the network, so, exactly like
    /// a failed download during a normal save, that block is dropped rather
    /// than shown as a gap.
    private static func reattachImages(_ content: inout ArticleContent, post: Post) {
        let assets = post.images ?? []
        var bySource: [String: StoredImage] = [:]
        for asset in assets where bySource[asset.sourceURL] == nil {
            bySource[asset.sourceURL] = asset
        }

        for index in content.blocks.indices {
            guard case .image(var image) = content.blocks[index] else { continue }
            if let stored = bySource[image.source] {
                image.assetID = stored.id
                image.width = stored.pixelWidth
                image.height = stored.pixelHeight
                content.blocks[index] = .image(image)
            }
        }

        content.blocks.removeAll { block in
            if case .image(let image) = block { return image.assetID == nil }
            return false
        }
    }

    private static func chooseLeadImage(from content: ArticleContent, preferring source: String?, post: Post) -> UUID? {
        let assets = post.images ?? []
        if let source, let match = assets.first(where: { $0.sourceURL == source }) {
            return match.id
        }
        return content.imageSources.first?.image.assetID
    }

    // MARK: - Highlight re-anchoring

    struct HighlightPlan {
        struct Match {
            let highlight: Highlight
            let blockIndex: Int
            let start: Int
            let length: Int
        }
        var reanchored: [Match] = []
        var atRisk: [Highlight] = []
    }

    static func planHighlights(_ highlights: [Highlight], against content: ArticleContent) -> HighlightPlan {
        var plan = HighlightPlan()
        guard !highlights.isEmpty else { return plan }

        // Every anchorable block's text as an `NSString` once, not once per
        // highlight — offsets are UTF-16, matching `Highlight.start`.
        let haystacks: [(blockIndex: Int, text: NSString)] = content.blocks.enumerated().compactMap { index, block in
            guard let text = block.selectableText, !text.isEmpty else { return nil }
            return (index, text as NSString)
        }

        for highlight in highlights {
            guard let match = uniqueOccurrence(of: highlight.text, in: haystacks) else {
                plan.atRisk.append(highlight)
                continue
            }
            plan.reanchored.append(
                HighlightPlan.Match(highlight: highlight, blockIndex: match.blockIndex, start: match.start, length: match.length)
            )
        }
        return plan
    }

    /// Finds the one place `text` occurs across every block. Any second
    /// occurrence — in the same block or another one — makes the match
    /// ambiguous, and `nil` is returned rather than a guess.
    private static func uniqueOccurrence(
        of text: String, in haystacks: [(blockIndex: Int, text: NSString)]
    ) -> (blockIndex: Int, start: Int, length: Int)? {
        guard !text.isEmpty else { return nil }
        let needleLength = (text as NSString).length
        var found: (blockIndex: Int, start: Int, length: Int)?

        for (blockIndex, haystack) in haystacks {
            var searchStart = 0
            while searchStart < haystack.length {
                let searchRange = NSRange(location: searchStart, length: haystack.length - searchStart)
                let range = haystack.range(of: text, options: [], range: searchRange)
                guard range.location != NSNotFound else { break }
                if found != nil { return nil }
                found = (blockIndex, range.location, needleLength)
                // Advance by one, not past the whole match: "aa" inside "aaa"
                // occurs at both offset 0 and offset 1, and skipping past the
                // first match entirely would hide the second, unique-only
                // occurrence that should have made this ambiguous.
                searchStart = range.location + 1
            }
        }
        return found
    }
}
