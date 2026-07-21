import Foundation

/// A named leader (spot or gear) with its session count.
struct YearInReviewLeader: Equatable {
    let name: String
    let count: Int
}

struct YearInReviewMonth: Equatable {
    let month: Date
    let count: Int
}

struct YearInReviewWaveSlice: Identifiable, Equatable {
    let height: WaveHeight
    let count: Int

    var id: String { height.rawValue }
}

/// Everything the recap screen and its share card render. Every field is
/// optional-or-zero safe, because a surfer with one logged session must still
/// get a recap that reads honestly rather than a wall of dashes.
struct YearInReview: Equatable {
    let year: Int
    let sessionCount: Int
    let surfDays: Int
    let totalMinutes: Int
    let averageRating: Double?
    let topSpot: YearInReviewLeader?
    let topGear: YearInReviewLeader?
    let bestMonth: YearInReviewMonth?
    let longestWeekStreak: Int
    let waveHeightDistribution: [YearInReviewWaveSlice]

    var isEmpty: Bool { sessionCount == 0 }

    /// Hours in water, rounded to one decimal for display.
    var hoursInWater: Double {
        (Double(totalMinutes) / 60 * 10).rounded() / 10
    }
}

/// Year-end aggregates over the logbook. Stateless; derived entirely from
/// existing session fields.
enum YearInReviewCalculator {
    static func summary(
        sessions: [SurfSession],
        year: Int,
        calendar: Calendar = .current
    ) -> YearInReview {
        let yearSessions = sessions.filter { calendar.component(.year, from: $0.date) == year }

        guard !yearSessions.isEmpty else {
            return YearInReview(
                year: year,
                sessionCount: 0,
                surfDays: 0,
                totalMinutes: 0,
                averageRating: nil,
                topSpot: nil,
                topGear: nil,
                bestMonth: nil,
                longestWeekStreak: 0,
                waveHeightDistribution: []
            )
        }

        let surfDays = Set(yearSessions.map { calendar.startOfDay(for: $0.date) }).count
        let totalMinutes = yearSessions.compactMap(\.durationMinutes).reduce(0, +)

        let ratings = yearSessions.map(\.rating).filter { $0 > 0 }
        let averageRating = ratings.isEmpty
            ? nil
            : Double(ratings.reduce(0, +)) / Double(ratings.count)

        var heightCounts: [WaveHeight: Int] = [:]
        for session in yearSessions {
            guard let band = GearInsightsCalculator.waveBand(for: session) else { continue }
            heightCounts[band, default: 0] += 1
        }
        let distribution = WaveHeight.allCases.compactMap { height -> YearInReviewWaveSlice? in
            guard let count = heightCounts[height], count > 0 else { return nil }
            return YearInReviewWaveSlice(height: height, count: count)
        }

        return YearInReview(
            year: year,
            sessionCount: yearSessions.count,
            surfDays: surfDays,
            totalMinutes: totalMinutes,
            averageRating: averageRating,
            topSpot: leader(names: yearSessions.compactMap { $0.spot?.name }),
            topGear: leader(names: yearSessions.flatMap { $0.gear.map(\.name) }),
            bestMonth: bestMonth(in: yearSessions, calendar: calendar),
            longestWeekStreak: StatsCalculator.longestWeekStreak(
                sessions: yearSessions,
                calendar: calendar
            ),
            waveHeightDistribution: distribution
        )
    }

    /// Years that actually contain sessions, most recent first. Drives the
    /// recap's year picker so it can never land on an empty year by accident.
    static func availableYears(
        sessions: [SurfSession],
        calendar: Calendar = .current
    ) -> [Int] {
        Set(sessions.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }

    /// Photos from the year, newest first — the recap's highlights grid. Videos
    /// are skipped: the grid is a still-image wall and a video's poster frame
    /// already ships as its thumbnail elsewhere.
    static func mediaHighlights(
        sessions: [SurfSession],
        year: Int,
        calendar: Calendar = .current,
        limit: Int = 6
    ) -> [SessionMedia] {
        sessions
            .filter { calendar.component(.year, from: $0.date) == year }
            .sorted { $0.date > $1.date }
            .flatMap { session in
                session.media
                    .filter { $0.kind == .photo && ($0.thumbnailData != nil || $0.photoData != nil) }
                    .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Private

    private static func leader(names: [String]) -> YearInReviewLeader? {
        guard !names.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for name in names {
            counts[name, default: 0] += 1
        }
        return counts
            .map { YearInReviewLeader(name: $0.key, count: $0.value) }
            .max { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return lhs.name > rhs.name
            }
    }

    private static func bestMonth(
        in sessions: [SurfSession],
        calendar: Calendar
    ) -> YearInReviewMonth? {
        var counts: [Date: Int] = [:]
        for session in sessions {
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: session.date)
            ) ?? session.date
            counts[monthStart, default: 0] += 1
        }
        return counts
            .map { YearInReviewMonth(month: $0.key, count: $0.value) }
            // Ties resolve to the earlier month so the answer is stable.
            .max { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return lhs.month > rhs.month
            }
    }
}
