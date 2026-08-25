import SwiftUI
import UIKit

/// Where each block currently sits, in the reader's own document-space
/// coordinate system — collected from every mounted `ArticleBlockView` so the
/// ink layer can place existing strokes and choose an anchor for a new one.
///
/// The space this is measured in is anchored to the scrolling content itself,
/// not the screen: a block's rect here only changes when the layout actually
/// changes (a re-render, a resize), never as a side effect of scrolling. That
/// is what lets ink stay put while the page moves under it.
struct BlockFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

/// The named coordinate space block frames are reported in. Shared between
/// the blocks that report their own frame and the canvas that reads them
/// back — both must be anchored to the same ancestor for the numbers to mean
/// the same thing.
enum ReaderInkSpace {
    static let name = "reader-ink-space"
}

/// The ink layer for the whole reader, not one block. It sits over the entire
/// scrolling column — including the margins on either side, which is space no
/// per-block layer could ever reach — and uses `blockFrames` to translate
/// between a block's unit space and this canvas's own coordinates.
///
/// Strokes are always drawn; input is only captured while the pen or the
/// eraser is the active tool, so an ordinary read never has a transparent
/// view eating its taps, and scrolling or text selection is untouched while
/// markup is off.
struct InkCanvas: View {
    let strokes: [InkStroke]
    let blockFrames: [Int: CGRect]
    let tool: MarkupTool?
    let ink: InkColor
    /// The anchor block chosen for a finished stroke, plus its points in that
    /// block's unit space.
    let onFinish: (Int, [CGPoint]) -> Void
    let onErase: (InkStroke) -> Void

    @State private var live: [CGPoint] = []

    private var isDrawing: Bool { tool == .pen }
    private var isErasing: Bool { tool == .erase }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for stroke in strokes {
                    guard let rect = blockFrames[stroke.blockIndex] else { continue }
                    context.stroke(
                        Self.path(points: stroke.documentPoints(in: rect)),
                        with: .color(stroke.color.color.opacity(0.92)),
                        style: strokeStyle(width: stroke.width)
                    )
                }
                if live.count > 1 {
                    context.stroke(
                        Self.path(points: live),
                        with: .color(ink.color.opacity(0.92)),
                        style: strokeStyle(width: InkCanvas.penWidth)
                    )
                }
            }
            .allowsHitTesting(false)

            if isDrawing || isErasing {
                InkCapture(
                    // In pen mode the layer owns every touch, anywhere over
                    // the document. Erasing, it only claims taps that landed
                    // on a stroke — everything else falls through to the text
                    // underneath, which is what erases a highlight instead.
                    claims: { point in isDrawing || hit(point) != nil },
                    onBegan: { point in
                        guard isDrawing else { return }
                        live = [point]
                    },
                    onMoved: { points in
                        guard isDrawing else { return }
                        live.append(contentsOf: points)
                    },
                    onEnded: { isTap, point in
                        if isErasing {
                            if let target = hit(point) { onErase(target) }
                            return
                        }
                        defer { live = [] }
                        guard !isTap, live.count > 1, let start = live.first,
                              let anchor = anchorBlock(for: start),
                              let rect = blockFrames[anchor],
                              rect.width > 0, rect.height > 0
                        else { return }
                        let unitPoints = live.map {
                            CGPoint(x: ($0.x - rect.minX) / rect.width, y: ($0.y - rect.minY) / rect.height)
                        }
                        onFinish(anchor, unitPoints)
                    }
                )
            }
        }
    }

    static let penWidth: Double = 2.4

    private func strokeStyle(width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    /// The block a document-space point anchors to. The block whose vertical
    /// span contains the point wins even when the point sits to its left or
    /// right — that is exactly what lets a margin stroke anchor to the
    /// paragraph beside it rather than needing a block of its own.
    ///
    /// A point above every block anchors to the first one, overflowing above
    /// it. A point below every block — or in the gap beneath one — anchors to
    /// the nearest block above it, overflowing past its bottom: the same
    /// "runs past the edge" case `InkStroke` already documents for text
    /// growing taller than its block, just reached by drawing into the gap
    /// instead.
    private func anchorBlock(for point: CGPoint) -> Int? {
        let ordered = blockFrames.sorted { $0.value.minY < $1.value.minY }
        guard let first = ordered.first else { return nil }
        var candidate = first.key
        for (index, rect) in ordered {
            guard rect.minY <= point.y else { break }
            candidate = index
        }
        return candidate
    }

    /// The stroke nearest a tap, if the tap landed close enough to count. The
    /// threshold is a finger, not a pixel — erasing should not need aim.
    private func hit(_ point: CGPoint) -> InkStroke? {
        let threshold: CGFloat = 18

        var best: (stroke: InkStroke, distance: CGFloat)?
        for stroke in strokes {
            guard let rect = blockFrames[stroke.blockIndex], rect.width > 0, rect.height > 0 else { continue }
            let points = stroke.documentPoints(in: rect)
            guard points.count > 1 else { continue }
            var closest = CGFloat.greatestFiniteMagnitude
            for index in 0..<(points.count - 1) {
                closest = min(closest, Self.distance(from: point, to: points[index], points[index + 1]))
            }
            if closest < threshold, closest < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (stroke, closest)
            }
        }
        return best?.stroke
    }

    private static func distance(from point: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Midpoint quadratics: a raw polyline through touch samples reads as
    /// faceted, and ink shouldn't.
    private static func path(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        guard points.count > 2 else {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }

        path.move(to: first)
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// Raw touch capture for ink.
///
/// A `DragGesture` reports one point per frame, which is visibly coarse next to
/// a pencil moving at 240Hz. `coalescedTouches` hands back every sample the
/// digitiser actually took between frames, which is the difference between a
/// line that looks drawn and one that looks plotted.
private struct InkCapture: UIViewRepresentable {
    let claims: (CGPoint) -> Bool
    let onBegan: (CGPoint) -> Void
    let onMoved: ([CGPoint]) -> Void
    let onEnded: (_ wasTap: Bool, _ point: CGPoint) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.handlers = (onBegan, onMoved, onEnded)
        view.claims = claims
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.handlers = (onBegan, onMoved, onEnded)
        view.claims = claims
    }

    final class TouchView: UIView {
        typealias Handlers = (
            began: (CGPoint) -> Void,
            moved: ([CGPoint]) -> Void,
            ended: (Bool, CGPoint) -> Void
        )

        var handlers: Handlers?
        var claims: ((CGPoint) -> Bool)?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard bounds.contains(point), claims?(point) ?? false else { return nil }
            return self
        }

        private var origin: CGPoint = .zero
        private var travelled: CGFloat = 0
        private var last: CGPoint = .zero

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            origin = touch.location(in: self)
            last = origin
            travelled = 0
            handlers?.began(origin)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let samples = (event?.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: self) }
            for sample in samples {
                travelled += hypot(sample.x - last.x, sample.y - last.y)
                last = sample
            }
            handlers?.moved(samples)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            let point = touches.first?.location(in: self) ?? last
            handlers?.ended(travelled < 6, point)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            handlers?.ended(true, last)
        }
    }
}
