import WidgetKit
import SwiftUI

/// Habit-focused widget: current week streak, sessions this month, and days
/// since the last surf. Available on Home Screen and Lock Screen accessories.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PeakStreakWidget", provider: PeakSnapshotProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Surf Streak")
        .description("Your current week streak and recent surf activity.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PeakWidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            // A Label, not an emoji: emoji render monochrome/inconsistently in
            // the Lock Screen's vibrant mode and say nothing to VoiceOver.
            Label("\(snapshot.currentStreakWeeks) wk streak", systemImage: "flame.fill")
        case .accessoryCircular:
            Gauge(value: Double(min(snapshot.currentStreakWeeks, 12)), in: 0...12) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(snapshot.currentStreakWeeks)")
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Week streak")
            .accessibilityValue("\(snapshot.currentStreakWeeks) weeks")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(snapshot.currentStreakWeeks) week streak", systemImage: "flame.fill")
                    .font(.headline)
                Text(daysSinceText)
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .widgetURL(peakLogSessionURL)
        default:
            homeView
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 10 : 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(PeakWidgetStyle.ink)
                Text("\(snapshot.currentStreakWeeks)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("wk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PeakWidgetStyle.muted)
                    .padding(.top, 10)
            }
            // Marks the streak as the accent group so the tinted Home Screen
            // rendering mode keeps its emphasis instead of flattening the
            // whole widget uniformly.
            .widgetAccentable()
            Text("Week streak")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PeakWidgetStyle.muted)

            Spacer(minLength: 0)

            HStack {
                metric("\(snapshot.sessionsThisMonth)", "this month")
                if family == .systemMedium {
                    Spacer()
                    metric(daysSinceValue, "since last")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(peakLogSessionURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.currentStreakWeeks) week streak, \(snapshot.sessionsThisMonth) sessions this month, \(daysSinceText)")
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(PeakWidgetStyle.muted)
        }
    }

    private var daysSinceValue: String {
        guard let days = snapshot.daysSinceLastSession else { return "—" }
        return days == 0 ? "today" : "\(days)d"
    }

    private var daysSinceText: String {
        guard let days = snapshot.daysSinceLastSession else { return "No sessions yet" }
        return days == 0 ? "Surfed today" : "\(days) days since last surf"
    }
}
