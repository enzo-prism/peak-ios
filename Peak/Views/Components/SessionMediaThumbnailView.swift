import SwiftUI
import UIKit

struct SessionMediaThumbnailView: View {
    let imageData: Data?
    let isVideo: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
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
        // Decode + prepare off the main thread so scrolling stays smooth. `task(id:)` reloads
        // when the underlying data changes and cancels the previous decode.
        .task(id: imageData) {
            image = await Self.decodedImage(from: imageData)
        }
    }

    private static func decodedImage(from data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let raw = UIImage(data: data) else { return nil }
            return raw.preparingForDisplay() ?? raw
        }.value
    }
}

#Preview {
    SessionMediaThumbnailView(imageData: nil, isVideo: true)
        .frame(width: 120, height: 120)
        .background(Theme.background)
}
