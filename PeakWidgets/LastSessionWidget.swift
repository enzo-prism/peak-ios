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
            .accessibilityLabel("Last surf at \(spot)")
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
        .widgetURL(peakLogSessionURL)
    }
}
