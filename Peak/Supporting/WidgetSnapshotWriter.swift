import Foundation
import SwiftData

/// App-side helper that derives a `PeakWidgetSnapshot` from the current sessions
/// and publishes it to the shared App Group store, then asks WidgetKit to reload.
/// Called on launch and whenever sessions change.
enum WidgetSnapshotWriter {
    static func update(from sessions: [SurfSession], now: Date = Date(), calendar: Calendar = .current) {
        let snapshot = makeSnapshot(from: sessions, now: now, calendar: calendar)
        PeakWidgetStore.write(snapshot)
        PeakWidgetRefresh.reloadTimelines()
    }

    /// Pure, testable derivation of the snapshot.
    static func makeSnapshot(from sessions: [SurfSession], now: Date = Date(), calendar: Calendar = .current) -> PeakWidgetSnapshot {
        let sorted = sessions.sorted { $0.date > $1.date }
        let last = sorted.first

        // Same definition as `SessionIntentQueries.sessionsThisMonth`, so the
        // widget and Siri can never disagree about the count.
        let sessionsThisMonth = SessionIntentQueries.sessionsThisMonth(
            in: sessions, now: now, calendar: calendar
        ).count

        let daysSinceLast = last.map { session in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: session.date), to: calendar.startOfDay(for: now)).day ?? 0
        }

        return PeakWidgetSnapshot(
            currentStreakWeeks: StatsCalculator.surfDaysThisYear(sessions: sessions, referenceDate: now, calendar: calendar).currentWeekStreak,
            totalSessions: sessions.count,
            sessionsThisMonth: sessionsThisMonth,
            lastSessionSpot: last?.spot?.name,
            lastSessionSpotKey: last?.spot?.key,
            lastSessionDate: last?.date,
            lastSessionRating: last.map { $0.rating },
            lastSessionWaveCount: last?.waveCount,
            daysSinceLastSession: daysSinceLast,
            generatedAt: now
        )
    }
}
