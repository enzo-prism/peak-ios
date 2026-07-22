import Charts
import SwiftUI

/// Scrollable monthly surf-days bar chart. Opens anchored on the most recent
/// months; tapping a bar surfaces that month's exact count in the header.
struct MonthlyBarsCard: View {
    let data: [MonthlyCount]

    @State private var rawSelection: Date?

    /// ~6 months of the temporal (seconds-based) x domain kept in view.
    private let visibleSeconds: TimeInterval = 3600 * 24 * 30 * 6

    private var selectedEntry: MonthlyCount? {
        guard let rawSelection else { return nil }
        return data.first {
            Calendar.current.isDate($0.month, equalTo: rawSelection, toGranularity: .month)
        }
    }

    private var initialScrollMonth: Date {
        guard !data.isEmpty else { return Date() }
        return data[max(0, data.count - 6)].month
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Month", item.month, unit: .month),
                        y: .value("Surf Days", item.count)
                    )
                    .foregroundStyle(barColor(for: item))
                    .accessibilityLabel(Text(item.month.formatted(.dateTime.month(.abbreviated).year())))
                    .accessibilityValue(Text("\(item.count) surf days"))
                }

                if let selectedEntry {
                    RuleMark(x: .value("Month", selectedEntry.month, unit: .month))
                        .foregroundStyle(Theme.glassStrongTint.opacity(0.25))
                        .zIndex(-1)
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleSeconds)
            .chartScrollPosition(initialX: initialScrollMonth)
            .chartXSelection(value: $rawSelection)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(Theme.glassDimTint)
                    AxisValueLabel(format: .dateTime.month(.narrow))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.glassDimTint)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(height: 160)
            .accessibilityLabel(Text("Monthly surf days"))
            .accessibilityValue(Text("Scrollable bar chart of surf days per month"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly surf days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(selectedEntry == nil ? "Scroll · tap a bar" : selectedMonthLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if let selectedEntry {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(selectedEntry.count)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(selectedEntry.count == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(selectedMonthLabel), \(selectedEntry.count) surf days"))
            }
        }
    }

    private var selectedMonthLabel: String {
        selectedEntry?.month.formatted(.dateTime.month(.wide).year()) ?? ""
    }

    private func barColor(for item: MonthlyCount) -> Color {
        guard selectedEntry != nil else { return Theme.textPrimary.opacity(0.85) }
        let isSelected = Calendar.current.isDate(
            item.month,
            equalTo: selectedEntry?.month ?? item.month,
            toGranularity: .month
        )
        return isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.3)
    }
}
