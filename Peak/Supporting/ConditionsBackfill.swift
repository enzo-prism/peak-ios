import Foundation
import SwiftData

/// Fills in the surf conditions for sessions that were logged without them.
///
/// This is what actually bootstraps the Best Window model. `WindowScorer` learns
/// from conditions, and a surfer who logged for a season before ever tapping
/// "Auto-fill Conditions" has a logbook full of ratings attached to nothing.
/// Open-Meteo serves roughly 92 days of past marine data, so most of a recent
/// season can be recovered in one explicit action.
///
/// **Explicit only.** Peak makes no network call the surfer did not ask for, and
/// this one is the largest the app can make — dozens of requests. It runs on a
/// tap, reports progress while it runs, and reports honestly what it managed
/// afterwards. It is never triggered by appearing, refreshing or launching.
enum ConditionsBackfill {

    /// Open-Meteo's marine archive horizon, matching `SurfConditionsService.fetch`.
    /// Older sessions are skipped rather than attempted: the request would fail
    /// with `outOfRange` and burn a round trip to learn what the calendar already
    /// says.
    static let maxPastDays = 92

    /// Assumed session length when none was recorded, in minutes. The fetch
    /// averages readings across the session window, so it needs *some* duration;
    /// an hour is the app's own common case and keeps the averaging window tight
    /// enough that a whole tide swing cannot wash out inside it.
    static let assumedDurationMinutes = 60

    /// Consecutive failures after which the run stops.
    ///
    /// One failure is a bad hour of data; three in a row is the network or the
    /// provider being down, and hammering it forty more times helps nobody. The
    /// summary says the run stopped early so the surfer can retry rather than
    /// conclude their history is unrecoverable.
    static let consecutiveFailureLimit = 3

    /// UTC, matching `SurfConditionsService.validateRange`.
    ///
    /// The archive horizon is the provider's, and the provider counts days in
    /// UTC. Measuring eligibility in the surfer's local calendar would let a
    /// session on the boundary pass here and fail there, which reads as a random
    /// failure rather than as an old session.
    static let horizonCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// Whether this session can be filled in, and is worth trying.
    ///
    /// The `hasSurfConditions` check is the load-bearing one: it is what
    /// guarantees a backfill can never overwrite a reading the surfer typed or
    /// corrected by hand. Only a session with no stored conditions at all is
    /// touched. The coarse Wind/Wave pickers are deliberately *not* part of that
    /// test and are never written — they are the surfer's own words about the
    /// day, and a model estimate does not get to replace them.
    static func isEligible(
        _ session: SurfSession,
        at spot: Spot,
        now: Date = Date(),
        calendar: Calendar = horizonCalendar
    ) -> Bool {
        guard session.spot?.persistentModelID == spot.persistentModelID else { return false }
        guard !session.hasSurfConditions else { return false }
        guard session.date <= now else { return false }

        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -maxPastDays, to: today) else { return false }
        return calendar.startOfDay(for: session.date) >= earliest
    }

    /// Eligible sessions, newest first.
    ///
    /// Newest first because recency is what a surfer is most likely to remember
    /// and most likely to want back, and because a run that stops early should
    /// have spent its requests on the sessions that matter most.
    static func eligibleSessions(
        from sessions: [SurfSession],
        at spot: Spot,
        now: Date = Date(),
        calendar: Calendar = horizonCalendar
    ) -> [SurfSession] {
        sessions
            .filter { isEligible($0, at: spot, now: now, calendar: calendar) }
            .sorted { $0.date > $1.date }
    }

    /// Writes a fetched snapshot onto a session.
    ///
    /// Deliberately narrower than `SessionDraft.applySurfConditions`: it writes
    /// only the numeric readings and their provenance, and leaves
    /// `windCondition` / `waveHeight` alone. Those are the surfer's own
    /// description of the day and outrank a model's.
    static func apply(_ snapshot: SurfConditionsSnapshot, to session: SurfSession) {
        session.windSpeedKph = snapshot.windSpeedKph
        session.windDirectionDegrees = snapshot.windDirectionDegrees
        session.waveHeightMeters = snapshot.waveHeightMeters
        session.swellWaveHeightMeters = snapshot.swellWaveHeightMeters
        session.swellWavePeriodSeconds = snapshot.swellWavePeriodSeconds
        session.swellWaveDirectionDegrees = snapshot.swellWaveDirectionDegrees
        session.windWaveHeightMeters = snapshot.windWaveHeightMeters
        session.windWavePeriodSeconds = snapshot.windWavePeriodSeconds
        session.windWaveDirectionDegrees = snapshot.windWaveDirectionDegrees
        session.seaSurfaceTemperatureC = snapshot.seaSurfaceTemperatureC
        session.seaLevelHeightM = snapshot.seaLevelHeightMeters
        session.tide = snapshot.tideTrend
        session.conditionsSource = snapshot.source
        session.conditionsFetchedAt = snapshot.fetchedAt
        session.conditionsLatitude = snapshot.latitude
        session.conditionsLongitude = snapshot.longitude
        session.updatedAt = Date()
    }

    /// What the run managed, in the surfer's terms.
    struct Summary: Sendable, Hashable {
        /// Sessions that came back with usable readings and were written.
        var filled: Int
        /// Sessions the run actually asked about (>= `filled`).
        var attempted: Int
        /// Sessions that were eligible when the run started.
        var eligible: Int
        /// True when the run gave up after `consecutiveFailureLimit` failures.
        var stoppedEarly: Bool

        /// One honest sentence. Never rounds up, never claims a session it did
        /// not write, and always says when it stopped short.
        var message: String {
            let noun = filled == 1 ? "session" : "sessions"
            if filled == 0 {
                if eligible == 0 {
                    return "Nothing to fill in — every session here already has its conditions."
                }
                return stoppedEarly
                    ? "Could not reach the surf report service. Nothing was filled in — try again later."
                    : "No past conditions were available for these sessions."
            }
            if stoppedEarly {
                return "Filled in \(filled) \(noun), then lost the surf report service. Tap again to carry on."
            }
            let remaining = eligible - filled
            if remaining > 0 {
                return "Filled in \(filled) of \(eligible) \(noun). The rest had no data available."
            }
            return "Filled in \(filled) \(noun)."
        }
    }
}
