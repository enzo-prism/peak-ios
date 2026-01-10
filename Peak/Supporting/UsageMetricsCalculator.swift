import Foundation

struct UsageSummary {
    let count: Int
    let lastUsed: Date?
    let averageRating: Double
    let monthlyCounts: [MonthlyCount]
}

struct UsageSnapshot {
    let count: Int
    let lastUsed: Date?
    let averageRating: Double
}

struct MonthlyCount: Identifiable {
    let month: Date
    let count: Int

    var id: Date { month }
}

enum UsageMetricsCalculator {
    static func metrics(for sessions: [SurfSession], calendar: Calendar = .current) -> UsageSummary {
        let count = sessions.count
        let lastUsed = sessions.map(\.date).max()
        let rated = sessions.filter { $0.rating > 0 }
        let averageRating = rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
        let monthlyCounts = monthlyUsageCounts(sessions: sessions, monthsBack: 12, calendar: calendar)
        return UsageSummary(count: count, lastUsed: lastUsed, averageRating: averageRating, monthlyCounts: monthlyCounts)
    }

    static func monthlyUsageCounts(
        sessions: [SurfSession],
        monthsBack: Int,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [MonthlyCount] {
        guard monthsBack > 0 else { return [] }
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate
        let monthStarts = (0..<monthsBack).compactMap { offset -> Date? in
            calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
        }.sorted()

        var counts: [Date: Int] = [:]
        for session in sessions {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: session.date)) ?? session.date
            counts[monthStart, default: 0] += 1
        }

        return monthStarts.map { month in
            MonthlyCount(month: month, count: counts[month, default: 0])
        }
    }

    static func gearSnapshots(sessions: [SurfSession]) -> [String: UsageSnapshot] {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        var ratings: [String: [Int]] = [:]

        for session in sessions {
            for gear in session.gear {
                counts[gear.key, default: 0] += 1
                if let existing = lastUsed[gear.key] {
                    if session.date > existing {
                        lastUsed[gear.key] = session.date
                    }
                } else {
                    lastUsed[gear.key] = session.date
                }
                if session.rating > 0 {
                    ratings[gear.key, default: []].append(session.rating)
                }
            }
        }

        var snapshots: [String: UsageSnapshot] = [:]
        for (key, count) in counts {
            let last = lastUsed[key]
            let values = ratings[key] ?? []
            let average = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
            snapshots[key] = UsageSnapshot(count: count, lastUsed: last, averageRating: average)
        }
        return snapshots
    }

    static func spotSnapshots(sessions: [SurfSession]) -> [String: UsageSnapshot] {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        var ratings: [String: [Int]] = [:]

        for session in sessions {
            guard let spot = session.spot else { continue }
            counts[spot.key, default: 0] += 1
            if let existing = lastUsed[spot.key] {
                if session.date > existing {
                    lastUsed[spot.key] = session.date
                }
            } else {
                lastUsed[spot.key] = session.date
            }
            if session.rating > 0 {
                ratings[spot.key, default: []].append(session.rating)
            }
        }

        var snapshots: [String: UsageSnapshot] = [:]
        for (key, count) in counts {
            let last = lastUsed[key]
            let values = ratings[key] ?? []
            let average = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
            snapshots[key] = UsageSnapshot(count: count, lastUsed: last, averageRating: average)
        }
        return snapshots
    }

    static func buddySnapshots(sessions: [SurfSession]) -> [String: UsageSnapshot] {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        var ratings: [String: [Int]] = [:]

        for session in sessions {
            for buddy in session.buddies {
                counts[buddy.key, default: 0] += 1
                if let existing = lastUsed[buddy.key] {
                    if session.date > existing {
                        lastUsed[buddy.key] = session.date
                    }
                } else {
                    lastUsed[buddy.key] = session.date
                }
                if session.rating > 0 {
                    ratings[buddy.key, default: []].append(session.rating)
                }
            }
        }

        var snapshots: [String: UsageSnapshot] = [:]
        for (key, count) in counts {
            let last = lastUsed[key]
            let values = ratings[key] ?? []
            let average = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
            snapshots[key] = UsageSnapshot(count: count, lastUsed: last, averageRating: average)
        }
        return snapshots
    }

    static func surfDayCountsByMonth(
        sessions: [SurfSession],
        year: Int,
        calendar: Calendar = .current
    ) -> [MonthlyCount] {
        let months = (1...12).compactMap { month -> Date? in
            var components = DateComponents()
            components.year = year
            components.month = month
            return calendar.date(from: components)
        }

        let daySet = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        var counts: [Date: Int] = [:]
        for day in daySet {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            counts[monthStart, default: 0] += 1
        }

        return months.map { month in
            MonthlyCount(month: month, count: counts[month, default: 0])
        }
    }
}
