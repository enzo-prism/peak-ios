import Foundation

/// Descriptive comparisons within one spot/size/period cohort. This is not a
/// causal claim about equipment or a forecast of a surfer's performance.
enum QuiverAdvisor {
    struct Comparison: Identifiable {
        let gear: Gear
        let sessions: [SurfSession]
        let averageRating: Double
        let standardError: Double
        var id: String { gear.key }
        var count: Int { sessions.count }
    }

    struct Report {
        let comparisons: [Comparison]
        let excludedSessionCount: Int
        var coverage: [Coverage] = []
        var suggestedBoard: Gear? {
            guard let first = comparisons.first else { return nil }
            // With one observed board there is no comparison to make.
            guard comparisons.count > 1 else { return nil }
            let second = comparisons[1]
            let uncertainty = 2 * sqrt(first.standardError * first.standardError
                                      + second.standardError * second.standardError)
            guard first.averageRating - second.averageRating > max(0.5, uncertainty) else { return nil }
            return first.gear
        }
    }

    struct Coverage: Identifiable {
        let gear: Gear
        let qualifyingCount: Int
        let sessions: [SurfSession]
        var id: String { gear.key }
    }

    /// Prefer an actionable comparison, otherwise the most recent surfed spot.
    static func preferredSpot(spots: [Spot], sessions: [SurfSession]) -> Spot? {
        let valid = Dictionary(spots.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: [String: Int]] = [:]
        for session in sessions where (1...5).contains(session.rating) {
            let boards = session.gear.filter { $0.kind == .board && !$0.isArchived }
            guard let key = session.spot?.key, valid[key] != nil, boards.count == 1,
                  session.gear.filter({ $0.kind == .board }).count == 1 else { continue }
            counts[key, default: [:]][boards[0].key, default: 0] += 1
        }
        let ready = counts.mapValues { $0.values.filter { $0 >= GearInsightsCalculator.minimumBucketSessions }.count }
        let useful = spots.filter { (ready[$0.key] ?? 0) >= 2 }.sorted {
            if ready[$0.key] != ready[$1.key] { return (ready[$0.key] ?? 0) > (ready[$1.key] ?? 0) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return useful.first ?? sessions.sorted { $0.date > $1.date }.compactMap { $0.spot.flatMap { valid[$0.key] } }.first ?? spots.first
    }

    static func compare(spot: Spot, height: WaveHeight?, period: SwellPeriodBand?,
                        gear: [Gear], sessions: [SurfSession]) -> Report {
        let candidates = gear.filter { $0.kind == .board && !$0.isArchived }
        let atSpot = sessions.filter { $0.spot?.key == spot.key && (1...5).contains($0.rating) }
        let comparable = atSpot.filter { session in
            // Unknown conditions cannot stand in for a matching condition.
            (height == nil || GearInsightsCalculator.waveBand(for: session) == height)
                && (period == nil || session.swellWavePeriodSeconds.map(SwellPeriodBand.band(forSeconds:)) == period)
                // A split-board surf cannot attribute its rating to one board.
                && session.gear.filter { $0.kind == .board }.count == 1
        }
        // Walk relationships once rather than rescanning the entire logbook for
        // every board. This remains linear as the quiver and library grow.
        let byBoard = Dictionary(grouping: comparable) { session in
            session.gear.first { $0.kind == .board }!.key
        }
        let comparisons = candidates.compactMap { board -> Comparison? in
            let evidence = byBoard[board.key] ?? []
            guard evidence.count >= GearInsightsCalculator.minimumBucketSessions else { return nil }
            let ratings = evidence.map { Double($0.rating) }
            let mean = ratings.reduce(0, +) / Double(ratings.count)
            let variance = ratings.reduce(0) { $0 + pow($1 - mean, 2) } / Double(ratings.count - 1)
            return Comparison(gear: board, sessions: evidence.sorted { $0.date > $1.date },
                              averageRating: mean, standardError: sqrt(variance / Double(ratings.count)))
        }.sorted {
            if $0.averageRating != $1.averageRating { return $0.averageRating > $1.averageRating }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }
        let coverage = candidates.map { board in
            Coverage(gear: board, qualifyingCount: byBoard[board.key]?.count ?? 0,
                     sessions: sessions.filter { $0.spot?.key == spot.key && $0.gear.contains { $0.key == board.key } }
                        .sorted { $0.date > $1.date })
        }.sorted { $0.gear.name.localizedStandardCompare($1.gear.name) == .orderedAscending }
        return Report(comparisons: comparisons, excludedSessionCount: atSpot.count - comparable.count, coverage: coverage)
    }
}
