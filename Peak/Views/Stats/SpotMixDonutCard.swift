import Charts
import SwiftUI

/// Donut of where the sessions happened. Slices step from full ink/foam (the
/// most-surfed break) down to a faint tint (the "Other" bucket), with the
/// all-in total floating in the hole. The legend keys the shades and gives
/// each spot's share.
struct SpotMixDonutCard: View {
    let spots: [CountedItem]

    private struct Slice: Identifiable {
        let item: CountedItem
        let color: Color
        var id: String { item.id }
    }

    private var slices: [Slice] {
        spots.enumerated().map { index, item in
            Slice(item: item, color: sliceColor(index: index))
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
            // The share, not just the count: in a monochrome donut the legend
            // has to carry the comparison the shades alone can't.
            Text(percent(slice.item.count))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(slice.item.name), \(slice.item.count) session\(slice.item.count == 1 ? "" : "s"), \(percent(slice.item.count))"))
    }

    private func percent(_ count: Int) -> String {
        guard totalSessions > 0 else { return "0%" }
        return (Double(count) / Double(totalSessions)).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Fixed, well-separated ink/foam steps instead of a linear fade: a linear
    /// ramp over six slices put neighbours ~13% apart, which reads as one grey.
    /// Stays inside the monochrome palette (Theme.swift) on purpose.
    private static let sliceOpacities: [Double] = [1.0, 0.7, 0.48, 0.32, 0.2]

    private func sliceColor(index: Int) -> Color {
        let isOther = spots[index].key == "stats.spot-mix.other"
        let opacity = isOther
            ? 0.1
            : Self.sliceOpacities[min(index, Self.sliceOpacities.count - 1)]
        return Theme.textPrimary.opacity(opacity)
    }
}
