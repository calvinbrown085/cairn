import SwiftUI

/// What a tap or a stroke does while the reader is in markup mode.
enum MarkupTool: Equatable {
    /// Tap a sentence to paint it in the current tint; tap it again to clear it.
    case highlight
    /// Tap a sentence to mark it and open its note.
    case note
    /// Tap a highlight or a stroke to remove it.
    case erase
    /// Draw freehand. Scrolling is suspended while this is the tool.
    case pen

    /// The one-line coaching line under the dock.
    var hint: String {
        switch self {
        case .highlight: "Tap a sentence to highlight — anchored to the text, not the pixels"
        case .note: "Tap a sentence to attach a note"
        case .erase: "Tap a highlight or a stroke to remove it"
        case .pen: "Draw anywhere with Apple Pencil · scrolling is paused"
        }
    }
}

/// The ink colours available to the pen. Deliberately three, and deliberately
/// not the highlight tints — ink sits on top of the page, tint sits behind it.
enum InkColor: String, Codable, CaseIterable, Identifiable {
    case graphite, terracotta, teal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .graphite: "Graphite"
        case .terracotta: "Terracotta"
        case .teal: "Teal"
        }
    }

    var color: Color {
        switch self {
        case .graphite: Palette.dynamic(light: 0x3A342C, dark: 0xD8D0C4)
        case .terracotta: Palette.dynamic(light: 0xA0472B, dark: 0xE08A63)
        case .teal: Palette.dynamic(light: 0x2F5D63, dark: 0x7FB8BF)
        }
    }
}

/// How the library draws a post.
enum LibraryStyle: String, CaseIterable, Identifiable, Codable {
    case cards, rows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cards: "Cards"
        case .rows: "Rows"
        }
    }
}
