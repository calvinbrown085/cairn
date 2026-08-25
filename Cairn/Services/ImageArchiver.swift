import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Downloads and re-encodes article images for offline storage.
///
/// Everything gets downscaled: originals are routinely 3000px wide, and those
/// bytes would sync to every device over CloudKit for no visible benefit.
struct ImageArchiver {

    struct Result {
        var data: Data
        var width: Double
        var height: Double
    }

    /// Wide enough for a 13" iPad at 2×, which is the largest reader we present.
    static let maxPixelSize: CGFloat = 1600
    /// Anything past this is a poster or a mistake; skip rather than sync it.
    static let maxDownloadBytes = 12 * 1024 * 1024
    /// Below this, an image is an icon, a bullet, or a tracking pixel.
    static let minimumDimension: Double = 64

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": PageFetcher.userAgent,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        ]
        session = URLSession(configuration: configuration)
    }

    func archive(source: String, referer: URL?) async -> Result? {
        guard let url = URL(string: source), ["http", "https"].contains(url.scheme ?? "") else {
            return nil
        }

        var request = URLRequest(url: url)
        // Some CDNs hotlink-protect; sending the article as referer gets us the file.
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }

        guard let (data, response) = try? await session.data(for: request) else { return nil }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard !data.isEmpty, data.count <= Self.maxDownloadBytes else { return nil }

        return Self.reencode(data)
    }

    /// Downscales to `maxPixelSize` and re-encodes. Images with transparency stay
    /// PNG; everything else becomes JPEG, which is far smaller for photographs.
    static func reencode(_ data: Data) -> Result? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let originalWidth = (properties?[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let originalHeight = (properties?[kCGImagePropertyPixelHeight] as? Double) ?? 0

        if originalWidth > 0, originalHeight > 0,
           originalWidth < minimumDimension, originalHeight < minimumDimension {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else { return nil }

        let hasAlpha: Bool
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            hasAlpha = true
        default:
            hasAlpha = false
        }

        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.82,
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination), output.length > 0 else { return nil }

        return Result(
            data: output as Data,
            width: Double(image.width),
            height: Double(image.height)
        )
    }
}
