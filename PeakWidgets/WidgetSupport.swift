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
        let snapshot = context.isPreview ? .preview : PeakWidgetStore.read()
        completion(PeakEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PeakEntry>) -> Void) {
        let snapshot = PeakWidgetStore.read()
        // Snapshot is push-updated by the app on every data change; refresh a few
        // times a day only so "days since" stays roughly current between edits.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [PeakEntry(date: .now, snapshot: snapshot)], policy: .after(next)))
    }
}

extension PeakWidgetSnapshot {
    /// Sample data for the widget gallery / previews.
    static let preview = PeakWidgetSnapshot(
        currentStreakWeeks: 3,
        totalSessions: 42,
        sessionsThisMonth: 6,
        lastSessionSpot: "Trestles",
        lastSessionDate: Calendar.current.date(byAdding: .day, value: -2, to: .now),
        lastSessionRating: 4,
        daysSinceLastSession: 2,
        generatedAt: .now
    )
}

/// Deep link that opens the app straight into the new-session sheet.
let peakLogSessionURL = URL(string: "peak://new-session")!

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
                    .font(.system(size: 6))
                    .foregroundStyle(index < rating ? PeakWidgetStyle.ink : PeakWidgetStyle.muted)
            }
        }
        .accessibilityLabel("\(rating) out of 5")
    }
}
