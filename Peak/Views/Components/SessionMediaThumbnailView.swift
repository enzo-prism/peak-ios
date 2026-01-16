import SwiftUI
import UIKit

struct SessionMediaThumbnailView: View {
    let imageData: Data?
    let isVideo: Bool

    var body: some View {
        ZStack {
            if let imageData, let image = UIImage(data: imageData) {
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
    }
}

#Preview {
    SessionMediaThumbnailView(imageData: nil, isVideo: true)
        .frame(width: 120, height: 120)
        .background(Theme.background)
}
