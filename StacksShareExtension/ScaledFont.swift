import SwiftUI

/// A drop-in replacement for a fixed-size system font (weight and design
/// included) that keeps today's exact rendered size at the default Dynamic
/// Type setting but lets accessibility sizes grow it, the way a semantic
/// style (`.footnote`, `.body`, ...) already does. See
/// `Stacks/Design/ReadingPreferences.swift`, which defines the identical
/// helper for the app target — the share extension is a separate module with
/// its own binary, so it can't import that file and needs its own copy. See
/// T-0012.
extension Font {
    static func scaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        var uiFont = UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
        if let systemDesign = design.uiFontDescriptorDesign,
           let descriptor = uiFont.fontDescriptor.withDesign(systemDesign) {
            uiFont = UIFont(descriptor: descriptor, size: size)
        }
        // A custom font keyed by the system font's own PostScript name reads
        // back as the identical glyphs at the identical size, but unlike a
        // fixed-size system font, `Font.custom(_:size:relativeTo:)` scales
        // with `UIFontMetrics` the same way the built-in text styles do.
        return Font.custom(uiFont.fontName, size: size, relativeTo: textStyle)
    }
}

private extension Font.Weight {
    /// SwiftUI has no accessor to read a `Font.Weight` back out, so this
    /// mirrors the fixed set of `UIFont.Weight` cases it's built from.
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

private extension Font.Design {
    var uiFontDescriptorDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .default: nil
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        @unknown default: nil
        }
    }
}
