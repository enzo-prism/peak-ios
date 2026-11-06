import Foundation

/// The final facts about a watch-recorded session, in a form that survives the
/// trip to the iPhone as a file.
///
/// This is the **fallback** path, not the primary one. The primary path is the
/// HealthKit save: the watch finishes an `HKWorkout`, HealthKit syncs it (with
/// its GPS route) to the phone, and the phone's existing import + `WaveAnalyzer`
/// derive everything. That path needs no payload at all.
///
/// The payload closes the phone's live display after an interrupted mirror.
/// WatchConnectivity queues it until the counterpart becomes available.
///
/// It is explicitly *not* a source of truth. Every field here is a convenience
/// copy of something HealthKit already holds; if the two ever disagree,
/// HealthKit wins. That rule is what makes a mirror failure incapable of losing
/// a session.
nonisolated struct SurfSessionHandoff: Codable, Equatable, Sendable {
    /// Bumped if the payload shape ever changes, so an old watch build talking
    /// to a new phone build is detectable rather than silently mis-decoded.
    static let currentVersion = 1

    var version: Int
    var startDate: Date
    var endDate: Date
    /// Active surf time, excluding paused stretches. May be well under
    /// `endDate - startDate` when the surfer paused for a beer.
    var activeDuration: TimeInterval
    /// UUID of the saved `HKWorkout`, when the save succeeded. The phone
    /// prefers to look this up in HealthKit rather than trust anything below.
    var workoutUUID: UUID?
    var totalDistanceMeters: Double?
    var averageHeartRate: Double?
    /// First GPS fix of the session, used to guess the spot. Nil when the watch
    /// never got a fix (paddled out before GPS locked, or location denied).
    var routeStartLatitude: Double?
    var routeStartLongitude: Double?

    init(
        version: Int = SurfSessionHandoff.currentVersion,
        startDate: Date,
        endDate: Date,
        activeDuration: TimeInterval,
        workoutUUID: UUID? = nil,
        totalDistanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        routeStartLatitude: Double? = nil,
        routeStartLongitude: Double? = nil
    ) {
        self.version = version
        self.startDate = startDate
        self.endDate = endDate
        self.activeDuration = activeDuration
        self.workoutUUID = workoutUUID
        self.totalDistanceMeters = totalDistanceMeters
        self.averageHeartRate = averageHeartRate
        self.routeStartLatitude = routeStartLatitude
        self.routeStartLongitude = routeStartLongitude
    }

    /// Duration in the whole minutes the session editor works in.
    var activeMinutes: Int {
        guard activeDuration.isFinite, activeDuration > 0, activeDuration / 60 < Double(Int.max) else { return 0 }
        return Int((activeDuration / 60).rounded())
    }

    /// Saved workout identity prevents same-second recordings from colliding.
    /// Legacy unsaved payloads retain a stable timing-based name.
    var transferFileName: String {
        "peak-session-\(workoutUUID?.uuidString ?? String(startDate.timeIntervalSince1970)).json"
    }

    /// Marks the transfer so the phone can tell a Peak handoff from any other
    /// file the system might deliver.
    static let metadataKind = "com.designprism.peak.sessionHandoff"
    static let metadataKindKey = "kind"
}

/// Formats a running workout clock for the watch face.
///
/// Separate from the app's `SessionDurationFormatter` ("1h 12m") on purpose:
/// that one summarises a finished session in prose, this one is a live clock
/// that has to tick seconds and stay a fixed width so the digits don't jitter.
nonisolated enum SurfWorkoutClockFormatter {
    /// `m:ss` under an hour, `h:mm:ss` past it.
    ///
    /// Negative and non-finite intervals clamp to zero rather than rendering
    /// nonsense — a clock is never a useful place to surface a bug.
    static func string(from interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0, interval < Double(Int.max) else { return "0:00" }
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
