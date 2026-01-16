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
    var createdAt: Date

    init(
        kind: SessionMediaKind,
        photoData: Data? = nil,
        thumbnailData: Data? = nil,
        videoFileName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.photoData = photoData
        self.thumbnailData = thumbnailData
        self.videoFileName = videoFileName
        self.createdAt = createdAt
    }
}
