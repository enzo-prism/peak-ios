import Foundation
import SwiftData

@Model
final class SurfSession {
    var date: Date
    var spot: Spot?
    var notes: String
    var rating: Int
    var durationMinutes: Int?
    var windCondition: WindCondition?
    var waveHeight: WaveHeight?
    var windSpeedKph: Double?
    var windDirectionDegrees: Double?
    var waveHeightMeters: Double?
    var swellWaveHeightMeters: Double?
    var swellWavePeriodSeconds: Double?
    var swellWaveDirectionDegrees: Double?
    var windWaveHeightMeters: Double?
    var windWavePeriodSeconds: Double?
    var windWaveDirectionDegrees: Double?
    var seaSurfaceTemperatureC: Double?
    var conditionsSource: String?
    var conditionsFetchedAt: Date?
    var conditionsLatitude: Double?
    var conditionsLongitude: Double?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .nullify) var gear: [Gear]
    @Relationship(deleteRule: .nullify) var buddies: [Buddy]
    @Relationship(deleteRule: .cascade) var media: [SessionMedia]

    init(
        date: Date,
        spot: Spot?,
        gear: [Gear] = [],
        buddies: [Buddy] = [],
        media: [SessionMedia] = [],
        rating: Int = 0,
        durationMinutes: Int? = nil,
        windCondition: WindCondition? = nil,
        waveHeight: WaveHeight? = nil,
        windSpeedKph: Double? = nil,
        windDirectionDegrees: Double? = nil,
        waveHeightMeters: Double? = nil,
        swellWaveHeightMeters: Double? = nil,
        swellWavePeriodSeconds: Double? = nil,
        swellWaveDirectionDegrees: Double? = nil,
        windWaveHeightMeters: Double? = nil,
        windWavePeriodSeconds: Double? = nil,
        windWaveDirectionDegrees: Double? = nil,
        seaSurfaceTemperatureC: Double? = nil,
        conditionsSource: String? = nil,
        conditionsFetchedAt: Date? = nil,
        conditionsLatitude: Double? = nil,
        conditionsLongitude: Double? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.spot = spot
        self.gear = gear
        self.buddies = buddies
        self.media = media
        self.rating = max(0, min(5, rating))
        self.durationMinutes = SurfSession.normalizedDuration(durationMinutes)
        self.windCondition = windCondition
        self.waveHeight = waveHeight
        self.windSpeedKph = windSpeedKph
        self.windDirectionDegrees = windDirectionDegrees
        self.waveHeightMeters = waveHeightMeters
        self.swellWaveHeightMeters = swellWaveHeightMeters
        self.swellWavePeriodSeconds = swellWavePeriodSeconds
        self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
        self.windWaveHeightMeters = windWaveHeightMeters
        self.windWavePeriodSeconds = windWavePeriodSeconds
        self.windWaveDirectionDegrees = windWaveDirectionDegrees
        self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        self.conditionsSource = conditionsSource
        self.conditionsFetchedAt = conditionsFetchedAt
        self.conditionsLatitude = conditionsLatitude
        self.conditionsLongitude = conditionsLongitude
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Duration bounds shared by `normalizedDuration` and the editor's control.
    /// 8 hours covers marathon/multi-peak days; 5-minute steps keep short
    /// sessions honest without demanding to-the-minute precision.
    static let maxDurationMinutes = 480
    static let durationStepMinutes = 5

    static func normalizedDuration(_ minutes: Int?) -> Int? {
        guard let minutes, minutes > 0 else { return nil }
        let clamped = min(minutes, maxDurationMinutes)
        let step = durationStepMinutes
        let snapped = Int((Double(clamped) / Double(step)).rounded()) * step
        return max(step, min(snapped, maxDurationMinutes))
    }

    var hasSurfConditions: Bool {
        windSpeedKph != nil ||
        windDirectionDegrees != nil ||
        waveHeightMeters != nil ||
        swellWaveHeightMeters != nil ||
        swellWavePeriodSeconds != nil ||
        swellWaveDirectionDegrees != nil ||
        windWaveHeightMeters != nil ||
        windWavePeriodSeconds != nil ||
        windWaveDirectionDegrees != nil ||
        seaSurfaceTemperatureC != nil ||
        conditionsSource != nil ||
        conditionsFetchedAt != nil
    }
}
