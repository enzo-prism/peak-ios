import SwiftUI
import WidgetKit

#if canImport(RelevanceKit)
import RelevanceKit
#endif

/// Smart Stack entry point: a tap target that starts a surf session, which
/// watchOS surfaces on its own when the surfer is somewhere they surf.
struct LogSurfWidget: Widget {
    static let kind = "PeakLogSurf"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LogSurfProvider()) { _ in
            LogSurfWidgetView()
        }
        .configurationDisplayName("Log your surf")
        .description("Start a surf session from the Smart Stack.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner])
    }
}

struct LogSurfEntry: TimelineEntry {
    let date: Date
}

struct LogSurfProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogSurfEntry {
        LogSurfEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LogSurfEntry) -> Void) {
        completion(LogSurfEntry(date: Date()))
    }

    /// One entry, never expiring. The widget shows a fixed call to action — it
    /// has no changing content, so a timeline of one is honest and costs the
    /// system nothing to refresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LogSurfEntry>) -> Void) {
        completion(Timeline(entries: [LogSurfEntry(date: Date())], policy: .never))
    }

    /// Tells the Smart Stack when this widget is worth showing.
    ///
    /// Two layers of availability, for two different reasons:
    /// - `WidgetRelevance` itself only exists from watchOS 11, which is why the
    ///   whole method is gated. The app's deployment target stays at watchOS 10
    ///   so the session tracker — the actual point of the app — still runs on
    ///   older watches.
    /// - `RelevantContext` only moved into RelevanceKit in watchOS 26 (it was
    ///   AppIntents-internal before), hence the inner check.
    ///
    /// Below either bar the widget still works; it just sits in the stack in its
    /// normal position rather than being promoted at the beach.
    @available(watchOS 11.0, *)
    func relevance() async -> WidgetRelevance<Void> {
        #if canImport(RelevanceKit)
        guard #available(watchOS 26.0, *) else { return WidgetRelevance([]) }

        var attributes: [WidgetRelevanceAttribute<Void>] = []

        // Where this surfer has actually surfed before, from HealthKit route
        // history. See SurfRegionProvider for why this is not read from the
        // user's saved spots.
        for region in await SurfRegionProvider.recentSurfRegions() {
            attributes.append(WidgetRelevanceAttribute(context: .location(region)))
        }

        // Dawn patrol. Costs no data and covers the surfer whose first-ever
        // session has not been recorded yet, so the widget is not useless on
        // day one.
        if let dawn = LogSurfRelevanceWindow.dawnPatrolWindow(from: Date()) {
            attributes.append(WidgetRelevanceAttribute(context: .date(interval: dawn, kind: .default)))
        }

        return WidgetRelevance(attributes)
        #else
        return WidgetRelevance([])
        #endif
    }
}

struct LogSurfWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryCorner:
            Image(systemName: "water.waves")
                .font(.title3)
                .widgetAccentable()
        default:
            HStack(spacing: 6) {
                Image(systemName: "water.waves")
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Peak").font(.headline)
                    Text("Log your surf")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
