import AppIntents

/// Offers `SaveLinkIntent` in the Shortcuts app, Spotlight, and Siri without
/// anyone having to build a shortcut by hand first.
struct CairnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveLinkIntent(),
            phrases: [
                "Save a link to \(.applicationName)",
                "Save to \(.applicationName)",
            ],
            shortTitle: "Save Link",
            systemImageName: "link.badge.plus"
        )
    }
}
