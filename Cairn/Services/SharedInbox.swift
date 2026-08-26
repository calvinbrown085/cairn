import Foundation

/// A drop-off point between the share extension and the app.
///
/// The extension writes one small JSON file per shared item — a URL, or a
/// PDF's bytes copied alongside it — and exits immediately; the app drains
/// the directory when it next becomes active. Keeping the extension out of
/// SwiftData and CloudKit entirely is what makes sharing feel instant and
/// keeps it well inside the extension memory budget.
enum SharedInbox {

    enum ItemKind: String, Codable {
        case link
        case pdf
    }

    struct Item: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var kind: ItemKind = .link
        /// The shared URL, for `.link`. Empty for `.pdf`.
        var url: String = ""
        var title: String?
        var receivedAt: Date = .now
        /// The file's name inside `AppGroup.sharedFilesURL`, for `.pdf`.
        /// `nil` for `.link`.
        var fileName: String?
    }

    // MARK: - Writing (share extension)

    @discardableResult
    static func deposit(url: URL, title: String? = nil) -> Bool {
        let item = Item(kind: .link, url: url.absoluteString, title: title)
        return write(item)
    }

    /// Copies a shared PDF's bytes into the app group before recording the
    /// drop-off, so the app never has to reach back into the extension's own
    /// (security-scoped, often temporary) copy of the file.
    @discardableResult
    static func depositPDF(fileURL: URL, title: String? = nil) -> Bool {
        let id = UUID()
        let destinationName = "\(Date.now.timeIntervalSince1970)-\(id.uuidString).pdf"

        do {
            try FileManager.default.createDirectory(
                at: AppGroup.sharedFilesURL, withIntermediateDirectories: true
            )
            let destination = AppGroup.sharedFilesURL.appending(path: destinationName)
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            return false
        }

        let item = Item(id: id, kind: .pdf, title: title, fileName: destinationName)
        guard write(item) else {
            try? FileManager.default.removeItem(
                at: AppGroup.sharedFilesURL.appending(path: destinationName)
            )
            return false
        }
        return true
    }

    private static func write(_ item: Item) -> Bool {
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
