import SwiftUI
import UIKit

struct SessionMediaThumbnailView: View {
    let imageData: Data?
    let isVideo: Bool
    @State private var decodedImage: UIImage?

    var body: some View {
        ZStack {
            if let image = decodedImage ?? ThumbnailImageCache.shared.cachedImage(for: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.glassDimTint)
                Image(systemName: isVideo ? "video" : "photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }

            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
        .task(id: imageData) {
            decodedImage = await ThumbnailImageCache.shared.image(for: imageData)
        }
    }
}

/// Decodes thumbnails off the main thread once and reuses the prepared bitmap,
/// so scrolling a media grid never re-decodes JPEG data during rendering.
final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    private let cache = NSCache<NSData, UIImage>()

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for data: Data?) -> UIImage? {
        guard let data else { return nil }
        return cache.object(forKey: data as NSData)
    }

    func image(for data: Data?) async -> UIImage? {
        guard let data else { return nil }
        if let cached = cache.object(forKey: data as NSData) {
            return cached
        }
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
        if let decoded {
            let cost = decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
            cache.setObject(decoded, forKey: data as NSData, cost: cost)
        }
        return decoded
    }
}

#Preview {
    SessionMediaThumbnailView(imageData: nil, isVideo: true)
        .frame(width: 120, height: 120)
        .background(Theme.background)
}
