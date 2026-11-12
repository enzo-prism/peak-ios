import SwiftUI

/// Headline metrics grid for the Stats tab: time in water, average session
/// length, this-year surf days and sessions, and current / longest week
/// streaks. Optional tiles (time, average length) drop out cleanly when there
/// is no logged duration, so the grid stays tidy on a thin logbook.
struct StatsMetricsRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let yearSummary: SurfYearSummary
    let timeSummary: SurfTimeSummary
    let longestStreak: Int

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }

    var body: some View {
        GlassContainer(spacing: 12) {
            if typeSize.isAccessibilitySize {
                // Only four or six cards: eagerly lay out their complete text
                // so offscreen metrics also adopt the current font metrics.
                VStack(spacing: 12) {
                    ForEach(tiles) { metricCard($0) }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tiles) { metricCard($0) }
                }
            }
        }
    }

    private func metricCard(_ tile: StatsMetric) -> some View {
        StatCardView(
            title: tile.title,
            value: tile.value,
            subtitle: tile.subtitle,
            accessibilitySummary: tile.accessibilityLabel,
            valueSystemImage: tile.valueSystemImage
        )
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

        // Parallel to "Surf days / In 2026" — a "This year / Sessions" tile beside
        // it read as the same number labelled twice.
        result.append(StatsMetric(
            title: "Sessions",
            value: "\(yearSummary.totalSessions)",
            subtitle: "In \(yearSummary.year)",
            accessibilityLabel: "Sessions in \(yearSummary.year), \(yearSummary.totalSessions)"
        ))

        result.append(StatsMetric(
            title: "Current streak",
            value: "\(yearSummary.currentWeekStreak)",
            subtitle: "Weeks in a row",
            accessibilityLabel: "Current streak, \(StatsFormat.spokenWeeks(yearSummary.currentWeekStreak))",
            valueSystemImage: yearSummary.currentWeekStreak > 0 ? "flame.fill" : nil
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
    var valueSystemImage: String? = nil

    var id: String { title }
}
