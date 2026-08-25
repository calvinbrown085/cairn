import SwiftUI
import UIKit

/// A non-scrolling, self-sizing text view that supports selection, a custom
/// "Highlight" menu action, and tappable links.
///
/// SwiftUI's `Text` can't report what the reader selected, which is what
/// highlighting needs — so each prose block gets its own `UITextView`. Blocks
/// are separate views anyway, which is also what makes highlight anchoring
/// simple: a block index plus a range inside that block.
struct SelectableTextView: UIViewRepresentable {
    let attributed: NSAttributedString
    /// Block index, used to memoise the measured height. Nil means measure every
    /// time — correct, just slower.
    var measurementKey: Int?
    var onHighlight: ((NSRange, String) -> Void)?
    var onOpenLink: ((URL) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.dataDetectorTypes = []
        view.adjustsFontForContentSizeCategory = false
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.required, for: .vertical)

        // Links carry a custom attribute rather than `.link` so the theme owns
        // their colour, which means resolving taps by hand.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Cached strings are shared instances, so identity settles it without
        // walking the text.
        if view.attributedText !== attributed {
            view.attributedText = attributed
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }

        func measure() -> CGFloat {
            ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        }

        guard let measurementKey else {
            return CGSize(width: width, height: measure())
        }
        let height = ReaderRenderCache.shared.height(block: measurementKey, width: width, measure: measure)
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextView

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        /// Adds "Highlight" ahead of the system's copy/look-up items.
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, let onHighlight = parent.onHighlight else {
                return UIMenu(children: suggestedActions)
            }

            let selected = (textView.attributedText.string as NSString).substring(with: range)
            let highlight = UIAction(
                title: "Highlight",
                image: UIImage(systemName: "highlighter")
            ) { _ in
                onHighlight(range, selected)
                textView.selectedTextRange = nil
            }

            return UIMenu(children: [highlight] + suggestedActions)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView else { return }
            // A tap that dismisses a selection shouldn't also follow a link.
            guard textView.selectedTextRange?.isEmpty ?? true else { return }
            guard let url = textView.linkURL(at: recognizer.location(in: textView)) else { return }
            parent.onOpenLink?(url)
        }
    }
}

/// Resolves a tap location to the link stored at that character, if any.
extension UITextView {
    func linkURL(at point: CGPoint) -> URL? {
        guard let position = closestPosition(to: point) else { return nil }
        let index = offset(from: beginningOfDocument, to: position)
        guard index >= 0, index < attributedText.length else { return nil }
        return attributedText.attribute(
            AttributedTextBuilder.linkAttribute, at: index, effectiveRange: nil
        ) as? URL
    }
}
