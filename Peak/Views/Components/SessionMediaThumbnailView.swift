import SwiftUI
import UIKit

struct SessionMediaThumbnailView: View {
    let imageData: Data?
    let isVideo: Bool
    /// Normalized preview crop (0...1). Default full frame == today's center-fill.
    var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var decodedImage: UIImage?

    /// Reload the decode whenever the bytes OR the crop change.
    private struct DecodeKey: Equatable {
        let data: Data?
        let crop: CGRect
    }

    var body: some View {
        ZStack {
            if let image = decodedImage ?? ThumbnailImageCache.shared.cachedImage(for: imageData, crop: crop) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.glassDimTint)
                Image(systemName: isVideo ? "video" : "photo")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }

            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
        .task(id: DecodeKey(data: imageData, crop: crop)) {
            decodedImage = await ThumbnailImageCache.shared.image(for: imageData, crop: crop)
        }
    }
}

/// Decodes (and crops) thumbnails off the main thread once and reuses the prepared bitmap,
/// so scrolling a media grid never re-decodes JPEG data during rendering. Keyed by (data, crop)
/// so an uncropped item and its cropped variant cache independently.
final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    /// Longest pixel edge for list/grid thumbs. Covers 2x/3x 40–88 pt cells
    /// without decoding a 2048px session photo into a 40pt chip.
    static let displayMaxPixelSize: CGFloat = 256

    private let cache = NSCache<ThumbnailCacheKey, UIImage>()

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for data: Data?, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> UIImage? {
        guard let data else { return nil }
        return cache.object(forKey: ThumbnailCacheKey(data: data, crop: crop))
    }

    func image(for data: Data?, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) async -> UIImage? {
        guard let data else { return nil }
        let key = ThumbnailCacheKey(data: data, crop: crop)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let maxPixel = Self.displayMaxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            // ImageIO downsample first (never a full-res bitmap), then the
            // normalized crop still applies because it is fraction-based.
            guard let image = SessionMediaStore.downsampledImage(from: data, maxDimension: maxPixel) else {
                return nil
            }
            let cropped = image.cropped(toNormalized: crop)
            return cropped.preparingForDisplay() ?? cropped
        }.value
        if let decoded {
            let cost = decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
            cache.setObject(decoded, forKey: key, cost: cost)
        }
        return decoded
    }
}

private final class ThumbnailCacheKey: NSObject {
    let data: NSData
    let crop: CGRect
    private let fingerprint: Int

    init(data: Data, crop: CGRect) {
        self.data = data as NSData
        self.crop = crop
        // Hash length + ends only. `isEqual` still compares the full bytes, so
        // a collision can never show the wrong thumb — it just falls through
        // to NSData equality. Walking every JPEG byte on every cache lookup
        // was the cost we were paying on scroll.
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(crop.origin.x)
        hasher.combine(crop.origin.y)
        hasher.combine(crop.size.width)
        hasher.combine(crop.size.height)
        if !data.isEmpty {
            hasher.combine(Data(data.prefix(16)))
            hasher.combine(Data(data.suffix(16)))
        }
        self.fingerprint = hasher.finalize()
        super.init()
    }

    override var hash: Int { fingerprint }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ThumbnailCacheKey else { return false }
        return fingerprint == other.fingerprint && data.isEqual(other.data) && crop == other.crop
    }
}

#Preview {
    SessionMediaThumbnailView(imageData: nil, isVideo: true)
        .frame(width: 120, height: 120)
        .background(Theme.background)
}
