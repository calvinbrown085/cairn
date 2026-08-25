import UIKit
import SwiftReadability

/// Turns a `RichText` run list into an `NSAttributedString` styled for the
/// current reader settings, with highlight backgrounds painted on top.
struct AttributedTextBuilder {
    let typography: ReaderTypography
    let theme: ReaderTheme

    /// Marks a link's destination so taps can be resolved back to a URL.
    static let linkAttribute = NSAttributedString.Key("stacks.link")

    /// Changes whenever anything that affects rendering changes, which is what
    /// tells `ReaderRenderCache` to start over.
    var styleGeneration: Int {
        var hasher = Hasher()
        hasher.combine(typography.family)
        hasher.combine(typography.bodySize)
        hasher.combine(typography.lineSpacingRatio)
        hasher.combine(typography.measure)
        hasher.combine(theme)
        return hasher.finalize()
    }

    func paragraph(
        _ text: RichText,
        size: Double? = nil,
        weight: UIFont.Weight = .regular,
        color: UIColor? = nil,
        alignment: NSTextAlignment = .natural,
        highlights: [Highlight] = []
    ) -> NSAttributedString {
        let pointSize = size ?? typography.bodySize
        let ink = color ?? UIColor(theme.ink)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = typography.lineSpacing
        paragraphStyle.alignment = alignment
        // Hyphenation keeps the ragged edge from tearing open on narrow columns.
        paragraphStyle.hyphenationFactor = 0.9

        let output = NSMutableAttributedString()

        for run in text.runs {
            var traits = weight
            if run.isBold { traits = weight == .regular ? .semibold : .heavy }

            let font: UIFont = run.isCode
                ? typography.monoFont(size: pointSize * 0.92)
                : typography.uiFont(size: pointSize, weight: traits, italic: run.isItalic)

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ink,
                .paragraphStyle: paragraphStyle,
            ]

            if run.isCode {
                attributes[.backgroundColor] = UIColor(theme.codeBackground)
            }

            if let link = run.link, let url = URL(string: link) {
                attributes[.foregroundColor] = UIColor(theme.accent)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = UIColor(theme.accent).withAlphaComponent(0.35)
                attributes[Self.linkAttribute] = url
            }

            output.append(NSAttributedString(string: run.text, attributes: attributes))
        }

        apply(highlights, to: output)
        return output
    }

    func code(_ source: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = typography.codeSize * 0.36

        return NSAttributedString(string: source, attributes: [
            .font: typography.monoFont(size: typography.codeSize),
            .foregroundColor: UIColor(theme.ink),
            .paragraphStyle: paragraphStyle,
        ])
    }

    /// Highlights are stored as character ranges into the block's plain text, so
    /// they survive font, theme, and device changes. Ranges are clamped because a
    /// re-extraction could have shortened the text underneath them.
    private func apply(_ highlights: [Highlight], to string: NSMutableAttributedString) {
        guard !highlights.isEmpty else { return }
        let bounds = NSRange(location: 0, length: string.length)

        for highlight in highlights {
            let range = NSIntersectionRange(highlight.range, bounds)
            guard range.length > 0 else { continue }
            string.addAttribute(.backgroundColor, value: UIColor(Palette.highlight(highlight.tint)), range: range)
        }
    }
}
