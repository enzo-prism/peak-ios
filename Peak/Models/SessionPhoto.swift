import Foundation
import SwiftData

@Model
final class SessionPhoto {
    @Attribute(.externalStorage) var data: Data
    var sortIndex: Int
    var createdAt: Date

    init(data: Data, sortIndex: Int, createdAt: Date = Date()) {
        self.data = data
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
