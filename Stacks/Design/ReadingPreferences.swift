import SwiftUI
import Observation

/// Reader typography and theme, persisted locally and mirrored to iCloud's
/// key-value store so the setup follows you between iPhone and iPad.
@Observable
final class ReadingPreferences {
    static let shared = ReadingPreferences()

    private enum Key {
        static let theme = "reader.theme"
        static let family = "reader.family"
        static let bodySize = "reader.bodySize"
        static let lineSpacing = "reader.lineSpacing"
        static let measure = "reader.measure"
        static let groupBySite = "library.groupBySite"
        static let libraryStyle = "library.style"
    }

    static let bodySizeRange: ClosedRange<Double> = 15...30
    static let lineSpacingRange: ClosedRange<Double> = 0.30...0.90
    static let measureRange: ClosedRange<Double> = 520...900

    var theme: ReaderTheme = .paper { didSet { write(theme.rawValue, Key.theme) } }
    var family: ReaderFontFamily = .serif { didSet { write(family.rawValue, Key.family) } }
    var bodySize: Double = 19 { didSet { write(bodySize, Key.bodySize) } }
    var lineSpacingRatio: Double = 0.55 { didSet { write(lineSpacingRatio, Key.lineSpacing) } }
    var measure: Double = Metrics.readingWidth { didSet { write(measure, Key.measure) } }
    var groupBySite: Bool = false { didSet { write(groupBySite, Key.groupBySite) } }
    var libraryStyle: LibraryStyle = .cards { didSet { write(libraryStyle.rawValue, Key.libraryStyle) } }

    var typography: ReaderTypography {
        ReaderTypography(
            family: family,
            bodySize: bodySize,
            lineSpacingRatio: lineSpacingRatio,
            measure: measure
        )
    }

    private let defaults = AppGroup.defaults
    private let cloud = NSUbiquitousKeyValueStore.default
    private var isLoading = false

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
        cloud.synchronize()
    }

    func resetToDefaults() {
        theme = .paper
        family = .serif
        bodySize = 19
        lineSpacingRatio = 0.55
        measure = Metrics.readingWidth
    }

    // MARK: - Persistence

    /// iCloud wins on load: a change made on the other device is newer than
    /// whatever this device last wrote locally.
    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let raw = read(Key.theme) as? String, let value = ReaderTheme(rawValue: raw) { theme = value }
        if let raw = read(Key.family) as? String, let value = ReaderFontFamily(rawValue: raw) { family = value }
        if let value = read(Key.bodySize) as? Double, value > 0 {
            bodySize = value.clamped(to: Self.bodySizeRange)
        }
        if let value = read(Key.lineSpacing) as? Double, value > 0 {
            lineSpacingRatio = value.clamped(to: Self.lineSpacingRange)
        }
        if let value = read(Key.measure) as? Double, value > 0 {
            measure = value.clamped(to: Self.measureRange)
        }
        if let value = read(Key.groupBySite) as? Bool { groupBySite = value }
        if let raw = read(Key.libraryStyle) as? String, let value = LibraryStyle(rawValue: raw) { libraryStyle = value }
    }

    private func read(_ key: String) -> Any? {
        cloud.object(forKey: key) ?? defaults.object(forKey: key)
    }

    private func write(_ value: Any, _ key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Chrome type scale

/// The app's chrome (library, sheets, sidebar, dock, share extension) used
/// fixed system-font point sizes throughout, which never respond to the
/// system's Dynamic Type setting. `Font.scaled` is a drop-in replacement: it
/// resolves the exact same system font at today's default text size, so
/// nothing visibly changes for anyone on the default setting, but it scales
/// like a semantic style (`.footnote`, `.body`, ...) as the user's preferred
/// size grows. `relativeTo` picks which style's growth curve to follow — a
/// small caption need not grow at the same rate as a headline.
///
/// The reader's own text stack (`ArticleBlockView`, `ReaderTheme`) keeps
/// its fixed-size system font on purpose: its size slider becomes a relative
/// offset over Dynamic Type in T-0022, not before.
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
