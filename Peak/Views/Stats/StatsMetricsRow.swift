import SwiftUI

/// Headline metrics grid for the Stats tab: time in water, average session
/// length, this-year surf days and sessions, and current / longest week
/// streaks. Optional tiles (time, average length) drop out cleanly when there
/// is no logged duration, so the grid stays tidy on a thin logbook.
struct StatsMetricsRow: View {
    let yearSummary: SurfYearSummary
    let timeSummary: SurfTimeSummary
    let longestStreak: Int

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        GlassContainer(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { tile in
                    StatCardView(
                        title: tile.title,
                        value: tile.value,
                        subtitle: tile.subtitle
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tile.accessibilityLabel)
                }
            }
        }
    }

    private var tiles: [StatsMetric] {
        var result: [StatsMetric] = []

        if timeSummary.sessionsWithDuration > 0 {
            result.append(StatsMetric(
                title: "Time in water",
                value: StatsFormat.duration(timeSummary.totalMinutes),
                subtitle: "\(timeSummary.sessionsWithDuration) logged",
                accessibilityLabel: "Time in water, \(StatsFormat.spokenDuration(timeSummary.totalMinutes)) across \(timeSummary.sessionsWithDuration) sessions"
            ))
        }

        if let average = timeSummary.averageMinutes {
            result.append(StatsMetric(
                title: "Avg length",
                value: StatsFormat.duration(average),
                subtitle: "Per session",
                accessibilityLabel: "Average session length, \(StatsFormat.spokenDuration(average))"
            ))
        }

        result.append(StatsMetric(
            title: "Surf days",
            value: "\(yearSummary.totalDays)",
            subtitle: "In \(yearSummary.year)",
            accessibilityLabel: "Surf days in \(yearSummary.year), \(yearSummary.totalDays)"
        ))

        result.append(StatsMetric(
            title: "This year",
            value: "\(yearSummary.totalSessions)",
            subtitle: "Sessions",
            accessibilityLabel: "Sessions in \(yearSummary.year), \(yearSummary.totalSessions)"
        ))

        result.append(StatsMetric(
            title: "Current streak",
            value: yearSummary.currentWeekStreak > 0 ? "\(yearSummary.currentWeekStreak) 🔥" : "0",
            subtitle: "Weeks in a row",
            accessibilityLabel: "Current streak, \(StatsFormat.spokenWeeks(yearSummary.currentWeekStreak))"
        ))

        result.append(StatsMetric(
            title: "Longest streak",
            value: "\(longestStreak)",
            subtitle: "Weeks in a row",
            accessibilityLabel: "Longest streak, \(StatsFormat.spokenWeeks(longestStreak))"
        ))

        return result
    }
}

private struct StatsMetric: Identifiable {
    let title: String
    let value: String
    let subtitle: String
    let accessibilityLabel: String

    var id: String { title }
}
