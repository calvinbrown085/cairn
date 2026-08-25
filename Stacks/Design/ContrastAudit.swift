import SwiftUI

/// A pure function of two colours — the WCAG 2.x contrast formula itself,
/// §1.4.3. Kept apart from `ReaderContrastAudit` so it can be reused wherever
/// a colour pair needs checking, not just for the reader themes.
enum WCAGContrast {
    /// Relative luminance of a single sRGB channel, 0...1.
    private static func linearize(_ channel: CGFloat) -> Double {
        let c = Double(channel)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Not `private`: `ReaderDock` reads this directly to pick its active
    /// toggle's ink from the accent that is actually resolved for the current
    /// appearance, rather than from which theme case is selected.
    static func luminance(of color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// The WCAG contrast ratio between two opaque colours, always ≥ 1:1.
    /// AA asks for 4.5:1 on normal text, 3:1 on large text (18pt+, or
    /// 14pt+ bold).
    static func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = luminance(of: a)
        let lb = luminance(of: b)
        let (lighter, darker) = la > lb ? (la, lb) : (lb, la)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Flattens a translucent `foreground` over an opaque `background`, the
    /// way UIKit composites a layer, so a pair drawn with `.opacity()` can be
    /// scored the way it is actually seen rather than at full strength.
    static func composited(_ foreground: UIColor, alpha: Double, over background: UIColor) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let a = CGFloat(alpha)
        return UIColor(
            red: fr * a + br * (1 - a),
            green: fg * a + bg * (1 - a),
            blue: fb * a + bb * (1 - a),
            alpha: 1
        )
    }
}

/// A repeatable record of every text-on-background pair the three reader
/// themes actually draw together, measured against WCAG AA. The colours are
/// read live from `ReaderTheme` and `Palette`, so the numbers here always
/// match what is on screen — there is nothing to keep in sync by hand.
///
/// To re-run the audit, read `ReaderContrastAudit.pairs` (or just
/// `.failures`, which should always be empty for a pair whose `required` is
/// non-nil). It is a pure function of the palette, so it reproduces the same
/// ratios on every run.
///
/// This is not wired into `verify.sh`: the app has no unit test target today
/// (only `StacksUITests`, a UI-testing bundle, and `verify.sh` only builds
/// the app — it never runs `xcodebuild test` against it), and adding one
/// means editing `project.yml`, which sits outside this task's `touches`
/// glob (`Stacks/Design/**`). Once a unit test target exists, a single test
/// asserting `ReaderContrastAudit.failures.isEmpty` is the whole job.
enum ReaderContrastAudit {
    /// One measured pair.
    struct Pair {
        /// Where this pair is drawn, so a failure is easy to find again.
        let label: String
        let ratio: Double
        /// `nil` marks a pair recorded for completeness that is not held to
        /// a minimum — an ornament with no reading content, not a sentence.
        let required: Double?
        var passes: Bool { required.map { ratio >= $0 } ?? true }
    }

    /// WCAG AA for normal-size text. Every pair audited here is body copy,
    /// captions, or links smaller than the "large text" carve-out (18pt, or
    /// 14pt bold), so this is the threshold that applies throughout.
    static let normalText = 4.5

    private static func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    /// `ReaderTheme.paper` has no forced colour scheme, so it renders as two
    /// distinct, equally real pairs depending on the system appearance. The
    /// other two themes pin their scheme and only ever render one way.
    private static func appearances(of theme: ReaderTheme) -> [(suffix: String, style: UIUserInterfaceStyle)] {
        guard let forced = theme.forcedColorScheme else {
            return [(" (light)", .light), (" (dark)", .dark)]
        }
        return [("", forced == .dark ? .dark : .light)]
    }

    static let pairs: [Pair] = {
        var out: [Pair] = []

        func add(_ label: String, _ foreground: UIColor, _ background: UIColor, required: Double? = normalText) {
            out.append(Pair(label: label, ratio: WCAGContrast.ratio(foreground, background), required: required))
        }

        for theme in ReaderTheme.allCases {
            for (suffix, style) in appearances(of: theme) {
                let label = theme.label + suffix
                let background = resolve(theme.background, style)
                let ink = resolve(theme.ink, style)
                let inkSecondary = resolve(theme.inkSecondary, style)
                let accent = resolve(theme.accent, style)
                let codeBackground = resolve(theme.codeBackground, style)

                add("\(label): body text (ink) on background", ink, background)
                add("\(label): metadata & captions (secondary ink) on background", inkSecondary, background)
                add("\(label): links & buttons (accent) on background", accent, background)
                add("\(label): code block text (ink) on code background", ink, codeBackground)

                // ReaderDock's active toggle fills its capsule with the
                // theme's accent and picks white or near-black ink from
                // whichever the resolved accent's luminance actually needs —
                // see `ReaderDock.onAccentInk(for:style:)`. Paper is the case
                // that matters here: light and dark appearance resolve to two
                // very different accent colours from the same theme case.
                add(
                    "\(label): dock active toggle (onAccentInk) on accent",
                    resolve(ReaderDock.onAccentInk(for: theme, style: style), style),
                    accent
                )

                // ReaderView's "Archived <date>" footer is read content drawn
                // at reduced opacity, not decoration — it has to clear AA too.
                add(
                    "\(label): archived-date caption (secondary ink @ 80%) on background",
                    WCAGContrast.composited(inkSecondary, alpha: 0.8, over: background),
                    background
                )

                for tint in HighlightTint.allCases {
                    let tintBackground = resolve(Palette.highlight(tint), style)
                    add(
                        "\(label): highlighted text (ink) on \(tint.label) highlight",
                        ink,
                        tintBackground
                    )
                    // A link inside a highlighted passage keeps its accent
                    // foreground colour (`AttributedTextBuilder.paragraph`
                    // sets it after the run is built) while the highlight
                    // background is painted on top afterwards — a real,
                    // separate pair from plain highlighted text.
                    add(
                        "\(label): highlighted link (accent) on \(tint.label) highlight",
                        accent,
                        tintBackground
                    )
                }

                // ArticleBlockView's "❋" section divider is an ornament, not
                // language — recorded so the audit is complete, but it is not
                // information a reader needs to resolve, so it is not scored.
                add(
                    "\(label): section-divider ornament (secondary ink @ 60%) on background",
                    WCAGContrast.composited(inkSecondary, alpha: 0.6, over: background),
                    background,
                    required: nil
                )
            }
        }

        return out
    }()

    /// Every pair that fails the threshold it was measured against. Should
    /// always be empty — that emptiness is the entire point of the list.
    static var failures: [Pair] { pairs.filter { !$0.passes } }
}
