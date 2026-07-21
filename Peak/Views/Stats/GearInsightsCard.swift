import SwiftUI

/// Quiver analytics on Stats: one line per board answering "what does this
/// thing actually do for me?". Boards with no qualifying bucket say so rather
/// than inventing a number — the full breakdown lives in the gear detail.
struct GearInsightsCard: View {
    let reports: [GearReport]

    /// Beyond a handful of boards the card stops being a summary.
    private static let maximumRows = 4

    private var visibleReports: [GearReport] {
        Array(reports.prefix(Self.maximumRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board Report")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if visibleReports.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleReports) { report in
                        row(for: report)
                    }
                }
            }
        }
    }

    private func row(for report: GearReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.gearName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail(for: report))
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(report.gearName))
        .accessibilityValue(Text(detail(for: report)))
    }

    private func detail(for report: GearReport) -> String {
        guard let highlight = report.highlight else {
            return "Not enough data yet — \(report.sessionCount) session\(report.sessionCount == 1 ? "" : "s") logged"
        }
        return "Averages \(StatsFormat.rating(highlight.averageRating))★ in \(highlight.phrase) (\(highlight.sessionCount) sessions)"
    }

    private var emptyHint: some View {
        Text("Log gear on your sessions to unlock the board report.")
            .font(.subheadline)
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }
}
