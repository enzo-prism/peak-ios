import WidgetKit
import SwiftUI

/// Timeline entry wrapping the shared snapshot the app publishes.
/// `configuredSpotKey` is only set by the Last Session widget's
/// `AppIntentConfiguration`; Streak keeps using `PeakSnapshotProvider` and
/// leaves it nil so it always shows the overall snapshot.
struct PeakEntry: TimelineEntry {
    let date: Date
    let snapshot: PeakWidgetSnapshot
    var configuredSpotKey: String? = nil
}

/// Common provider: reads the app-published snapshot from the App Group store.
/// The widget never touches SwiftData — it only renders what the app derived,
/// so there is no store to migrate or share.
struct PeakSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> PeakEntry {
        PeakEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PeakEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : PeakWidgetStore.read().adjusted(for: .now)
        completion(PeakEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PeakEntry>) -> Void) {
        completion(PeakEntry.midnightAlignedTimeline(snapshot: PeakWidgetStore.read()))
    }
}

extension PeakEntry {
    /// Snapshot is push-updated by the app on every data change. Between writes
    /// the time-relative values ("days since", "this month", streak) still move,
    /// and they all tick at local midnight — so pre-render one entry per upcoming
    /// midnight with the values re-derived for that day, instead of re-reading
    /// the same frozen scalars every few hours.
    ///
    /// Last Session passes `configuredSpotKey` through so a pinned spot survives
    /// those midnight reloads; Streak omits it.
    static func midnightAlignedTimeline(
        snapshot: PeakWidgetSnapshot,
        configuredSpotKey: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Timeline<PeakEntry> {
        var entries = [PeakEntry(date: now, snapshot: snapshot.adjusted(for: now), configuredSpotKey: configuredSpotKey)]
        var cursor = now
        for _ in 0..<3 {
            guard let midnight = calendar.nextDate(
                after: cursor,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { break }
            entries.append(PeakEntry(
                date: midnight,
                snapshot: snapshot.adjusted(for: midnight),
                configuredSpotKey: configuredSpotKey
            ))
            cursor = midnight
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

extension PeakWidgetSnapshot {
    /// Sample data for the widget gallery / previews.
    static let preview = PeakWidgetSnapshot(
        currentStreakWeeks: 3,
        totalSessions: 42,
        sessionsThisMonth: 6,
        lastSessionSpot: "Trestles",
        lastSessionSpotKey: "trestles",
        lastSessionDate: Calendar.current.date(byAdding: .day, value: -2, to: .now),
        lastSessionRating: 4,
        lastSessionWaveCount: 11,
        lastSessionID: "preview-session",
        daysSinceLastSession: 2,
        spotGlances: [
            PeakSpotGlance(
                key: "trestles",
                name: "Trestles",
                lastSessionID: "preview-session",
                lastSessionDate: Calendar.current.date(byAdding: .day, value: -2, to: .now),
                lastSessionRating: 4,
                sessionCount: 12
            )
        ],
        generatedAt: .now
    )
}

/// Deep link that opens the app straight into the new-session sheet.
/// Empty widgets and the Streak widget keep using this; Last Session uses
/// `peakSessionURL(id:)` so a tap reopens the session it is showing.
let peakLogSessionURL = PeakDeepLink.newSession

/// Opens that session when the snapshot carried an identifier; otherwise the
/// new-session sheet so a tap still does something useful (legacy snapshots,
/// empty glances).
func peakSessionURL(id: String?) -> URL {
    guard let id, !id.isEmpty else { return PeakDeepLink.newSession }
    return PeakDeepLink.session(id)
}

enum PeakWidgetStyle {
    static let ink = Color.primary
    static let muted = Color.secondary
}

/// Rating as filled/empty dots so VoiceOver reads a clean value and it renders
/// crisply at small sizes.
struct RatingDots: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "circle.fill" : "circle")
                    .font(.caption2)
                    .imageScale(.small)
                    .foregroundStyle(index < rating ? PeakWidgetStyle.ink : PeakWidgetStyle.muted)
            }
        }
        // Collapse the five images into one element so the label below is what
        // VoiceOver reads, not five separate "circle" images.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) out of 5")
    }
}
