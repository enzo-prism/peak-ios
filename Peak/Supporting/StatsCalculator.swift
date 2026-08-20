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
        var ratingSum = 0
        var ratingCount = 0
        var spotItems: [(key: String, name: String, detail: String?)] = []
        var gearItems: [(key: String, name: String, detail: String?)] = []
        var buddyItems: [(key: String, name: String, detail: String?)] = []
        spotItems.reserveCapacity(sessions.count)
        gearItems.reserveCapacity(sessions.count)
        buddyItems.reserveCapacity(sessions.count)

        for session in sessions {
            if session.rating > 0 {
                ratingSum += session.rating
                ratingCount += 1
            }
            if let spot = session.spot {
                spotItems.append((spot.key, spot.name, nil))
            }
            for item in session.gear {
                gearItems.append((item.key, item.name, item.kind.label))
            }
            for buddy in session.buddies {
                buddyItems.append((buddy.key, buddy.name, nil))
            }
        }

        let averageRating = ratingCount == 0 ? 0 : Double(ratingSum) / Double(ratingCount)
        return StatsSummary(
            totalSessions: sessions.count,
            averageRating: averageRating,
            topSpots: topCounted(items: spotItems, topLimit: topLimit),
            topGear: topCounted(items: gearItems, topLimit: topLimit),
            topBuddies: topCounted(items: buddyItems, topLimit: topLimit)
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
        // Streak counts an unbroken run of weeks that each have at least one
        // session, computed over ALL sessions (not just this year) so a run
        // spanning a year boundary isn't truncated. When the current week has no
        // session yet, the walk starts from the most recent completed week, so a
        // brand-new week doesn't reset the streak to 0 before you've surfed.
        let allWeekStarts = Set(sessions.compactMap { session in
            calendar.dateInterval(of: .weekOfYear, for: session.date)?.start
        })
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        var streak = 0
        if let currentWeekStart {
            var cursor: Date? = allWeekStarts.contains(currentWeekStart)
                ? currentWeekStart
                : calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)
            while let weekStart = cursor, allWeekStarts.contains(weekStart) {
                streak += 1
                cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)
            }
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
                detail: "\(rest.count) spot\(rest.count == 1 ? "" : "s")",
                count: otherCount
            ))
        }
        return result
    }

    /// Rated sessions that also carry a measured wave height, oldest first.
    /// Caps at `limit` most-recent samples so Swift Charts is not asked to
    /// plot an unbounded PointMark set (WWDC: keep mark counts in the
    /// hundreds, not the thousands).
    static let maxWaveHeightRatingSamples = 200

    static func waveHeightRatingSamples(
        sessions: [SurfSession],
        limit: Int = maxWaveHeightRatingSamples
    ) -> [WaveRatingSample] {
        let eligible = sessions.filter { $0.rating > 0 && $0.waveHeightMeters != nil }
        let trimmed: [SurfSession]
        if eligible.count <= limit {
            trimmed = eligible.sorted { $0.date < $1.date }
        } else {
            trimmed = Array(eligible.sorted { $0.date > $1.date }.prefix(limit))
                .sorted { $0.date < $1.date }
        }
        return trimmed.enumerated().map { index, session in
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
        var counts: [String: Int] = [:]
        var meta: [String: (name: String, detail: String?)] = [:]
        counts.reserveCapacity(items.count)
        for item in items {
            counts[item.key, default: 0] += 1
            if meta[item.key] == nil {
                meta[item.key] = (item.name, item.detail)
            }
        }

        let counted = counts.compactMap { key, count -> CountedItem? in
            guard let info = meta[key] else { return nil }
            return CountedItem(key: key, name: info.name, detail: info.detail, count: count)
        }

        return counted.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                // Final `key` tiebreak keeps ordering stable when two items
                // share both a count and a display name (e.g. duplicate names).
                if lhs.name == rhs.name {
                    return lhs.key < rhs.key
                }
                return lhs.name < rhs.name
            }
            return lhs.count > rhs.count
        }.prefix(topLimit).map { $0 }
    }
}
