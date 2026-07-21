import Foundation
import SwiftData

@Model
final class Spot {
    @Attribute(.unique) var key: String
    var name: String
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    /// NOAA CO-OPS station id for US spots, resolved once and cached here so the
    /// (large) station directory is downloaded at most once per spot. `nil` means
    /// "not looked up yet, or this spot is outside NOAA's coverage" — the two are
    /// deliberately indistinguishable, because both fall back to the same
    /// Open-Meteo tide curve and neither is an error worth surfacing.
    var tideStationId: String?
    var createdAt: Date

    init(
        name: String,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        tideStationId: String? = nil,
        createdAt: Date = Date()
    ) {
        let cleaned = name.trimmedNonEmpty ?? "Unknown"
        self.name = cleaned
        self.key = Spot.makeKey(from: cleaned)
        self.locationName = locationName?.trimmedNonEmpty
        self.latitude = latitude
        self.longitude = longitude
        self.tideStationId = tideStationId?.trimmedNonEmpty
        self.createdAt = createdAt
    }

    static func makeKey(from name: String) -> String {
        name.normalizedKey
    }

    /// Soft cap on saved surf breaks. Raised from 10 (which blocked traveling
    /// surfers) to a generous ceiling that still guards against runaway data.
    /// All user-facing copy interpolates this value, so it stays in sync.
    static let maxCount = 200
}
