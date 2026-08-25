import SwiftUI
import UIKit
import SwiftReadability

/// A self-contained, full-screen presentation of an already-archived image.
///
/// This renders `StoredImage` bytes directly — the same bytes `ArchivedImageView`
/// draws inline in the reader — and never touches the network (see
/// `ImageArchiver`, which already did the one-time download and re-encode at
/// save time). It knows nothing about how it is presented: a caller opens it
/// from a `.fullScreenCover(item:)` or `.fullScreenCover(isPresented:)`, and it
/// dismisses itself through `\.dismiss`, so mounting it takes one line and no
/// shared state.
///
/// Zoom uses a `UIScrollView` wrapped in `UIViewRepresentable` rather than a
/// hand-rolled `MagnifyGesture` + `DragGesture` pair: bounded panning, rubber-band
/// edges, and gesture-driven zoom-to-a-point all come for free from the scroll
/// view, whereas reimplementing them in pure SwiftUI is exactly where a pinch
/// gesture tends to drift once the image is smaller than the viewport. See
/// `ZoomableImageView` below. `SelectableTextView.swift` is this codebase's other
/// example of the same wrapping pattern.
struct ImageViewer: View {
    let image: StoredImage
    var caption: RichText?
    var typography: ReaderTypography = ReaderTypography()
    var theme: ReaderTheme = .paper

    @Environment(\.dismiss) private var dismiss

    /// Tracks whether the scroll view is zoomed past "fit". While zoomed, a
    /// one-finger drag belongs to the scroll view's own panning, so the
    /// swipe-to-dismiss gesture below stands down entirely rather than fight it
    /// for the same touch.
    @State private var isZoomedIn = false

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    private let dismissDistance: CGFloat = 130
    private let dismissVelocity: CGFloat = 900

    var body: some View {
        ZStack {
            theme.background
                .opacity(1 - 0.5 * dismissProgress)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZoomableImageRepresentable(image: decodedImage, isZoomedIn: $isZoomedIn)
                    .accessibilityLabel(image.sourceURL.isEmpty ? "Image" : "Image from \(image.sourceURL)")

                captionView

                Spacer(minLength: 0)
            }
            .offset(dragOffset)
            .scaleEffect(CGFloat(1 - 0.08 * dismissProgress))
            .gesture(dismissGesture, including: isZoomedIn ? .subviews : .all)

            closeButton
        }
        .statusBarHidden()
    }

    // MARK: - Caption

    /// Beneath the image, set smaller and in the reader's own secondary ink so
    /// it reads as metadata rather than body prose — the same treatment
    /// `ArticleBlockView` gives an inline image's caption. No caption, no view:
    /// the layout collapses to just the image with nothing left over.
    @ViewBuilder private var captionView: some View {
        if let caption, !caption.isEmpty {
            SelectableTextView(
                attributed: AttributedTextBuilder(typography: typography, theme: theme).paragraph(
                    caption,
                    size: typography.captionSize,
                    color: UIColor(theme.inkSecondary),
                    alignment: .center
                )
            )
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .opacity(1 - dismissProgress)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.medium)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.ink)
                        .padding(10)
                        .background(.thinMaterial, in: .circle)
                }
                .accessibilityLabel("Close")
                .padding(16)
            }
            Spacer()
        }
        .opacity(1 - dismissProgress)
    }

    // MARK: - Decoding

    /// Full-resolution decode, not a list thumbnail: `ImageArchiver` already
    /// capped these bytes to its own max pixel size at save time, so there is
    /// no larger source to reach for and nothing further to downsample here.
    private var decodedImage: UIImage {
        ImageCache.shared.image(for: image.id, data: image.data)
            ?? UIImage()
    }

    // MARK: - Swipe to dismiss

    /// 0 while at rest, rising toward 1 as a downward drag approaches the
    /// distance that commits to dismissal — used to fade the chrome and the
    /// backdrop together, the way Photos lets the image "leave" under a finger
    /// rather than snapping away the instant a threshold is crossed.
    private var dismissProgress: Double {
        guard isDragging else { return 0 }
        return Double(min(1, abs(dragOffset.height) / (dismissDistance * 1.6)))
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Follows in both directions while dragging so it feels tracked,
                // but only ever commits to dismissal downward.
                isDragging = true
                dragOffset = CGSize(width: value.translation.width * 0.4, height: value.translation.height)
            }
            .onEnded { value in
                let travelled = value.translation.height
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let shouldDismiss = travelled > dismissDistance || (travelled > 40 && velocity > dismissVelocity)

                if shouldDismiss {
                    withAnimation(.easeIn(duration: 0.18)) {
                        dragOffset.height = travelled > 0 ? 1200 : -1200
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { dismiss() }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dragOffset = .zero
                    }
                    isDragging = false
                }
            }
    }
}

/// Hosts a `UIScrollView` zooming a single `UIImageView`.
///
/// `minimumZoomScale` is "fit" (the whole image visible, letterboxed if its
/// aspect ratio doesn't match the screen's); `maximumZoomScale` is built from
/// "fill" (the image scaled up just enough to cover the screen, cropping the
/// overflow) so a pinch can always reach at least that far. Double-tap toggles
/// between exactly those two scales, zooming in centred on the tap point.
private struct ZoomableImageRepresentable: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomedIn: Bool

    func makeUIView(context: Context) -> ZoomableImageView {
        let view = ZoomableImageView(image: image)
        view.onZoomChange = { zoomed in
            if isZoomedIn != zoomed { isZoomedIn = zoomed }
        }
        return view
    }

    func updateUIView(_ uiView: ZoomableImageView, context: Context) {
        if uiView.imageView.image !== image {
            uiView.setImage(image)
        }
    }
}

final class ZoomableImageView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onZoomChange: ((Bool) -> Void)?

    private var fitScale: CGFloat = 1
    private var fillScale: CGFloat = 1

    init(image: UIImage) {
        super.init(frame: .zero)

        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.image = image
        addSubview(imageView)
        contentSize = image.size

        delegate = self
        bouncesZoom = true
        // Disabled at rest: with panning off, an un-zoomed one-finger drag
        // passes straight through to the SwiftUI dismiss gesture behind this
        // view instead of the scroll view eating it as a rubber-banded scroll.
        isScrollEnabled = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        fitScale = 1
        fillScale = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0,
              let image = imageView.image, image.size.width > 0, image.size.height > 0
        else { return }

        let scaleToFit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let scaleToFill = max(bounds.width / image.size.width, bounds.height / image.size.height)

        if scaleToFit != fitScale || scaleToFill != fillScale {
            fitScale = scaleToFit
            fillScale = scaleToFill
            minimumZoomScale = fitScale
            maximumZoomScale = max(fillScale * 3, fitScale * 4)
            zoomScale = fitScale
        }
        centerImage()
    }

    private func centerImage() {
        let boundsSize = bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        let zoomedIn = zoomScale > fitScale + 0.001
        isScrollEnabled = zoomedIn
        onZoomChange?(zoomedIn)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > fitScale + 0.001 {
            setZoomScale(fitScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let targetScale = fillScale
            let width = bounds.width / targetScale
            let height = bounds.height / targetScale
            let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            zoom(to: rect, animated: true)
        }
    }
}

#Preview("With caption") {
    ImageViewer(
        image: StoredImage(
            data: UIImage(systemName: "photo")?.pngData() ?? Data(),
            pixelWidth: 400,
            pixelHeight: 300,
            sourceURL: "https://example.com/photo.jpg"
        ),
        caption: RichText(runs: [InlineRun(text: "A caption, set beneath the image in the reader's secondary ink.")]),
        theme: .sepia
    )
}

#Preview("No caption") {
    ImageViewer(
        image: StoredImage(
            data: UIImage(systemName: "photo")?.pngData() ?? Data(),
            pixelWidth: 400,
            pixelHeight: 300,
            sourceURL: "https://example.com/photo.jpg"
        ),
        theme: .night
    )
}
