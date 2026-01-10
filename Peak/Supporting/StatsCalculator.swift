import Foundation

struct StatsSummary {
    let totalSessions: Int
    let averageRating: Double
    let topSpots: [CountedItem]
    let topGear: [CountedItem]
    let topBuddies: [CountedItem]
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
