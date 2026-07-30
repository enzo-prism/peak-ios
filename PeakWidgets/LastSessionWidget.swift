import WidgetKit
import SwiftUI

/// At-a-glance widget for the most recent session: spot, rating, and how long
/// ago it was.
struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PeakLastSessionWidget", provider: PeakSnapshotProvider()) { entry in
            LastSessionWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last Session")
        .description("Your most recent surf at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct LastSessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PeakWidgetSnapshot

    var body: some View {
        if let spot = snapshot.lastSessionSpot, let date = snapshot.lastSessionDate {
            content(spot: spot, date: date)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(spot: String, date: Date) -> some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last surf").font(.caption2).foregroundStyle(PeakWidgetStyle.muted)
                Text(spot).font(.headline).lineLimit(1)
                Text(date, format: .relative(presentation: .named)).font(.caption)
            }
            .accessibilityElement(children: .combine)
            .widgetURL(peakLogSessionURL)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST SURF")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PeakWidgetStyle.muted)
                Text(spot)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                if let rating = snapshot.lastSessionRating, rating > 0 {
                    RatingDots(rating: rating)
                }
                Spacer(minLength: 0)
                Text(date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(PeakWidgetStyle.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(peakLogSessionURL)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullLabel(spot: spot, date: date))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "figure.surfing")
                .font(.title2)
                .foregroundStyle(PeakWidgetStyle.muted)
            Text("Log your first surf")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .widgetURL(peakLogSessionURL)
    }

    /// Everything the widget shows, spoken in one element: spot, rating, when.
    private func fullLabel(spot: String, date: Date) -> String {
        var parts = ["Last surf at \(spot)"]
        if let rating = snapshot.lastSessionRating, rating > 0 {
            parts.append("rated \(rating) out of 5")
        }
        parts.append(date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: ", ")
    }
}
