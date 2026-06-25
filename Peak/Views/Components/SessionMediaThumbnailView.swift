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
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(data: data) else { return nil }
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

    init(data: Data, crop: CGRect) {
        self.data = data as NSData
        self.crop = crop
        super.init()
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(data)
        hasher.combine(crop.origin.x)
        hasher.combine(crop.origin.y)
        hasher.combine(crop.size.width)
        hasher.combine(crop.size.height)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ThumbnailCacheKey else { return false }
        return data.isEqual(other.data) && crop == other.crop
    }
}

#Preview {
    SessionMediaThumbnailView(imageData: nil, isVideo: true)
        .frame(width: 120, height: 120)
        .background(Theme.background)
}
