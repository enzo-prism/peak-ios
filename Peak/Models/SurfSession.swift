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
    /// Tide height relative to mean sea level, in metres. Legitimately negative
    /// below MSL, so it is never sanity-checked for sign.
    var seaLevelHeightM: Double?
    /// `TideTrend.rawValue`. Stored as a string — see `TideTrend` for why.
    var tideTrend: String?
    var conditionsSource: String?
    var conditionsFetchedAt: Date?
    var conditionsLatitude: Double?
    var conditionsLongitude: Double?
    // MARK: Wave stats (3.0)
    // Every one of these is an *estimate* until the user says otherwise — see
    // `waveStatsSource`. They are stored rather than recomputed because the route
    // they came from lives in HealthKit, which may be revoked, disabled, or simply
    // slow; a logged session must keep its numbers regardless.
    var waveCount: Int?
    var topSpeedKph: Double?
    var longestRideSeconds: Double?
    var longestRideMeters: Double?
    var paddleDistanceMeters: Double?
    /// `WaveStatsSource.rawValue`. Stored as a string — see `WaveStatsSource`.
    var waveStatsSource: String?
    /// UUID string of the HealthKit workout the stats were derived from, so the
    /// route can be re-fetched live for the map without persisting coordinates.
    var linkedWorkoutID: String?
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
        seaLevelHeightM: Double? = nil,
        tideTrend: String? = nil,
        conditionsSource: String? = nil,
        conditionsFetchedAt: Date? = nil,
        conditionsLatitude: Double? = nil,
        conditionsLongitude: Double? = nil,
        waveCount: Int? = nil,
        topSpeedKph: Double? = nil,
        longestRideSeconds: Double? = nil,
        longestRideMeters: Double? = nil,
        paddleDistanceMeters: Double? = nil,
        waveStatsSource: String? = nil,
        linkedWorkoutID: String? = nil,
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
        self.seaLevelHeightM = seaLevelHeightM
        self.tideTrend = tideTrend
        self.conditionsSource = conditionsSource
        self.conditionsFetchedAt = conditionsFetchedAt
        self.conditionsLatitude = conditionsLatitude
        self.conditionsLongitude = conditionsLongitude
        self.waveCount = waveCount
        self.topSpeedKph = topSpeedKph
        self.longestRideSeconds = longestRideSeconds
        self.longestRideMeters = longestRideMeters
        self.paddleDistanceMeters = paddleDistanceMeters
        self.waveStatsSource = waveStatsSource
        self.linkedWorkoutID = linkedWorkoutID
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
        seaLevelHeightM != nil ||
        tideTrend != nil ||
        conditionsSource != nil ||
        conditionsFetchedAt != nil
    }

    /// Typed view of the stored raw value. An unrecognised string reads as `nil`
    /// rather than throwing, so a row written by a newer build stays readable.
    var tide: TideTrend? {
        get { tideTrend.flatMap(TideTrend.init(rawValue:)) }
        set { tideTrend = newValue?.rawValue }
    }

    // MARK: Wave stats

    /// Typed view of `waveStatsSource`, same forward-compatible reading as `tide`.
    var waveStats: WaveStatsSource? {
        get { waveStatsSource.flatMap(WaveStatsSource.init(rawValue:)) }
        set { waveStatsSource = newValue?.rawValue }
    }

    var hasWaveStats: Bool {
        waveCount != nil ||
        topSpeedKph != nil ||
        longestRideSeconds != nil ||
        longestRideMeters != nil ||
        paddleDistanceMeters != nil
    }

    /// Writes analyzer output onto the session.
    ///
    /// Refuses to touch a session whose stats the user has already corrected or
    /// typed in: re-importing a workout must never silently overwrite a human's
    /// own count. Returns whether anything was written, so callers can report
    /// honestly.
    @discardableResult
    func applyDerivedWaveStats(_ stats: WaveStats, workoutID: String?, force: Bool = false) -> Bool {
        let existing = waveStats
        guard force || existing == nil || existing == .auto else { return false }

        waveCount = stats.waveCount
        // A session with no detected ride still has a meaningful paddle distance,
        // but zero top speed / zero longest ride are not facts worth displaying —
        // store nil so the UI can omit the row rather than print "0.0 km/h".
        topSpeedKph = stats.topSpeedKph > 0 ? stats.topSpeedKph : nil
        longestRideSeconds = stats.longestRideSeconds > 0 ? stats.longestRideSeconds : nil
        longestRideMeters = stats.longestRideMeters > 0 ? stats.longestRideMeters : nil
        paddleDistanceMeters = stats.paddleDistanceMeters > 0 ? stats.paddleDistanceMeters : nil
        waveStats = .auto
        linkedWorkoutID = workoutID
        return true
    }

    /// Marks the stats as human-owned. Called by the editor whenever any wave
    /// field is changed, which is what stops a later import from clobbering them.
    func markWaveStatsEdited() {
        // A session that never had derived stats and is being filled in by hand is
        // `manual`; one that started from a route and was corrected is `edited`.
        // The distinction drives the microcopy, and only that.
        switch waveStats {
        case .auto, .edited: waveStats = .edited
        case .manual, .none: waveStats = linkedWorkoutID == nil ? .manual : .edited
        }
    }

    /// Drops every wave stat, including the source marker and workout link.
    func clearWaveStats() {
        waveCount = nil
        topSpeedKph = nil
        longestRideSeconds = nil
        longestRideMeters = nil
        paddleDistanceMeters = nil
        waveStatsSource = nil
        linkedWorkoutID = nil
    }
}
