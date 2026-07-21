import Foundation

enum MonthlyGoalMetric: String, CaseIterable, Identifiable {
    case sessions
    case hours

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .sessions:
            return "Sessions"
        case .hours:
            return "Hours"
        }
    }

    /// Lower-case unit for use inside a sentence ("4 of 8 sessions").
    nonisolated var unitLabel: String {
        switch self {
        case .sessions:
            return "sessions"
        case .hours:
            return "hours"
        }
    }
}

struct MonthlyGoalProgress: Equatable {
    let metric: MonthlyGoalMetric
    let target: Int
    let achieved: Double
    /// Clamped to 0...1. Overshoot is reported by `achieved`/`isMet`, never by a
    /// ring that runs past full — a 12/8 month should read as done, not broken.
    let fraction: Double
    let isMet: Bool

    var isActive: Bool { target > 0 }

    var remaining: Double { max(0, Double(target) - achieved) }

    var achievedLabel: String {
        switch metric {
        case .sessions:
            return String(Int(achieved.rounded()))
        case .hours:
            return achieved == achieved.rounded()
                ? String(Int(achieved))
                : String(format: "%.1f", achieved)
        }
    }

    var summaryLabel: String {
        "\(achievedLabel) of \(target) \(metric.unitLabel)"
    }
}

/// Monthly goal progress. Goals are a deliberate counterweight to streaks:
/// surfing is condition-gated, so a flat week should cost you a percentage
/// point, not a badge you've held for a year.
enum MonthlyGoalCalculator {
    /// `@AppStorage` keys — the goal is user preference, not logbook data, so it
    /// never touches the SwiftData schema.
    static let metricKey = "monthlyGoalMetric"
    static let targetKey = "monthlyGoalTarget"

    /// Goals start OFF (`0` hides the card). A target the surfer never chose is
    /// just a number telling them they're behind — on day one it would read
    /// "0 of 8", which is exactly the discouragement goals exist to avoid.
    /// Settings offers this suggested target when they opt in.
    static let defaultTarget = 0
    /// Roughly two sessions a week: ambitious enough to pull, achievable enough
    /// that a bad-forecast month doesn't zero it out.
    static let suggestedTarget = 8
    /// The same cadence expressed in hours, assuming a ~1.5 h session.
    static let suggestedHoursTarget = 12
    static let maximumTarget = 60

    static func progress(
        sessions: [SurfSession],
        metric: MonthlyGoalMetric,
        target: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyGoalProgress {
        let monthSessions: [SurfSession]
        if let interval = calendar.dateInterval(of: .month, for: referenceDate) {
            monthSessions = sessions.filter { interval.contains($0.date) }
        } else {
            monthSessions = []
        }

        let achieved: Double
        switch metric {
        case .sessions:
            achieved = Double(monthSessions.count)
        case .hours:
            achieved = Double(monthSessions.compactMap(\.durationMinutes).reduce(0, +)) / 60
        }

        let safeTarget = max(0, min(target, maximumTarget))
        let fraction = safeTarget > 0 ? min(achieved / Double(safeTarget), 1) : 0

        return MonthlyGoalProgress(
            metric: metric,
            target: safeTarget,
            achieved: achieved,
            fraction: fraction,
            isMet: safeTarget > 0 && achieved >= Double(safeTarget)
        )
    }
}
