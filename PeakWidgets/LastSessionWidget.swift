import AppIntents
import SwiftUI
import WidgetKit

/// At-a-glance widget for the most recent session: spot, rating, and how long
/// ago it was. Configurable to pin a frequent spot from the snapshot glances
/// (the extension never opens SwiftData).
struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "PeakLastSessionWidget",
            intent: LastSessionConfigurationIntent.self,
            provider: LastSessionProvider()
        ) { entry in
            LastSessionWidgetView(
                snapshot: entry.snapshot,
                configuredSpotKey: entry.configuredSpotKey
            )
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last Session")
        .description("Your most recent surf at a glance. Optionally pin a spot.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemExtraLarge, .accessoryRectangular])
    }
}

// MARK: - Configuration

/// Optional spot pin. Nil keeps overall-last-session behaviour; a value looks
/// up that key in `PeakWidgetSnapshot.spotGlances`.
struct LastSessionConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Last Session"
    static var description = IntentDescription(
        "Show your most recent surf, or the last surf at a chosen spot."
    )

    @Parameter(title: "Spot")
    var spot: WidgetSpotEntity?

    /// Configuration intents are never executed; WidgetKit only reads the
    /// parameters. AppIntent still requires `perform()`.
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// A spot the Last Session widget can pin. Identity is `PeakSpotGlance.key`,
/// and suggestions come from the App Group snapshot — not SwiftData — so the
/// extension never opens the store.
struct WidgetSpotEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spot")
    static let defaultQuery = WidgetSpotQuery()

    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(glance: PeakSpotGlance) {
        self.init(id: glance.key, name: glance.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "mappin.and.ellipse"))
    }
}

struct WidgetSpotQuery: EntityStringQuery {
    func entities(for identifiers: [WidgetSpotEntity.ID]) async throws -> [WidgetSpotEntity] {
        let byKey = Dictionary(
            uniqueKeysWithValues: glances().map { ($0.key, $0) }
        )
        return identifiers.map { id in
            if let glance = byKey[id] {
                return WidgetSpotEntity(glance: glance)
            }
            // Keep a configured pin resolvable even if it dropped out of the
            // capped glance list; the view then falls back to empty.
            return WidgetSpotEntity(id: id, name: id)
        }
    }

    func entities(matching string: String) async throws -> [WidgetSpotEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try await suggestedEntities() }
        return glances()
            .filter { $0.name.lowercased().contains(needle) || $0.key.contains(needle) }
            .map(WidgetSpotEntity.init(glance:))
    }

    func suggestedEntities() async throws -> [WidgetSpotEntity] {
        glances().map(WidgetSpotEntity.init(glance:))
    }

    private func glances() -> [PeakSpotGlance] {
        PeakWidgetStore.read().spotGlances ?? []
    }
}

struct LastSessionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PeakEntry {
        PeakEntry(date: .now, snapshot: .preview)
    }

    func snapshot(for configuration: LastSessionConfigurationIntent, in context: Context) async -> PeakEntry {
        let snapshot = context.isPreview ? PeakWidgetSnapshot.preview : PeakWidgetStore.read().adjusted(for: .now)
        return PeakEntry(date: .now, snapshot: snapshot, configuredSpotKey: configuration.spot?.id)
    }

    func timeline(for configuration: LastSessionConfigurationIntent, in context: Context) async -> Timeline<PeakEntry> {
        PeakEntry.midnightAlignedTimeline(
            snapshot: PeakWidgetStore.read(),
            configuredSpotKey: configuration.spot?.id
        )
    }
}

// MARK: - View

struct LastSessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PeakWidgetSnapshot
    var configuredSpotKey: String? = nil

    var body: some View {
        if let session = displayed {
            content(session)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(_ session: DisplayedSession) -> some View {
        switch family {
        case .accessoryRectangular:
            accessoryContent(session)
        case .systemExtraLarge:
            extraLargeContent(session)
        case .systemMedium:
            mediumContent(session)
        default:
            smallContent(session)
        }
    }

    private func accessoryContent(_ session: DisplayedSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last surf").font(.caption2).foregroundStyle(PeakWidgetStyle.muted)
            Text(session.spot).font(.headline).lineLimit(1)
            Text(session.date, format: .relative(presentation: .named)).font(.caption)
        }
        .accessibilityElement(children: .combine)
        // Same rule as Home Screen: reopen this session, not a blank editor.
        .widgetURL(peakSessionURL(id: session.sessionID))
    }

    private func smallContent(_ session: DisplayedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAST SURF")
                .font(.caption2.weight(.bold))
                .foregroundStyle(PeakWidgetStyle.muted)
            Text(session.spot)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            if let rating = session.rating, rating > 0 {
                RatingDots(rating: rating)
            }
            Spacer(minLength: 0)
            Text(session.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(PeakWidgetStyle.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(peakSessionURL(id: session.sessionID))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullLabel(session))
    }

    /// Medium has room for a primary action without crowding the glance.
    /// The button is an interactive region; the rest of the surface still
    /// uses `widgetURL` so a tap on the session opens that session.
    private func mediumContent(_ session: DisplayedSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST SURF")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PeakWidgetStyle.muted)
                Text(session.spot)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                if let rating = session.rating, rating > 0 {
                    RatingDots(rating: rating)
                }
                Spacer(minLength: 0)
                Text(session.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(PeakWidgetStyle.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullLabel(session))

            Spacer(minLength: 0)
            startSessionButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(peakSessionURL(id: session.sessionID))
    }

    /// Extra-large is iPad-only and has room for the session's numbers, not
    /// just a stretched small layout: spot, rating, wave count (when present),
    /// relative date, sessions this month, and Start Session.
    private func extraLargeContent(_ session: DisplayedSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST SURF")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PeakWidgetStyle.muted)
                    Text(session.spot)
                        .font(.title.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    if let rating = session.rating, rating > 0 {
                        RatingDots(rating: rating)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fullLabel(session))

                Spacer(minLength: 0)
                startSessionButton
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 16) {
                extraLargeMetric(
                    session.date.formatted(.relative(presentation: .named)),
                    "last surf"
                )
                if let waveCount = session.waveCount {
                    extraLargeMetric("\(waveCount)", waveCount == 1 ? "wave" : "waves")
                }
                extraLargeMetric("\(snapshot.sessionsThisMonth)", "this month")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(peakSessionURL(id: session.sessionID))
    }

    private func extraLargeMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(PeakWidgetStyle.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var startSessionButton: some View {
        Button(intent: StartSessionIntent()) {
            Label("Start Session", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "figure.surfing")
                    .font(.title2)
                    .foregroundStyle(PeakWidgetStyle.muted)
                Text("Log your first surf")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)

            if showsStartSessionButton {
                Spacer(minLength: 0)
                startSessionButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(peakLogSessionURL)
    }

    /// Accessory families are too small for a button; small stays glanceable
    /// without one. Medium and extra-large must have it, including empty state.
    private var showsStartSessionButton: Bool {
        family == .systemMedium || family == .systemExtraLarge
    }

    /// Everything the widget shows, spoken in one element: spot, rating, when.
    private func fullLabel(_ session: DisplayedSession) -> String {
        var parts = ["Last surf at \(session.spot)"]
        if let rating = session.rating, rating > 0 {
            parts.append("rated \(rating) out of 5")
        }
        if let waveCount = session.waveCount {
            parts.append(waveCount == 1 ? "1 wave" : "\(waveCount) waves")
        }
        parts.append(session.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: ", ")
    }

    /// The session this widget is currently showing. A configured spot looks up
    /// its glance; otherwise this is the overall last session.
    private var displayed: DisplayedSession? {
        if let key = configuredSpotKey {
            guard let glance = snapshot.spotGlances?.first(where: { $0.key == key }),
                  let date = glance.lastSessionDate else { return nil }
            return DisplayedSession(
                spot: glance.name,
                date: date,
                rating: glance.lastSessionRating,
                waveCount: nil,
                sessionID: glance.lastSessionID
            )
        }
        guard let spot = snapshot.lastSessionSpot, let date = snapshot.lastSessionDate else { return nil }
        return DisplayedSession(
            spot: spot,
            date: date,
            rating: snapshot.lastSessionRating,
            waveCount: snapshot.lastSessionWaveCount,
            sessionID: snapshot.lastSessionID
        )
    }
}

/// Values the view actually renders, resolved from either a pinned glance or
/// the overall last session. Wave count only exists on the overall snapshot.
private struct DisplayedSession {
    var spot: String
    var date: Date
    var rating: Int?
    var waveCount: Int?
    var sessionID: String?
}
