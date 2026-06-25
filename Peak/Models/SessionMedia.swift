import CoreGraphics
import Foundation
import SwiftData

enum SessionMediaKind: String, Codable {
    case photo
    case video
}

@Model
final class SessionMedia {
    var kind: SessionMediaKind
    @Attribute(.externalStorage) var photoData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var videoFileName: String?
    // Order of this item within its session (written from the draft array index on save).
    var sortIndex: Int = 0
    // Normalized preview crop rect (0...1). Default (0,0,1,1) == full frame == "never cropped",
    // so legacy items render exactly as before. Crop is preview-framing metadata only; the full
    // image/video is always shown uncropped in the media viewer.
    var cropOriginX: Double = 0
    var cropOriginY: Double = 0
    var cropWidth: Double = 1
    var cropHeight: Double = 1
    var createdAt: Date

    init(
        kind: SessionMediaKind,
        photoData: Data? = nil,
        thumbnailData: Data? = nil,
        videoFileName: String? = nil,
        sortIndex: Int = 0,
        cropOriginX: Double = 0,
        cropOriginY: Double = 0,
        cropWidth: Double = 1,
        cropHeight: Double = 1,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.photoData = photoData
        self.thumbnailData = thumbnailData
        self.videoFileName = videoFileName
        self.sortIndex = sortIndex
        self.cropOriginX = cropOriginX
        self.cropOriginY = cropOriginY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.createdAt = createdAt
    }

    /// The preview crop as a normalized rect. Non-stored convenience.
    var cropRect: CGRect {
        CGRect(x: cropOriginX, y: cropOriginY, width: cropWidth, height: cropHeight)
    }
}
