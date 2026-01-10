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
    let monthlyCounts: [MonthlyCount]
    let currentWeekStreak: Int
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
            monthlyCounts: monthlyCounts,
            currentWeekStreak: streak
        )
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
