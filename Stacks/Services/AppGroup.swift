import Foundation

/// Identifiers shared between the app and its share extension.
enum AppGroup {
    static let identifier = "group.com.calvinbrown.Stacks"
    static let cloudKitContainer = "iCloud.com.calvinbrown.Stacks"

    /// The shared container both processes can write to. Falls back to the
    /// process-local documents directory if the group is unavailable, which keeps
    /// the app usable even when entitlements aren't in place yet.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? URL.documentsDirectory
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Where the share extension leaves URLs for the app to pick up.
    static var inboxURL: URL {
        containerURL.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// The SwiftData store, kept in the shared container so both targets agree
    /// on its location.
    static var storeURL: URL {
        containerURL.appending(path: "Stacks.store", directoryHint: .notDirectory)
    }
}
