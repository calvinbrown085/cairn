import AppIntents
import Foundation

/// Saves a link from Shortcuts, the Action Button, or an automation.
///
/// This runs the intent's own process — often without the app ever launching
/// — so it must not touch SwiftData or CloudKit directly. It writes into the
/// same shared inbox the share extension writes to (`SharedInbox.deposit`) and
/// nothing else; the app drains that inbox the next time it becomes active
/// (see `CairnApp`'s `scenePhase` handling). One writer, one inbox, one save
/// path — see `SharedInbox.swift`.
struct SaveLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Link"

    static var description = IntentDescription(
        "Saves a web page to your Cairnfield library. Works without opening the app.",
        categoryName: "Library"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to Cairnfield")
    }

    @Parameter(title: "Link", description: "The web page to save.")
    var url: URL

    @Parameter(title: "Title", description: "An optional title to save it under.")
    var title: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Re-validated the same way a pasted or typed link is (see
        // `URL.fromUserInput`): Shortcuts can hand over a URL value built from
        // arbitrary text, and a scheme-less or host-less one isn't something
        // the archive can fetch.
        guard let resolved = URL.fromUserInput(url.absoluteString) else {
            throw SaveLinkIntentError.unusableURL
        }

        let cleanTitle = title?.squeezed
        let providedTitle = (cleanTitle?.isEmpty ?? true) ? nil : cleanTitle

        guard SharedInbox.deposit(url: resolved, title: providedTitle) else {
            throw SaveLinkIntentError.depositFailed
        }

        return .result(dialog: "Saved \(Post.displayHost(for: resolved)) to Cairnfield.")
    }
}

/// Thrown errors that conform to `CustomLocalizedStringResourceConvertible`
/// are what Shortcuts shows the person running the action — silence is not
/// an option here, since a no-op that reports success would be worse than no
/// intent at all.
enum SaveLinkIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case unusableURL
    case depositFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unusableURL:
            "That doesn't look like a web address Cairnfield can save."
        case .depositFailed:
            "Cairnfield couldn't save that link. Check your device storage and try again."
        }
    }
}
