import Foundation

/// Swell-period bands, shared by the board report and the Best-Conditions card
/// so both name a period the same way. The thresholds follow how surfers talk
/// about swell rather than an even split: under 10 s is windswell you ride a
/// fish in, 13 s+ is the groundswell you reach for a step-up.
enum SwellPeriodBand: String, CaseIterable, Identifiable {
    case short
    case mid
    case long

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .short:
            return "Under 10 s"
        case .mid:
            return "10–13 s"
        case .long:
            return "13 s+"
        }
    }

    /// Adjective for the report headline, e.g. "short-period waist-high".
    nonisolated var phrase: String {
        switch self {
        case .short:
            return "short-period"
        case .mid:
            return "mid-period"
        case .long:
            return "long-period"
        }
    }

    nonisolated static func band(forSeconds seconds: Double) -> SwellPeriodBand {
        if seconds < 10 { return .short }
        if seconds < 13 { return .mid }
        return .long
    }
}

/// One bucketed slice of a board's history. `averageRating` is `nil` below the
/// sample floor: one 5★ session is not a pattern, and printing it as an average
/// would be misinformation rather than an insight.
struct GearRatingBucket: Identifiable, Equatable {
    let id: String
    let label: String
    let sessionCount: Int
    let averageRating: Double?

    var hasEnoughData: Bool { averageRating != nil }
}

/// The best-rated period × height combination for a board, once one clears the
/// sample floor. This is the report's one-line headline.
struct GearConditionsHighlight: Equatable {
    /// e.g. "short-period waist-high".
    let phrase: String
    let averageRating: Double
    let sessionCount: Int
}

struct GearReport: Identifiable, Equatable {
    let gearKey: String
    let gearName: String
    let sessionCount: Int
    let ratedSessionCount: Int
    let averageRating: Double?
    let waveHeightBuckets: [GearRatingBucket]
    let periodBuckets: [GearRatingBucket]
    let highlight: GearConditionsHighlight?

    var id: String { gearKey }

    /// False when nothing cleared the sample floor, so the surfaces can show an
    /// honest "keep logging" state instead of a grid of blanks.
    var hasBucketInsights: Bool {
        highlight != nil
            || waveHeightBuckets.contains(where: \.hasEnoughData)
            || periodBuckets.contains(where: \.hasEnoughData)
    }
}

/// Per-gear rating aggregates, bucketed by the two conditions a surfer actually
/// picks a board for: wave size and swell period. Every value is derived from
/// sessions on the fly — nothing is cached, so edits and deletes can't drift.
enum GearInsightsCalculator {
    /// Under three rated sessions a bucket average is noise. Everything below
    /// this floor reports `nil` and renders as "not enough data yet".
    static let minimumBucketSessions = 3

    static func report(
        for gear: Gear,
        sessions: [SurfSession],
        minimumBucketSessions: Int = minimumBucketSessions
    ) -> GearReport {
        let related = sessions.filter { session in
            session.gear.contains { $0.key == gear.key }
        }
        return report(for: gear, relatedSessions: related, minimumBucketSessions: minimumBucketSessions)
    }

    /// Same report, when the caller already isolated this board's sessions
    /// (one pass over the logbook in `reports(for:sessions:)`).
    private static func report(
        for gear: Gear,
        relatedSessions related: [SurfSession],
        minimumBucketSessions: Int
    ) -> GearReport {
        let rated = related.filter { $0.rating > 0 }

        var heightRatings: [WaveHeight: [Int]] = [:]
        var periodRatings: [SwellPeriodBand: [Int]] = [:]
        var combined: [String: CombinedBucket] = [:]

        for session in rated {
            let height = waveBand(for: session)
            let band = session.swellWavePeriodSeconds.map(SwellPeriodBand.band(forSeconds:))

            if let height {
                heightRatings[height, default: []].append(session.rating)
            }
            if let band {
                periodRatings[band, default: []].append(session.rating)
            }
            if let height, let band {
                let key = "\(band.rawValue)|\(height.rawValue)"
                var entry = combined[key] ?? CombinedBucket(band: band, height: height, ratings: [])
                entry.ratings.append(session.rating)
                combined[key] = entry
            }
        }

        // Canonical order (small → big, short → long) so the report reads like a
        // scale rather than a leaderboard.
        let waveHeightBuckets = WaveHeight.allCases.compactMap { height -> GearRatingBucket? in
            guard let ratings = heightRatings[height] else { return nil }
            return makeBucket(
                id: "height.\(height.rawValue)",
                label: height.label,
                ratings: ratings,
                minimum: minimumBucketSessions
            )
        }

        let periodBuckets = SwellPeriodBand.allCases.compactMap { band -> GearRatingBucket? in
            guard let ratings = periodRatings[band] else { return nil }
            return makeBucket(
                id: "period.\(band.rawValue)",
                label: band.label,
                ratings: ratings,
                minimum: minimumBucketSessions
            )
        }

        return GearReport(
            gearKey: gear.key,
            gearName: gear.name,
            sessionCount: related.count,
            ratedSessionCount: rated.count,
            averageRating: average(of: rated.map(\.rating)),
            waveHeightBuckets: waveHeightBuckets,
            periodBuckets: periodBuckets,
            highlight: bestCombination(in: combined, minimum: minimumBucketSessions)
        )
    }

    /// Reports for a set of gear, busiest first. Gear that was never logged is
    /// dropped — an empty report is noise on a summary card.
    static func reports(
        for gear: [Gear],
        sessions: [SurfSession],
        minimumBucketSessions: Int = minimumBucketSessions
    ) -> [GearReport] {
        var relatedByKey: [String: [SurfSession]] = [:]
        relatedByKey.reserveCapacity(gear.count)
        for session in sessions {
            // A session on two boards belongs to both reports, matching the
            // per-gear `filter` the single-item path uses.
            var seen = Set<String>()
            for item in session.gear where seen.insert(item.key).inserted {
                relatedByKey[item.key, default: []].append(session)
            }
        }

        return gear.compactMap { item -> GearReport? in
            guard let related = relatedByKey[item.key], !related.isEmpty else { return nil }
            return report(
                for: item,
                relatedSessions: related,
                minimumBucketSessions: minimumBucketSessions
            )
        }
        .sorted { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount {
                return lhs.sessionCount > rhs.sessionCount
            }
            return lhs.gearName < rhs.gearName
        }
    }

    /// Categorical size for a session: the logged band when there is one, else
    /// derived from the measured height so auto-filled sessions still count.
    static func waveBand(for session: SurfSession) -> WaveHeight? {
        if let logged = session.waveHeight {
            return logged
        }
        guard let meters = session.waveHeightMeters else { return nil }
        return waveBand(forMeters: meters)
    }

    /// Surfer-scale thresholds: waist is roughly hip-to-chest on a standing
    /// adult, overhead starts around 1.5 m of face.
    static func waveBand(forMeters meters: Double) -> WaveHeight {
        if meters < 0.6 { return .kneeHigh }
        if meters < 1.0 { return .waistHigh }
        if meters < 1.5 { return .shoulderHigh }
        if meters < 2.4 { return .overhead }
        return .wayOverhead
    }

    /// "Waist high" → "waist-high", for use inside a sentence.
    static func phrase(for height: WaveHeight) -> String {
        height.label.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - Private

    private struct CombinedBucket {
        let band: SwellPeriodBand
        let height: WaveHeight
        var ratings: [Int]
    }

    private static func makeBucket(
        id: String,
        label: String,
        ratings: [Int],
        minimum: Int
    ) -> GearRatingBucket {
        GearRatingBucket(
            id: id,
            label: label,
            sessionCount: ratings.count,
            averageRating: ratings.count >= minimum ? average(of: ratings) : nil
        )
    }

    private static func bestCombination(
        in combined: [String: CombinedBucket],
        minimum: Int
    ) -> GearConditionsHighlight? {
        combined.values
            .filter { $0.ratings.count >= minimum }
            .compactMap { entry -> GearConditionsHighlight? in
                guard let average = average(of: entry.ratings) else { return nil }
                return GearConditionsHighlight(
                    phrase: "\(entry.band.phrase) \(phrase(for: entry.height))",
                    averageRating: average,
                    sessionCount: entry.ratings.count
                )
            }
            // Highest average wins; ties go to the better-evidenced bucket, then
            // alphabetically so the headline never flickers between equals.
            .max { lhs, rhs in
                if lhs.averageRating != rhs.averageRating {
                    return lhs.averageRating < rhs.averageRating
                }
                if lhs.sessionCount != rhs.sessionCount {
                    return lhs.sessionCount < rhs.sessionCount
                }
                return lhs.phrase > rhs.phrase
            }
    }

    private static func average(of ratings: [Int]) -> Double? {
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }
}
