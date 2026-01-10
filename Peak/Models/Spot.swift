import Foundation
import SwiftData

@Model
final class Spot {
    @Attribute(.unique) var key: String
    var name: String
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    init(
        name: String,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date()
    ) {
        let cleaned = name.trimmedNonEmpty ?? "Unknown"
        self.name = cleaned
        self.key = Spot.makeKey(from: cleaned)
        self.locationName = locationName?.trimmedNonEmpty
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }

    static func makeKey(from name: String) -> String {
        name.normalizedKey
    }

    static let maxCount = 10
}
