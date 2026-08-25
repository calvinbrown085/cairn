import UIKit
import UniformTypeIdentifiers
import SwiftUI

/// The share sheet target.
///
/// It does no networking and touches neither SwiftData nor CloudKit — it drops
/// the URL into the shared app-group inbox and gets out of the way. The app
/// fetches and extracts the article when it next runs, which keeps sharing
/// instant and well under the extension's memory limit.
final class ShareViewController: UIViewController {

    private let card = UIHostingController(rootView: ConfirmationCard(state: .working))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        embedCard()

        Task {
            let result = await resolveSharedURL()
            await MainActor.run { self.finish(with: result) }
        }
    }

    private func embedCard() {
        addChild(card)
        card.view.backgroundColor = .clear
        card.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card.view)
        NSLayoutConstraint.activate([
            card.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.view.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            card.view.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
        ])
        card.didMove(toParent: self)
    }

    private func finish(with result: (url: URL, title: String?)?) {
        guard let result, SharedInbox.deposit(url: result.url, title: result.title) else {
            card.rootView = ConfirmationCard(state: .failed)
            dismissAfterDelay(0.9)
            return
        }

        card.rootView = ConfirmationCard(state: .saved(host: hostLabel(result.url)))
        dismissAfterDelay(0.65)
    }

    private func dismissAfterDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func hostLabel(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Reading the shared item

    /// Safari offers the page as a URL; other apps sometimes offer only text
    /// containing one, so both are handled.
    private func resolveSharedURL() async -> (url: URL, title: String?)? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        for item in items {
            let title = item.attributedContentText?.string
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await load(UTType.url, from: provider) as? URL {
                    return (url, title)
                }
            }
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await load(UTType.plainText, from: provider) as? String,
                   let url = ShareViewController.firstURL(in: text) {
                    return (url, nil)
                }
            }
        }

        return nil
    }

    private func load(_ type: UTType, from provider: NSItemProvider) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { value, _ in
                continuation.resume(returning: value as? NSSecureCoding)
            }
        }
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }
}

/// The small confirmation the share sheet shows while the URL is filed away.
private struct ConfirmationCard: View {
    enum State {
        case working
        case saved(host: String)
        case failed
    }

    let state: State

    // Frames the icon; scaled with it so a large accessibility size doesn't
    // clip the glyph inside what used to be a fixed 34pt box.
    @ScaledMetric(relativeTo: .title2) private var iconHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 12) {
            icon
                .frame(height: iconHeight)

            Text(headline)
                .font(.scaled(17, weight: .semibold, design: .serif, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(.scaled(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(minWidth: 230)
        .background(Palette.card, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 26, y: 10)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .working:
            ProgressView().controlSize(.large)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.scaled(30, relativeTo: .title2))
                .foregroundStyle(Palette.accent)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.scaled(28, relativeTo: .title2))
                .foregroundStyle(Palette.accent)
        }
    }

    private var headline: String {
        switch state {
        case .working: "Saving…"
        case .saved: "Saved to Stacks"
        case .failed: "Couldn't save that"
        }
    }

    private var detail: String? {
        switch state {
        case .working: nil
        case .saved(let host): host
        case .failed: "No link was found to save."
        }
    }
}
