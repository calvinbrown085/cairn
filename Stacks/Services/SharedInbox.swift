import Foundation

/// A drop-off point between the share extension and the app.
///
/// The extension writes one small JSON file per shared URL and exits immediately;
/// the app drains the directory when it next becomes active. Keeping the
/// extension out of SwiftData and CloudKit entirely is what makes sharing feel
/// instant and keeps it well inside the extension memory budget.
enum SharedInbox {

    struct Item: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var url: String
        var title: String?
        var receivedAt: Date = .now
    }

    // MARK: - Writing (share extension)

    @discardableResult
    static func deposit(url: URL, title: String? = nil) -> Bool {
        let item = Item(url: url.absoluteString, title: title)
        guard let data = try? JSONEncoder().encode(item) else { return false }

        do {
            try FileManager.default.createDirectory(
                at: AppGroup.inboxURL, withIntermediateDirectories: true
            )
            // Timestamp-prefixed so draining preserves the order things were shared.
            let name = "\(item.receivedAt.timeIntervalSince1970)-\(item.id.uuidString).json"
            try data.write(to: AppGroup.inboxURL.appending(path: name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reading (app)

    /// Returns everything waiting and removes it from the inbox. Files that fail
    /// to decode are deleted too, so a bad write can't wedge the queue forever.
    static func drain() -> [Item] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(
            at: AppGroup.inboxURL, includingPropertiesForKeys: nil
        ) else { return [] }

        var items: [Item] = []
        for file in names.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let item = try? JSONDecoder().decode(Item.self, from: data) {
                items.append(item)
            }
            try? manager.removeItem(at: file)
        }
        return items
    }

    static var isEmpty: Bool {
        let names = try? FileManager.default.contentsOfDirectory(
            at: AppGroup.inboxURL, includingPropertiesForKeys: nil
        )
        return (names ?? []).isEmpty
    }
}
