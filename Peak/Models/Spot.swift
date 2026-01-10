import Foundation
import SwiftData

@Model
final class Spot {
    @Attribute(.unique) var key: String
    var name: String
    var createdAt: Date

    init(name: String, createdAt: Date = Date()) {
        let cleaned = name.trimmedNonEmpty ?? "Unknown"
        self.name = cleaned
        self.key = Spot.makeKey(from: cleaned)
        self.createdAt = createdAt
    }

    static func makeKey(from name: String) -> String {
        name.normalizedKey
    }
}
