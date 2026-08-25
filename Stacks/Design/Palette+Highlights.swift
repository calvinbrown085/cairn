import SwiftUI

/// Highlight colours live apart from the rest of the palette because the share
/// extension compiles `Palette` but has no need for the article models.
extension Palette {
    static func highlight(_ tint: HighlightTint) -> Color {
        switch tint {
        case .butter: dynamic(light: 0xFCEBA8, dark: 0x5C4A16)
        case .rose:   dynamic(light: 0xF8D8D4, dark: 0x5E2E2A)
        case .sky:    dynamic(light: 0xD6E6F5, dark: 0x25415C)
        case .sage:   dynamic(light: 0xD9E8D2, dark: 0x2C4526)
        }
    }
}
