import Foundation

extension StringProtocol {
    /// Trimmed of surrounding whitespace and newlines.
    var squeezed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
