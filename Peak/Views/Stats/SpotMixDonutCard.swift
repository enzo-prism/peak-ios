import Charts
import SwiftUI

/// Donut of where the sessions happened. Slices ramp from full ink/foam (the
/// most-surfed break) to a faint tint (the long tail / "Other" bucket), with
/// the all-in total floating in the hole. A compact legend keys the shades.
struct SpotMixDonutCard: View {
    let spots: [CountedItem]

    private struct Slice: Identifiable {
        let item: CountedItem
        let color: Color
        var id: String { item.id }
    }

    private var slices: [Slice] {
        let count = spots.count
        return spots.enumerated().map { index, item in
            Slice(item: item, color: sliceColor(index: index, total: count))
        }
    }

    private var totalSessions: Int {
        spots.reduce(0) { $0 + $1.count }
    }

    private let legendColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spot mix")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Sessions", slice.item.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(slice.color)
                .accessibilityLabel(Text(slice.item.name))
                .accessibilityValue(Text("\(slice.item.count) session\(slice.item.count == 1 ? "" : "s")"))
            }
            .chartLegend(.hidden)
            .frame(height: 180)
            .overlay { centerTotal }
            .accessibilityLabel(Text("Spot mix"))
            .accessibilityValue(Text("\(spots.count) spots across \(totalSessions) sessions"))

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 8) {
                ForEach(slices) { slice in
                    legendRow(slice)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private var centerTotal: some View {
        VStack(spacing: 0) {
            Text("\(totalSessions)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("sessions")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityHidden(true)
    }

    private func legendRow(_ slice: Slice) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(slice.color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(slice.item.name)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(slice.item.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(slice.item.name), \(slice.item.count) session\(slice.item.count == 1 ? "" : "s")"))
    }

    /// Biggest slice is full-strength ink/foam; the tail fades toward a tint.
    private func sliceColor(index: Int, total: Int) -> Color {
        guard total > 1 else { return Theme.textPrimary }
        let ratio = Double(index) / Double(total - 1)
        return Theme.textPrimary.opacity(1.0 - ratio * 0.65)
    }
}
