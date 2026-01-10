import Charts
import SwiftUI

struct UsageChartCard: View {
    let title: String
    let data: [MonthlyCount]
    let valueLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Chart(data) { item in
                BarMark(
                    x: .value("Month", item.month, unit: .month),
                    y: .value(valueLabel, item.count)
                )
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .accessibilityLabel(Text(item.month.formatted(.dateTime.month(.abbreviated))))
                .accessibilityValue(Text("\(item.count)"))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisGridLine().foregroundStyle(Theme.glassDimTint)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.glassDimTint)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(height: 160)
            .accessibilityLabel(Text(title))
        }
        .padding(16)
        .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: false)
    }
}
