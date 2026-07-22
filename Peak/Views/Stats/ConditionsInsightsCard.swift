import Charts
import SwiftUI

/// Conditions storytelling: a wave-height-vs-rating scatter (once there are
/// enough measured sessions) and a plain-language "best sessions" readout.
/// Both fade in only when there's enough logged data; until then a single
/// gentle hint invites the surfer to keep logging conditions.
struct ConditionsInsightsCard: View {
    let samples: [WaveRatingSample]
    let insight: ConditionsInsight?

    private static let scatterThreshold = 8

    private var showScatter: Bool { samples.count >= Self.scatterThreshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showScatter {
                scatterCard
            }
            if let insight {
                bestSessionsCard(insight)
            }
            if !showScatter && insight == nil {
                emptyHint
            }
        }
    }

    private var scatterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wave height vs. rating")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Every rated session with a measured wave height")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Chart(samples) { sample in
                PointMark(
                    x: .value("Wave height", sample.waveHeightMeters),
                    y: .value("Rating", sample.rating)
                )
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .symbolSize(70)
                .accessibilityLabel(Text(String(format: "%.1f meters", sample.waveHeightMeters)))
                .accessibilityValue(Text("Rated \(sample.rating)"))
            }
            .chartYScale(domain: 0...5.5)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.glassDimTint)
                    if let meters = value.as(Double.self) {
                        AxisValueLabel {
                            Text(meters.formatted(.number.precision(.fractionLength(0...1))))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [1, 2, 3, 4, 5]) { _ in
                    AxisGridLine().foregroundStyle(Theme.glassDimTint)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .chartXAxisLabel("Wave height (m)", alignment: .center)
            .chartYAxisLabel("Rating ★")
            .frame(height: 180)
            .accessibilityLabel(Text("Wave height versus rating scatter plot"))
            .accessibilityValue(Text("\(samples.count) rated sessions with measured wave height"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private func bestSessionsCard(_ insight: ConditionsInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your best sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(insight.summary)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Averages \(StatsFormat.rating(insight.averageRating))★ over \(insight.sessionCount) session\(insight.sessionCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your best sessions"))
        .accessibilityValue(Text("\(insight.summary), averaging \(StatsFormat.rating(insight.averageRating)) stars over \(insight.sessionCount) session\(insight.sessionCount == 1 ? "" : "s")"))
    }

    private var emptyHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Conditions insights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("Log conditions on more sessions to unlock insights")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }
}
