import SwiftUI

/// GitHub-style consistency grid: one column per week, one row per weekday,
/// each cell shaded by how many sessions fell on that day. Monochrome — empty
/// days read as a faint tint and busy days ramp up to full ink/foam.
///
/// Drawn with plain stacks rather than Swift Charts: as a `RectangleMark` grid
/// the cells collapsed to ~2pt dashes, the weekday labels sat on the band
/// edges and overlapped the first column, and the rows ran Saturday-first.
/// Square cells sized from the available width avoid all three.
struct ConsistencyHeatmapCard: View {
    let cells: [SessionHeatmapCell]

    private static let cellSpacing: CGFloat = 3

    private var weekStarts: [Date] {
        Set(cells.map(\.weekStart)).sorted()
    }

    /// week start → weekday offset → cell. The current week is usually
    /// partial; its missing (future) days render as blank space.
    private var lookup: [Date: [Int: SessionHeatmapCell]] {
        var map: [Date: [Int: SessionHeatmapCell]] = [:]
        for cell in cells {
            map[cell.weekStart, default: [:]][cell.weekdayIndex] = cell
        }
        return map
    }

    private var maxCount: Int {
        max(cells.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        let weeks = weekStarts
        let grid = lookup

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Last \(weeks.count) weeks")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            VStack(spacing: Self.cellSpacing) {
                // Row 0 is the calendar's first weekday (`weekdayIndex` is the
                // offset from it), so Sunday — or Monday — sits on top.
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: Self.cellSpacing) {
                        Text(weekdayLetter(row))
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 16, alignment: .leading)
                            .accessibilityHidden(true)
                        ForEach(weeks, id: \.self) { week in
                            cellView(grid[week]?[row])
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Consistency heatmap"))
            .accessibilityValue(Text("Sessions per day over the last \(weeks.count) weeks"))
            .accessibilityIdentifier("stats.heatmap")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    @ViewBuilder
    private func cellView(_ cell: SessionHeatmapCell?) -> some View {
        if let cell {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(intensity(for: cell.count))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityLabel(Text(accessibilityLabel(for: cell)))
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    /// Empty days stay a faint glass tint; busy days ramp ink/foam 0.35 → 1.0.
    private func intensity(for count: Int) -> Color {
        guard count > 0 else { return Theme.glassDimTint }
        let ratio = Double(count) / Double(maxCount)
        return Theme.textPrimary.opacity(0.35 + 0.65 * ratio)
    }

    private func weekdayLetter(_ row: Int) -> String {
        let calendar = Calendar.current
        let index = (calendar.firstWeekday - 1 + row) % 7
        return calendar.veryShortWeekdaySymbols[index]
    }

    private func accessibilityLabel(for cell: SessionHeatmapCell) -> String {
        let day = cell.day.formatted(date: .abbreviated, time: .omitted)
        return "\(day), \(cell.count) session\(cell.count == 1 ? "" : "s")"
    }
}
