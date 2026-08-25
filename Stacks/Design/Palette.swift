import SwiftUI

/// The app's colour vocabulary. Warm paper tones rather than clinical greys, so
/// long-form text sits on something closer to a printed page.
enum Palette {
    /// Builds a colour that resolves per appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// The page itself.
    static let paper = dynamic(light: 0xFBF7F0, dark: 0x14120F)
    /// Cards and grouped rows lifted off the page.
    static let card = dynamic(light: 0xFFFDFA, dark: 0x1E1B16)
    /// Sidebar and secondary surfaces.
    static let recessed = dynamic(light: 0xF3EDE2, dark: 0x100E0C)

    static let ink = dynamic(light: 0x1F1B16, dark: 0xF3EBE1)
    static let inkSecondary = dynamic(light: 0x6B6055, dark: 0xA89A8B)
    static let inkTertiary = dynamic(light: 0x998C7C, dark: 0x7A6E61)

    static let rule = dynamic(light: 0xE6DCCC, dark: 0x2E2822)
    static let ruleStrong = dynamic(light: 0xD4C6B0, dark: 0x3D352C)

    /// Terracotta — used sparingly, for the one thing that matters on screen.
    static let accent = dynamic(light: 0xA0472B, dark: 0xE08A63)
    static let accentSoft = dynamic(light: 0xF0E2DA, dark: 0x3A2620)

    static let star = dynamic(light: 0xB8862B, dark: 0xE0B054)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Metrics shared across the app so spacing stays on one rhythm.
enum Metrics {
    static let gutter: CGFloat = 20
    static let rowSpacing: CGFloat = 18
    /// Long-form text becomes hard to track past roughly 70 characters a line.
    static let readingWidth: CGFloat = 680
    static let cornerRadius: CGFloat = 14
}
