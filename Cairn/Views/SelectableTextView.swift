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
    /// Marks this block as a heading for VoiceOver's rotor. A `UITextView` is
    /// its own accessibility element regardless of what SwiftUI modifiers are
    /// applied to the `SelectableTextView` wrapper around it, so the `.header`
    /// trait has to be set on the underlying view directly — it will not take
    /// effect if attached as a SwiftUI `.accessibilityAddTraits` on this view.
    var isHeading: Bool = false
    /// Character ranges (into `attributed.string`) that are currently
    /// highlighted, unclamped — this view clamps and merges them. A
    /// highlight is only a background colour, which VoiceOver never speaks on
    /// its own, so when this is non-empty the spoken value is rebuilt with an
    /// explicit "Highlighted … end highlight" narration around each span
    /// rather than relying on the paint underneath it.
    var highlightedRanges: [NSRange] = []
    /// Non-nil while the reader is marking up, which changes what a plain tap
    /// means: it selects a sentence instead of following a link.
    var markupTool: MarkupTool?
    var onHighlight: ((NSRange, String) -> Void)?
    var onSentenceTap: ((NSRange, String) -> Void)?
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
        // Fonts in `attributed` are built through `UIFontMetrics`
        // (`ReaderTypography.uiFont`/`monoFont`), which registers them for this
        // exact rescaling; the block's cached height is invalidated separately
        // (see `AttributedTextBuilder.styleGeneration`) whenever the system
        // category changes, so a taller re-render is measured, not clipped.
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.required, for: .vertical)

        // Links carry a custom attribute rather than `.link` so the theme owns
        // their colour, which means resolving taps by hand.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        // `cancelsTouchesInView` stays false: UITextView's own recognisers
        // (caret placement, the loupe, double-tap word selection) still need
        // the touch for selection and links to work outside markup mode.
        // Without a delegate answering `shouldBeRequiredToFailBy`, that leaves
        // this tap and UITextView's built-in tap-to-place-a-caret recogniser
        // racing for the same touch with no defined winner. Marking up needs
        // a deterministic winner, so the delegate below makes this recogniser
        // require the built-in one to wait, but only while marking up —
        // see `gestureRecognizer(_:shouldBeRequiredToFailBy:)`.
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        context.coordinator.tapRecognizer = tap
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
        // Assigned unconditionally (not just when `attributed` changes): this
        // view is reused across `updateUIView` calls for the same block, and
        // both of these can change independently of the text — a highlight
        // added elsewhere already forces a new `attributed` through the
        // render cache, but `isHeading` never does, since it never varies for
        // a given block.
        view.accessibilityTraits = isHeading ? [.header] : []
        view.accessibilityValue = Self.accessibilityValue(for: attributed, highlightedRanges: highlightedRanges)
    }

    /// The spoken content for a block that has highlights, or `nil` to leave
    /// `UITextView`'s own default (which reads `attributedText` as plain
    /// prose — correct, and untouched, for the common case of no highlights).
    ///
    /// Every character in `attributed.string` ends up in exactly one segment
    /// below, highlighted or not, in its original order, so this can only add
    /// narration — it cannot drop or reorder any of the underlying text.
    static func accessibilityValue(for attributed: NSAttributedString, highlightedRanges: [NSRange]) -> String? {
        guard !highlightedRanges.isEmpty else { return nil }
        let string = attributed.string as NSString
        let bounds = NSRange(location: 0, length: string.length)

        let ranges = highlightedRanges
            .map { NSIntersectionRange($0, bounds) }
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
        guard !ranges.isEmpty else { return nil }

        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(range)
            }
        }

        var result = ""
        var cursor = 0
        for range in merged {
            result += string.substring(with: NSRange(location: cursor, length: range.location - cursor))
            result += "Highlighted, "
            result += string.substring(with: range)
            result += ", end highlight. "
            cursor = NSMaxRange(range)
        }
        result += string.substring(with: NSRange(location: cursor, length: string.length - cursor))
        return result
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

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableTextView
        /// The custom tap added in `makeUIView`, kept so the delegate method
        /// below can tell it apart from UITextView's own recognisers.
        weak var tapRecognizer: UITapGestureRecognizer?

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        /// Makes the custom tap win the race against UITextView's built-in
        /// tap-to-place-a-caret recogniser, but only while marking up.
        ///
        /// Both are plain single-tap recognisers attached to the same view,
        /// so with no failure requirement between them, UIKit has no defined
        /// winner — either can recognise first, which is exactly why the
        /// caret used to win about half the time. Answering `true` here (for
        /// a sibling recogniser on the same text view) makes *this*
        /// recogniser required to fail before that sibling can succeed, which
        /// is the one relationship we can establish without touching
        /// UITextView's own private recognisers or their delegate. Since a
        /// plain tap almost always lets this recogniser succeed, the sibling
        /// then never gets a turn — no caret. Outside markup mode this
        /// returns false, so the two race exactly as they did before: not a
        /// bug there, since placing a caret on a plain tap is the ordinary,
        /// desired outcome of a selectable text view.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard gestureRecognizer === tapRecognizer else { return false }
            guard otherGestureRecognizer.view === gestureRecognizer.view else { return false }
            guard let tool = parent.markupTool, tool != .pen else { return false }
            return true
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
            // A tap that dismisses a selection shouldn't also do anything else.
            guard textView.selectedTextRange?.isEmpty ?? true else { return }
            let point = recognizer.location(in: textView)

            // Marking up, a tap picks the sentence it landed in. The pen draws
            // through its own layer, so it never reaches here.
            if let tool = parent.markupTool, tool != .pen, let onSentenceTap = parent.onSentenceTap {
                guard let range = textView.sentenceRange(at: point) else { return }
                let text = (textView.attributedText.string as NSString).substring(with: range)
                onSentenceTap(range, text)
                return
            }

            guard let url = textView.linkURL(at: point) else { return }
            parent.onOpenLink?(url)
        }
    }
}

extension UITextView {
    /// The sentence a tap landed in, as a range into the block's plain text.
    ///
    /// A sentence is the unit a reader actually decides about — it is what you
    /// would draw a line under on paper — and it anchors exactly like a dragged
    /// selection does, because it *is* a character range.
    func sentenceRange(at point: CGPoint) -> NSRange? {
        let string = attributedText.string as NSString
        guard string.length > 0 else { return nil }

        // A tap past the last line shouldn't silently mark the last sentence.
        guard bounds.contains(point) else { return nil }
        guard let position = closestPosition(to: point) else { return nil }
        let index = min(max(offset(from: beginningOfDocument, to: position), 0), string.length - 1)

        var found: NSRange?
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, stop in
            if NSLocationInRange(index, range) {
                found = range
                stop.pointee = true
            }
        }

        guard var range = found else { return nil }
        // Sentence enumeration keeps the space that follows the full stop;
        // painting it would leave a tinted gap before the next sentence.
        while range.length > 0,
              let scalar = Unicode.Scalar(string.character(at: range.location + range.length - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            range.length -= 1
        }
        return range.length > 0 ? range : nil
    }

    /// Resolves a tap location to the link stored at that character, if any.
    func linkURL(at point: CGPoint) -> URL? {
        guard let position = closestPosition(to: point) else { return nil }
        let index = offset(from: beginningOfDocument, to: position)
        guard index >= 0, index < attributedText.length else { return nil }
        return attributedText.attribute(
            AttributedTextBuilder.linkAttribute, at: index, effectiveRange: nil
        ) as? URL
    }
}
