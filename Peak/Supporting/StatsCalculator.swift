import Foundation

struct StatsSummary {
    let totalSessions: Int
    let averageRating: Double
    let topSpots: [CountedItem]
    let topGear: [CountedItem]
    let topBuddies: [CountedItem]
}

struct SurfYearSummary {
    let year: Int
    let totalDays: Int
    let totalSessions: Int
    let monthlyCounts: [MonthlyCount]
    let currentWeekStreak: Int
}

/// Aggregated `durationMinutes` across sessions. Sessions without a logged
/// duration are excluded from the average.
struct SurfTimeSummary: Equatable {
    let totalMinutes: Int
    let averageMinutes: Int?
    let sessionsWithDuration: Int
}

/// One day cell in the consistency heatmap grid. `weekdayIndex` is the offset
/// from the calendar's first weekday (0...6), so rows follow the user's locale.
struct SessionHeatmapCell: Identifiable, Equatable {
    let day: Date
    let weekStart: Date
    let weekdayIndex: Int
    let count: Int

    var id: Date { day }
}

/// A rated session that also carries a measured wave height.
struct WaveRatingSample: Identifiable, Equatable {
    let id: Int
    let waveHeightMeters: Double
    let rating: Int
}

/// The highest-rated conditions bucket, phrased for display
/// (e.g. "11 s+ swell on calm days").
struct ConditionsInsight: Equatable {
    let summary: String
    let averageRating: Double
    let sessionCount: Int
}

struct CountedItem: Identifiable {
    let key: String
    let name: String
    let detail: String?
    let count: Int

    var id: String { key }
}

enum StatsCalculator {
    static func summarize(sessions: [SurfSession], topLimit: Int = 3) -> StatsSummary {
        let totalSessions = sessions.count
        let ratings = sessions.map { $0.rating }.filter { $0 > 0 }
        let averageRating = ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)

        let topSpots = topCounted(
            items: sessions.compactMap { $0.spot }.map { (key: $0.key, name: $0.name, detail: nil) },
            topLimit: topLimit
        )

        let topGear = topCounted(
            items: sessions.flatMap { $0.gear }.map { (key: $0.key, name: $0.name, detail: $0.kind.label) },
            topLimit: topLimit
        )

        let topBuddies = topCounted(
            items: sessions.flatMap { $0.buddies }.map { (key: $0.key, name: $0.name, detail: nil) },
            topLimit: topLimit
        )

        return StatsSummary(
            totalSessions: totalSessions,
            averageRating: averageRating,
            topSpots: topSpots,
            topGear: topGear,
            topBuddies: topBuddies
        )
    }

    static func surfDaysThisYear(
        sessions: [SurfSession],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> SurfYearSummary {
        let year = calendar.component(.year, from: referenceDate)
        let yearInterval = calendar.dateInterval(of: .year, for: referenceDate)
        let yearSessions = sessions.filter { session in
            if let interval = yearInterval {
                return interval.contains(session.date)
            }
            return calendar.component(.year, from: session.date) == year
        }

        let surfDays = Set(yearSessions.map { calendar.startOfDay(for: $0.date) })
        let totalDays = surfDays.count
        let monthlyCounts = UsageMetricsCalculator.surfDayCountsByMonth(
            sessions: yearSessions,
            year: year,
            calendar: calendar
        )
        let weekStarts = Set(surfDays.compactMap { day in
            calendar.dateInterval(of: .weekOfYear, for: day)?.start
        })
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        var streak = 0
        var cursor = currentWeekStart
        while let weekStart = cursor, weekStarts.contains(weekStart) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)
        }

        return SurfYearSummary(
            year: year,
            totalDays: totalDays,
            totalSessions: yearSessions.count,
            monthlyCounts: monthlyCounts,
            currentWeekStreak: streak
        )
    }

    /// Totals `durationMinutes` across every session that logged one.
    static func timeInWater(sessions: [SurfSession]) -> SurfTimeSummary {
        let durations = sessions.compactMap { $0.durationMinutes }.filter { $0 > 0 }
        let totalMinutes = durations.reduce(0, +)
        let averageMinutes = durations.isEmpty
            ? nil
            : Int((Double(totalMinutes) / Double(durations.count)).rounded())
        return SurfTimeSummary(
            totalMinutes: totalMinutes,
            averageMinutes: averageMinutes,
            sessionsWithDuration: durations.count
        )
    }

    /// Longest run of consecutive calendar weeks (ever) with at least one session.
    static func longestWeekStreak(
        sessions: [SurfSession],
        calendar: Calendar = .current
    ) -> Int {
        let weekStarts = Set(sessions.compactMap { session in
            calendar.dateInterval(of: .weekOfYear, for: session.date)?.start
        })
        var longest = 0
        for start in weekStarts {
            // Only walk forward from the first week of each run.
            if let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: start),
               weekStarts.contains(previous) {
                continue
            }
            var length = 0
            var cursor: Date? = start
            while let week = cursor, weekStarts.contains(week) {
                length += 1
                cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: week)
            }
            longest = max(longest, length)
        }
        return longest
    }

    /// A complete day grid (including zero-count days) covering the last
    /// `weeksBack` calendar weeks, trimmed to today in the current week.
    static func sessionHeatmap(
        sessions: [SurfSession],
        weeksBack: Int = 20,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [SessionHeatmapCell] {
        guard weeksBack > 0,
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeksBack - 1), to: currentWeek)
        else { return [] }

        var counts: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            guard day >= firstWeek else { continue }
            counts[day, default: 0] += 1
        }

        let lastDay = calendar.startOfDay(for: referenceDate)
        var cells: [SessionHeatmapCell] = []
        var weekCursor = firstWeek
        while weekCursor <= currentWeek {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekCursor),
                      day <= lastDay
                else { break }
                cells.append(SessionHeatmapCell(
                    day: day,
                    weekStart: weekCursor,
                    weekdayIndex: offset,
                    count: counts[day, default: 0]
                ))
            }
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekCursor) else { break }
            weekCursor = nextWeek
        }
        return cells
    }

    /// Distinct surf days per month over a rolling window ending at
    /// `referenceDate`. The window grows back to the earliest session,
    /// clamped to `minMonthsBack...maxMonthsBack`.
    static func monthlySurfDays(
        sessions: [SurfSession],
        minMonthsBack: Int = 12,
        maxMonthsBack: Int = 36,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [MonthlyCount] {
        guard minMonthsBack > 0, maxMonthsBack >= minMonthsBack else { return [] }
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ) ?? referenceDate

        var monthsBack = minMonthsBack
        if let earliest = sessions.map({ $0.date }).min() {
            let earliestMonthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: earliest)
            ) ?? earliest
            let span = (calendar.dateComponents([.month], from: earliestMonthStart, to: currentMonthStart).month ?? 0) + 1
            monthsBack = min(max(span, minMonthsBack), maxMonthsBack)
        }

        let surfDays = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        var counts: [Date: Int] = [:]
        for day in surfDays {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            counts[monthStart, default: 0] += 1
        }

        return (0..<monthsBack)
            .compactMap { offset in
                calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
            }
            .sorted()
            .map { month in
                MonthlyCount(month: month, count: counts[month, default: 0])
            }
    }

    /// Sessions grouped by spot, top `topLimit` plus an "Other" bucket.
    /// Sessions without a spot are excluded.
    static func spotMix(sessions: [SurfSession], topLimit: Int = 5) -> [CountedItem] {
        let spots = sessions.compactMap { $0.spot }
        guard !spots.isEmpty else { return [] }
        let counted = topCounted(
            items: spots.map { (key: $0.key, name: $0.name, detail: nil) },
            topLimit: Int.max
        )
        var result = Array(counted.prefix(topLimit))
        let rest = counted.dropFirst(topLimit)
        let otherCount = rest.reduce(0) { $0 + $1.count }
        if otherCount > 0 {
            result.append(CountedItem(
                key: "stats.spot-mix.other",
                name: "Other",
                detail: "\(rest.count) spots",
                count: otherCount
            ))
        }
        return result
    }

    /// Rated sessions that also carry a measured wave height, oldest first.
    static func waveHeightRatingSamples(sessions: [SurfSession]) -> [WaveRatingSample] {
        sessions
            .filter { $0.rating > 0 && $0.waveHeightMeters != nil }
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { index, session in
                WaveRatingSample(
                    id: index,
                    waveHeightMeters: session.waveHeightMeters ?? 0,
                    rating: session.rating
                )
            }
    }

    /// Buckets rated sessions by swell period and wind condition and returns
    /// the highest-average-rated bucket with at least `minSessions` sessions.
    /// Prefers combined (period + wind) buckets, then falls back to
    /// period-only, then wind-only buckets.
    static func bestConditions(
        sessions: [SurfSession],
        minSessions: Int = 3
    ) -> ConditionsInsight? {
        let rated = sessions.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return nil }

        var combined: [String: [Int]] = [:]
        var periodOnly: [String: [Int]] = [:]
        var windOnly: [String: [Int]] = [:]

        for session in rated {
            let period = session.swellWavePeriodSeconds.map(SwellPeriodBand.band(forSeconds:))
            let wind = session.windCondition
            if let period {
                periodOnly["\(period.label) swell", default: []].append(session.rating)
            }
            if let wind {
                windOnly[windPhrase(wind), default: []].append(session.rating)
            }
            if let period, let wind {
                combined["\(period.label) swell on \(windPhrase(wind))", default: []].append(session.rating)
            }
        }

        for grouping in [combined, periodOnly, windOnly] {
            if let best = bestBucket(in: grouping, minSessions: minSessions) {
                return best
            }
        }
        return nil
    }

    private static func bestBucket(
        in grouping: [String: [Int]],
        minSessions: Int
    ) -> ConditionsInsight? {
        grouping
            .filter { $0.value.count >= minSessions }
            .map { label, ratings in
                ConditionsInsight(
                    summary: label,
                    averageRating: Double(ratings.reduce(0, +)) / Double(ratings.count),
                    sessionCount: ratings.count
                )
            }
            .max { lhs, rhs in
                if lhs.averageRating != rhs.averageRating {
                    return lhs.averageRating < rhs.averageRating
                }
                if lhs.sessionCount != rhs.sessionCount {
                    return lhs.sessionCount < rhs.sessionCount
                }
                return lhs.summary > rhs.summary
            }
    }

    private static func windPhrase(_ wind: WindCondition) -> String {
        switch wind {
        case .calm:
            return "calm days"
        case .breezy:
            return "breezy days"
        case .windy:
            return "windy days"
        case .strong:
            return "strong-wind days"
        }
    }

    private static func topCounted(
        items: [(key: String, name: String, detail: String?)],
        topLimit: Int
    ) -> [CountedItem] {
        var counts: [String: CountedItem] = [:]
        for item in items {
            if let existing = counts[item.key] {
                counts[item.key] = CountedItem(
                    key: existing.key,
                    name: existing.name,
                    detail: existing.detail,
                    count: existing.count + 1
                )
            } else {
                counts[item.key] = CountedItem(
                    key: item.key,
                    name: item.name,
                    detail: item.detail,
                    count: 1
                )
            }
        }

        return counts.values.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.name < rhs.name
            }
            return lhs.count > rhs.count
        }.prefix(topLimit).map { $0 }
    }
}
