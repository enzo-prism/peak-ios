import Foundation

struct GearUsageSnapshot {
    let count: Int
    let lastUsed: Date?
}

struct GearTopSpot: Identifiable {
    let id: String
    let name: String
    let count: Int
}

struct GearUsageSummary {
    let totalUses: Int
    let firstUsed: Date?
    let lastUsed: Date?
    let averageRating: Double
    let topSpots: [GearTopSpot]
    let monthlyCounts: [MonthlyCount]
}

struct GearUsagePolicy {
    let canDelete: Bool
    let canArchive: Bool
}

enum GearUsageCalculator {
    static func snapshots(sessions: [SurfSession]) -> [String: GearUsageSnapshot] {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]

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
            }
        }

        var snapshots: [String: GearUsageSnapshot] = [:]
        for (key, count) in counts {
            snapshots[key] = GearUsageSnapshot(count: count, lastUsed: lastUsed[key])
        }
        return snapshots
    }

    static func summary(
        for gear: Gear,
        sessions: [SurfSession],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> GearUsageSummary {
        let relatedSessions = sessions.filter { session in
            session.gear.contains(where: { $0.key == gear.key })
        }

        let totalUses = relatedSessions.count
        let dates = relatedSessions.map(\.date)
        let firstUsed = dates.min()
        let lastUsed = dates.max()

        let ratedSessions = relatedSessions.filter { $0.rating > 0 }
        let averageRating: Double
        if ratedSessions.isEmpty {
            averageRating = 0
        } else {
            let total = ratedSessions.reduce(0) { $0 + $1.rating }
            averageRating = Double(total) / Double(ratedSessions.count)
        }

        var spotCounts: [String: (name: String, count: Int)] = [:]
        for session in relatedSessions {
            let key = session.spot?.key ?? "unknown"
            let name = session.spot?.name ?? "Unknown spot"
            var entry = spotCounts[key] ?? (name: name, count: 0)
            entry.count += 1
            spotCounts[key] = entry
        }

        let topSpots = spotCounts
            .map { GearTopSpot(id: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name < rhs.name
                }
                return lhs.count > rhs.count
            }
            .prefix(3)

        let monthlyCounts = UsageMetricsCalculator.monthlyUsageCounts(
            sessions: relatedSessions,
            monthsBack: 12,
            calendar: calendar,
            referenceDate: referenceDate
        )

        return GearUsageSummary(
            totalUses: totalUses,
            firstUsed: firstUsed,
            lastUsed: lastUsed,
            averageRating: averageRating,
            topSpots: Array(topSpots),
            monthlyCounts: monthlyCounts
        )
    }

    static func policy(for gear: Gear, sessions: [SurfSession]) -> GearUsagePolicy {
        let count = usageCount(for: gear, sessions: sessions)
        return GearUsagePolicy(canDelete: count == 0, canArchive: count > 0)
    }

    static func usageCount(for gear: Gear, sessions: [SurfSession]) -> Int {
        sessions.filter { session in
            session.gear.contains(where: { $0.key == gear.key })
        }.count
    }
}
