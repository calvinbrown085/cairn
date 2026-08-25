import Foundation
import SwiftData

/// A freehand mark drawn over an article.
///
/// Ink anchors the same way a highlight does — to a block, not to a pixel. The
/// points are stored in the block's own unit space (x and y as fractions of the
/// block's laid-out frame), so a stroke drawn at 19pt New York still sits over
/// the same sentence at 26pt SF Rounded, on a different device, in a different
/// theme. A stroke that runs past the bottom of its block keeps a y above 1 and
/// is drawn overflowing, which is what the reader saw when they drew it.
@Model
final class InkStroke {
    var id: UUID = UUID()
    var blockIndex: Int = 0
    var colorRaw: String = InkColor.graphite.rawValue
    /// Line width in points, unscaled — ink keeps its weight when text grows.
    var width: Double = 2.4
    /// Unit-space points, flattened to x, y, x, y… and JSON-encoded. A blob
    /// rather than a relationship: a stroke is one value, not a set of rows.
    var pointData: Data = Data()
    var createdAt: Date = Date.now
    var post: Post?

    init(blockIndex: Int, points: [CGPoint], color: InkColor, width: Double = 2.4) {
        self.id = UUID()
        self.blockIndex = blockIndex
        self.colorRaw = color.rawValue
        self.width = width
        self.createdAt = .now
        self.points = points
    }

    init() {}

    var color: InkColor {
        get { InkColor(rawValue: colorRaw) ?? .graphite }
        set { colorRaw = newValue.rawValue }
    }

    var points: [CGPoint] {
        get {
            guard let flat = try? JSONDecoder().decode([Double].self, from: pointData) else { return [] }
            return stride(from: 0, to: flat.count - 1, by: 2).map {
                CGPoint(x: flat[$0], y: flat[$0 + 1])
            }
        }
        set {
            let flat = newValue.flatMap { [Double($0.x), Double($0.y)] }
            pointData = (try? JSONEncoder().encode(flat)) ?? Data()
        }
    }
}
