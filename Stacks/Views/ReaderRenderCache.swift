import UIKit

/// Memoises the two expensive things the reader does per block: building the
/// styled string, and asking TextKit how tall it is.
///
/// Both used to happen every time a block came into view, and `sizeThatFits` is
/// called more than once per layout pass — so a single flick through a long
/// essay re-laid-out the same paragraphs many times over. Everything is keyed by
/// a style generation, so changing the typography or theme drops the lot.
@MainActor
final class ReaderRenderCache {
    static let shared = ReaderRenderCache()

    private struct HeightKey: Hashable {
        let block: Int
        let width: Int
    }

    private var generation = 0
    private var strings: [Int: NSAttributedString] = [:]
    private var heights: [HeightKey: CGFloat] = [:]

    private init() {}

    /// Drops everything if the style has changed since the last look.
    func prepare(generation newGeneration: Int) {
        guard newGeneration != generation else { return }
        generation = newGeneration
        strings.removeAll(keepingCapacity: true)
        heights.removeAll(keepingCapacity: true)
    }

    /// Returns the styled string for a block, building it once. The instance is
    /// stable, so callers can compare identity instead of contents.
    func string(block: Int, build: () -> NSAttributedString) -> NSAttributedString {
        if let cached = strings[block] { return cached }
        let built = build()
        strings[block] = built
        return built
    }

    func height(block: Int, width: CGFloat, measure: () -> CGFloat) -> CGFloat {
        // Sub-point width changes shouldn't miss the cache.
        let key = HeightKey(block: block, width: Int(width.rounded()))
        if let cached = heights[key] { return cached }
        let measured = measure()
        heights[key] = measured
        return measured
    }
}
