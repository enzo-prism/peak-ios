import SwiftUI

/// The per-board report: a plain-language headline plus rating averages
/// bucketed by wave size and swell period. Buckets that haven't cleared the
/// sample floor say so out loud rather than printing a number nobody should
/// trust — see `GearInsightsCalculator.minimumBucketSessions`.
struct BoardReportCard: View {
    let report: GearReport
    /// Stats renders this inside a section that already has a title.
    var showsTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text("Board Report")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 16) {
                headline

                if !report.waveHeightBuckets.isEmpty {
                    bucketGroup(title: "By wave height", buckets: report.waveHeightBuckets)
                }

                if !report.periodBuckets.isEmpty {
                    bucketGroup(title: "By swell period", buckets: report.periodBuckets)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let highlight = report.highlight {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.gearName) averages \(StatsFormat.rating(highlight.averageRating))★ in \(highlight.phrase)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Across \(highlight.sessionCount) rated session\(highlight.sessionCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Board report for \(report.gearName)"))
            .accessibilityValue(Text("Averages \(StatsFormat.rating(highlight.averageRating)) stars in \(highlight.phrase), across \(highlight.sessionCount) rated sessions"))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Not enough data yet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(emptyHint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyHint: String {
        report.ratedSessionCount == 0
            ? "Rate your sessions with \(report.gearName) to see how it performs."
            : "Log \(GearInsightsCalculator.minimumBucketSessions) rated sessions in the same conditions and the pattern shows up here."
    }

    private func bucketGroup(title: String, buckets: [GearRatingBucket]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            ForEach(buckets) { bucket in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(bucket.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    if let average = bucket.averageRating {
                        Text("\(StatsFormat.rating(average))★")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text("Not enough data yet")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Text("\(bucket.sessionCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                        .frame(minWidth: 20, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(bucket.label))
                .accessibilityValue(Text(accessibilityValue(for: bucket)))
            }
        }
    }

    private func accessibilityValue(for bucket: GearRatingBucket) -> String {
        let sessions = "\(bucket.sessionCount) session\(bucket.sessionCount == 1 ? "" : "s")"
        guard let average = bucket.averageRating else {
            return "Not enough data yet, \(sessions)"
        }
        return "Averages \(StatsFormat.rating(average)) stars over \(sessions)"
    }
}

#Preview {
    BoardReportCard(
        report: GearReport(
            gearKey: "board|fish",
            gearName: "6'2\" Fish",
            sessionCount: 12,
            ratedSessionCount: 10,
            averageRating: 4.1,
            waveHeightBuckets: [
                GearRatingBucket(id: "a", label: "Waist high", sessionCount: 5, averageRating: 4.2),
                GearRatingBucket(id: "b", label: "Overhead", sessionCount: 2, averageRating: nil)
            ],
            periodBuckets: [
                GearRatingBucket(id: "c", label: "Under 10 s", sessionCount: 6, averageRating: 4.3)
            ],
            highlight: GearConditionsHighlight(
                phrase: "short-period waist-high",
                averageRating: 4.2,
                sessionCount: 5
            )
        )
    )
    .padding()
    .background(Theme.background)
}
