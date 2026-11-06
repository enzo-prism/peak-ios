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
        return Report(comparisons: comparisons, excludedSessionCount: atSpot.count - comparable.count)
    }
}
