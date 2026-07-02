import Charts
import SwiftUI

/// GitHub-style consistency grid: one column per week, one row per weekday,
/// each cell shaded by how many sessions fell on that day. Monochrome — empty
/// days read as a faint tint and busy days ramp up to full ink/foam.
struct ConsistencyHeatmapCard: View {
    let cells: [SessionHeatmapCell]

    private var weeksCount: Int {
        Set(cells.map(\.weekStart)).count
    }

    private var maxCount: Int {
        max(cells.map(\.count).max() ?? 0, 1)
    }

    /// Stable, sortable week keys (ordered oldest → newest) so the x axis reads
    /// left-to-right in time even as a categorical band scale.
    private var orderedWeekKeys: [String] {
        Set(cells.map(\.weekStart))
            .sorted()
            .enumerated()
            .map { weekKey(index: $0.offset) }
    }

    private var weekIndexByStart: [Date: Int] {
        var map: [Date: Int] = [:]
        for (index, start) in Set(cells.map(\.weekStart)).sorted().enumerated() {
            map[start] = index
        }
        return map
    }

    /// Ordered weekday full names (unique category identity). Reversed so the
    /// calendar's first weekday sits at the top of the grid.
    private var orderedWeekdayNames: [String] {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    var body: some View {
        let weekIndex = weekIndexByStart
        let names = orderedWeekdayNames

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Last \(weeksCount) weeks")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Chart(cells) { cell in
                RectangleMark(
                    x: .value("Week", weekKey(index: weekIndex[cell.weekStart] ?? 0)),
                    y: .value("Weekday", names[cell.weekdayIndex])
                )
                .foregroundStyle(intensity(for: cell.count))
                .cornerRadius(3)
                .accessibilityLabel(Text(accessibilityLabel(for: cell)))
                .accessibilityValue(Text("\(cell.count)"))
            }
            .chartXScale(domain: orderedWeekKeys)
            .chartYScale(domain: names.reversed())
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let name = value.as(String.self) {
                        AxisValueLabel {
                            Text(shortSymbol(for: name))
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .frame(height: 140)
            .accessibilityLabel(Text("Consistency heatmap"))
            .accessibilityValue(Text("Sessions per day over the last \(weeksCount) weeks"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private func weekKey(index: Int) -> String {
        String(format: "w%03d", index)
    }

    /// Empty days stay a faint glass tint; busy days ramp ink/foam 0.35 → 1.0.
    private func intensity(for count: Int) -> Color {
        guard count > 0 else { return Theme.glassDimTint }
        let ratio = Double(count) / Double(maxCount)
        return Theme.textPrimary.opacity(0.35 + 0.65 * ratio)
    }

    private func shortSymbol(for name: String) -> String {
        let calendar = Calendar.current
        if let index = calendar.weekdaySymbols.firstIndex(of: name) {
            return calendar.veryShortWeekdaySymbols[index]
        }
        return String(name.prefix(1))
    }

    private func accessibilityLabel(for cell: SessionHeatmapCell) -> String {
        let day = cell.day.formatted(date: .abbreviated, time: .omitted)
        return "\(day), \(cell.count) session\(cell.count == 1 ? "" : "s")"
    }
}
