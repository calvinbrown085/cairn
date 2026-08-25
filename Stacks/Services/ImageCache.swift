import SwiftUI
import ImageIO
import UIKit

/// Decoded-image cache keyed by asset id.
///
/// SwiftData hands back raw bytes; decoding those on every row render makes
/// scrolling stutter badly, so decoded images are held here and evicted under
/// memory pressure.
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func image(for id: UUID, data: @autoclosure () -> Data, maxPixel: CGFloat? = nil) -> UIImage? {
        let key = (maxPixel.map { "\(id.uuidString)@\(Int($0))" } ?? id.uuidString) as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let bytes = data()
        guard !bytes.isEmpty else { return nil }

        let decoded: UIImage?
        if let maxPixel {
            decoded = ImageCache.thumbnail(from: bytes, maxPixel: maxPixel)
        } else {
            decoded = UIImage(data: bytes)
        }

        guard let decoded else { return nil }
        let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
        cache.setObject(decoded, forKey: key, cost: cost)
        return decoded
    }

    /// Downsamples at decode time — a list thumbnail never needs the full bitmap.
    private static func thumbnail(from data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * UIScreen.main.scale,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

/// Renders a `StoredImage` straight from the archive — no network, ever.
struct ArchivedImageView: View {
    let image: StoredImage?
    var maxPixel: CGFloat?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image, let decoded = ImageCache.shared.image(
            for: image.id, data: image.data, maxPixel: maxPixel
        ) {
            Image(uiImage: decoded)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Rectangle()
                .fill(Palette.recessed)
        }
    }
}
