import Charts
import SwiftUI

/// Wave personal records + a waves-per-session trend.
///
/// The whole card disappears when no session has wave stats. That is deliberate:
/// most Peak users log by hand and will never see this, and an empty "Personal
/// records — no records yet" block on their Stats tab would be noise about a
/// feature they do not use.
struct WaveRecordsCard: View {
    let records: WaveRecords
    let trend: [WavesPerMonth]

    /// A single month is a dot, not a trend. Below this the chart is suppressed
    /// and only the records show.
    private static let minimumTrendMonths = 2

    private var hasTrend: Bool {
        trend.count >= Self.minimumTrendMonths
    }

    /// True when any record still rests on an unreviewed estimate.
    private var showsEstimateNote: Bool {
        [records.mostWaves, records.fastestWave, records.longestRide]
            .compactMap { $0 }
            .contains(where: \.isEstimate)
    }

    var body: some View {
        if records.isEmpty && !hasTrend {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wave records")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                if !records.isEmpty {
                    VStack(spacing: 8) {
                        if let record = records.mostWaves {
                            row(title: "Most waves", icon: "water.waves", record: record, key: "mostWaves")
                        }
                        if let record = records.fastestWave {
                            row(title: "Fastest wave", icon: "speedometer", record: record, key: "fastestWave")
                        }
                        if let record = records.longestRide {
                            row(title: "Longest ride", icon: "stopwatch", record: record, key: "longestRide")
                        }
                    }
                }

                if hasTrend {
                    trendChart
                }

                if showsEstimateNote {
                    Text(WaveStatsFormatter.estimateCaption)
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("stats.waveRecords.caption")
                }
            }
        }
    }

    private func row(title: String, icon: String, record: WaveRecord, key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.surfGreen)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(context(for: record))
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(record.value)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        // 44pt floor keeps the row a legal target even before Dynamic Type grows it.
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("stats.waveRecord.\(key)")
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(record.spokenValue), \(context(for: record))"))
    }

    private func context(for record: WaveRecord) -> String {
        let date = record.date.formatted(.dateTime.month(.abbreviated).day().year())
        guard let spot = record.spotName else { return date }
        return "\(spot) · \(date)"
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waves per session")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Chart {
                ForEach(trend) { point in
                    LineMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Waves", point.averageWaves)
                    )
                    .foregroundStyle(Theme.textPrimary)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Waves", point.averageWaves)
                    )
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel(Text(point.month.formatted(.dateTime.month(.abbreviated).year())))
                    .accessibilityValue(Text(accessibilityValue(for: point)))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(1, trend.count / 4))) { value in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .frame(height: 120)
            .accessibilityIdentifier("stats.wavesPerSession.chart")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private func accessibilityValue(for point: WavesPerMonth) -> String {
        let average = String(format: "%.1f", point.averageWaves)
        return "\(average) waves per session across \(point.sessionCount) session\(point.sessionCount == 1 ? "" : "s")"
    }
}
