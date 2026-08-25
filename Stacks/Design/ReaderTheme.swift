import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
    case paper, sepia, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .night: "Night"
        }
    }

    /// `nil` lets the reader follow the system appearance; the other themes pin it.
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .paper: nil
        case .sepia: .light
        case .night: .dark
        }
    }

    var background: Color {
        switch self {
        case .paper: Palette.paper
        case .sepia: Color(uiColor: UIColor(hex: 0xF4ECD9))
        case .night: Color(uiColor: UIColor(hex: 0x121110))
        }
    }

    var ink: Color {
        switch self {
        case .paper: Palette.ink
        case .sepia: Color(uiColor: UIColor(hex: 0x453A29))
        case .night: Color(uiColor: UIColor(hex: 0xDED6CC))
        }
    }

    var inkSecondary: Color {
        switch self {
        case .paper: Palette.inkSecondary
        // Darkened from 0x7A6A51 (same hue and saturation): at full opacity
        // it only cleared background contrast at 4.45:1, and at the 80%
        // opacity metadata captions draw it at, that fell to 3.11:1 — both
        // short of WCAG AA's 4.5:1. See `ReaderContrastAudit`.
        case .sepia: Color(uiColor: UIColor(hex: 0x524837))
        // Lightened from 0x8E8478 (same hue and saturation): the 80%-opacity
        // caption weight only reached 3.70:1 against `night`'s background.
        // See `ReaderContrastAudit`.
        case .night: Color(uiColor: UIColor(hex: 0xA0988E))
        }
    }

    var rule: Color {
        switch self {
        case .paper: Palette.rule
        case .sepia: Color(uiColor: UIColor(hex: 0xDDCFB2))
        case .night: Color(uiColor: UIColor(hex: 0x2B2723))
        }
    }

    var accent: Color {
        switch self {
        case .paper: Palette.accent
        case .sepia: Color(uiColor: UIColor(hex: 0x9A4526))
        // Lightened from 0xE08A63 (same hue and saturation) to match
        // `Palette.accent`'s dark value — see the comment there. A link set
        // in this colour can sit inside a highlighted passage, and against
        // the darkest highlight tint that pair only reached 3.26:1.
        case .night: Color(uiColor: UIColor(hex: 0xE49876))
        }
    }

    /// Behind code blocks and inline code.
    var codeBackground: Color {
        switch self {
        case .paper: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x1E1B17) : UIColor(hex: 0xF2ECE1) })
        case .sepia: Color(uiColor: UIColor(hex: 0xEBE0C7))
        case .night: Color(uiColor: UIColor(hex: 0x1C1A18))
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable {
    case serif, sans, rounded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .serif: "Serif"
        case .sans: "Sans"
        case .rounded: "Rounded"
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }

    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }
}

/// Resolves the reader's preferences into concrete fonts and metrics. Held as a
/// value so views can diff it and SwiftUI can animate size changes.
struct ReaderTypography: Equatable {
    var family: ReaderFontFamily = .serif
    var bodySize: Double = 19
    var lineSpacingRatio: Double = 0.55
    var measure: Double = Metrics.readingWidth

    func font(size: Double, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let base = Font.system(size: size, weight: weight, design: family.design)
        return italic ? base.italic() : base
    }

    func uiFont(size: Double, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        var descriptor = system.fontDescriptor
        if let designed = descriptor.withDesign(family.uiDesign) { descriptor = designed }
        if italic, let slanted = descriptor.withSymbolicTraits(
            descriptor.symbolicTraits.union(.traitItalic)
        ) {
            descriptor = slanted
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Monospace stays monospace regardless of the chosen family — code needs it.
    func monoFont(size: Double) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var body: Font { font(size: bodySize) }
    var lineSpacing: Double { bodySize * lineSpacingRatio }

    /// Headings step down through a modular scale rather than fixed sizes, so
    /// they stay proportional when the reader changes the body size.
    func headingSize(level: Int) -> Double {
        switch level {
        case 1: bodySize * 1.62
        case 2: bodySize * 1.38
        case 3: bodySize * 1.18
        default: bodySize * 1.04
        }
    }

    var codeSize: Double { bodySize * 0.84 }
    var captionSize: Double { bodySize * 0.78 }
    var quoteSize: Double { bodySize * 1.02 }
}
