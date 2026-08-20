import Foundation

/// One personal record, resolved to the session that set it.
struct WaveRecord: Identifiable, Equatable {
    /// Stable across recomputes: derived from the session's immutable `createdAt`.
    let id: String
    /// Formatted headline value, e.g. "14 waves".
    let value: String
    /// Spoken form for VoiceOver, which must not read "24 km/h" as glyphs.
    let spokenValue: String
    let spotName: String?
    let date: Date
    /// True when the record-setting session's numbers are still an unreviewed
    /// estimate. The UI marks those, because a personal record built on a guess
    /// is exactly the claim a user will call the app a liar over.
    let isEstimate: Bool
}

/// Personal records across the whole logbook. `nil` fields mean no session
/// carries that statistic at all.
struct WaveRecords: Equatable {
    var mostWaves: WaveRecord?
    var fastestWave: WaveRecord?
    var longestRide: WaveRecord?

    var isEmpty: Bool {
        mostWaves == nil && fastestWave == nil && longestRide == nil
    }
}

/// Average waves per session for one month.
struct WavesPerMonth: Identifiable, Equatable {
    let month: Date
    /// Mean wave count over the month's sessions that *have* a wave count.
    let averageWaves: Double
    /// How many sessions contributed, so the chart can be honest about a month
    /// whose "average" rests on a single session.
    let sessionCount: Int

    var id: Date { month }
}

/// Aggregates for the 3.0 wave statistics.
///
/// Stateless enum in the house style. Deliberately separate from
/// `StatsCalculator`: every function here has to reason about the fact that most
/// sessions carry no wave data at all, and folding that into the general
/// summariser would spread `if let` over code that has no business knowing.
enum WaveStatsCalculator {

    /// Personal records over sessions that have wave stats.
    ///
    /// Returns records only for statistics that actually exist. A logbook where
    /// nobody ever recorded a top speed gets a `fastestWave` of `nil` rather than
    /// a fabricated zero, and the Stats screen suppresses the whole row when
    /// everything is `nil`.
    static func records(sessions: [SurfSession]) -> WaveRecords {
        // One pass. Ties break toward the more recent session: a record you
        // just matched feels like yours, and it keeps the row changing as you
        // keep surfing.
        var bestWaves: SurfSession?
        var bestSpeed: SurfSession?
        var bestRide: SurfSession?

        for session in sessions {
            if let count = session.waveCount, count > 0,
               isBetter(count, date: session.date, than: bestWaves.flatMap(\.waveCount), date: bestWaves?.date) {
                bestWaves = session
            }
            if let speed = session.topSpeedKph, speed > 0,
               isBetter(speed, date: session.date, than: bestSpeed.flatMap(\.topSpeedKph), date: bestSpeed?.date) {
                bestSpeed = session
            }
            if let seconds = session.longestRideSeconds, seconds > 0,
               isBetter(seconds, date: session.date, than: bestRide.flatMap(\.longestRideSeconds), date: bestRide?.date) {
                bestRide = session
            }
        }

        var records = WaveRecords()
        if let best = bestWaves, let count = best.waveCount {
            records.mostWaves = record(
                for: best,
                value: WaveStatsFormatter.waveCount(count),
                spokenValue: WaveStatsFormatter.waveCount(count)
            )
        }
        if let best = bestSpeed, let speed = best.topSpeedKph {
            let formatted = WaveStatsFormatter.speed(speed)
            records.fastestWave = record(for: best, value: formatted, spokenValue: formatted)
        }
        if let best = bestRide, let seconds = best.longestRideSeconds {
            records.longestRide = record(
                for: best,
                value: WaveStatsFormatter.rideDuration(seconds),
                spokenValue: WaveStatsFormatter.spokenRideDuration(seconds)
            )
        }
        return records
    }

    /// `true` when `value` beats `current`, or matches it on a later date.
    private static func isBetter<T: Comparable>(
        _ value: T,
        date: Date,
        than current: T?,
        date currentDate: Date?
    ) -> Bool {
        guard let current, let currentDate else { return true }
        if value == current { return date > currentDate }
        return value > current
    }

    /// Average waves per session, by month, oldest first.
    ///
    /// Only months containing at least one session *with* a wave count appear —
    /// plotting a zero for every month before the user owned a watch would read
    /// as "you caught nothing all year", which is false rather than merely empty.
    static func wavesPerSession(
        sessions: [SurfSession],
        calendar: Calendar = .current
    ) -> [WavesPerMonth] {
        var buckets: [Date: (total: Int, count: Int)] = [:]

        for session in sessions {
            guard let waves = session.waveCount, waves >= 0 else { continue }
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: session.date)
            ) ?? session.date
            var bucket = buckets[monthStart] ?? (0, 0)
            bucket.total += waves
            bucket.count += 1
            buckets[monthStart] = bucket
        }

        return buckets
            .map { month, bucket in
                WavesPerMonth(
                    month: month,
                    averageWaves: bucket.count > 0 ? Double(bucket.total) / Double(bucket.count) : 0,
                    sessionCount: bucket.count
                )
            }
            .sorted { $0.month < $1.month }
    }

    /// Total waves ever recorded — the one wave figure that is safe to state
    /// plainly, because summing many estimates cancels most of the error.
    static func totalWaves(sessions: [SurfSession]) -> Int {
        sessions.reduce(0) { $0 + max(0, $1.waveCount ?? 0) }
    }

    /// Sessions that carry any wave statistic.
    static func sessionsWithWaveStats(_ sessions: [SurfSession]) -> Int {
        sessions.filter(\.hasWaveStats).count
    }

    private static func record(for session: SurfSession, value: String, spokenValue: String) -> WaveRecord {
        WaveRecord(
            id: HealthKitLogic.sessionKey(forSessionCreatedAt: session.createdAt),
            value: value,
            spokenValue: spokenValue,
            spotName: session.spot?.name,
            date: session.date,
            isEstimate: session.waveStats?.isEstimate ?? false
        )
    }
}
