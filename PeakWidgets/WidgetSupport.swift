import WidgetKit
import SwiftUI

/// Timeline entry wrapping the shared snapshot the app publishes.
struct PeakEntry: TimelineEntry {
    let date: Date
    let snapshot: PeakWidgetSnapshot
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
        let snapshot = PeakWidgetStore.read()
        // Snapshot is push-updated by the app on every data change. Between
        // writes the time-relative values ("days since", "this month", streak)
        // still move, and they all tick at local midnight — so pre-render one
        // entry per upcoming midnight with the values re-derived for that day,
        // instead of re-reading the same frozen scalars every few hours.
        let calendar = Calendar.current
        let now = Date.now
        var entries = [PeakEntry(date: now, snapshot: snapshot.adjusted(for: now))]
        var cursor = now
        for _ in 0..<3 {
            guard let midnight = calendar.nextDate(
                after: cursor,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { break }
            entries.append(PeakEntry(date: midnight, snapshot: snapshot.adjusted(for: midnight)))
            cursor = midnight
        }
        completion(Timeline(entries: entries, policy: .atEnd))
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
        daysSinceLastSession: 2,
        generatedAt: .now
    )
}

/// Deep link that opens the app straight into the new-session sheet.
let peakLogSessionURL = PeakDeepLink.newSession

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
