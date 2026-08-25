import SwiftUI
import UIKit

/// The ink sitting over one block of an article.
///
/// Strokes are always drawn; input is only captured while the pen or the eraser
/// is the active tool, so an ordinary read never has a transparent view eating
/// its taps. Points are held in the block's unit space — see `InkStroke` — and
/// are only turned into pixels here, at the size the block happens to be right
/// now.
struct InkCanvas: View {
    let strokes: [InkStroke]
    let tool: MarkupTool?
    let ink: InkColor
    let onFinish: ([CGPoint]) -> Void
    let onErase: (InkStroke) -> Void

    @State private var live: [CGPoint] = []

    private var isDrawing: Bool { tool == .pen }
    private var isErasing: Bool { tool == .erase }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                Canvas { context, _ in
                    for stroke in strokes {
                        context.stroke(
                            Self.path(unit: stroke.points, in: size),
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
                        // In pen mode the layer owns every touch. Erasing, it
                        // only claims taps that landed on a stroke — everything
                        // else falls through to the text underneath, which is
                        // what erases a highlight.
                        claims: { point in isDrawing || hit(point, in: size) != nil },
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
                                if let target = hit(point, in: size) { onErase(target) }
                                return
                            }
                            defer { live = [] }
                            guard !isTap, live.count > 1, size.width > 0, size.height > 0 else { return }
                            onFinish(live.map {
                                CGPoint(x: $0.x / size.width, y: $0.y / size.height)
                            })
                        }
                    )
                }
            }
        }
    }

    static let penWidth: Double = 2.4

    private func strokeStyle(width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    /// The stroke nearest a tap, if the tap landed close enough to count. The
    /// threshold is a finger, not a pixel — erasing should not need aim.
    private func hit(_ point: CGPoint, in size: CGSize) -> InkStroke? {
        guard size.width > 0, size.height > 0 else { return nil }
        let threshold: CGFloat = 18

        var best: (stroke: InkStroke, distance: CGFloat)?
        for stroke in strokes {
            let points = stroke.points.map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }
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

    private static func path(unit points: [CGPoint], in size: CGSize) -> Path {
        path(points: points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
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
