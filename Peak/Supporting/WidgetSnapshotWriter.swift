import Foundation
import SwiftData
import WidgetKit

/// App-side helper that derives a `PeakWidgetSnapshot` from the current sessions
/// and publishes it to the shared App Group store, then asks WidgetKit to reload.
/// Called on launch and whenever sessions change.
enum WidgetSnapshotWriter {
    static func update(from sessions: [SurfSession], now: Date = Date(), calendar: Calendar = .current) {
        let snapshot = makeSnapshot(from: sessions, now: now, calendar: calendar)
        PeakWidgetStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Pure, testable derivation of the snapshot.
    static func makeSnapshot(from sessions: [SurfSession], now: Date = Date(), calendar: Calendar = .current) -> PeakWidgetSnapshot {
        let sorted = sessions.sorted { $0.date > $1.date }
        let last = sorted.first

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        let sessionsThisMonth = monthStart.map { start in
            sessions.filter { $0.date >= start && $0.date <= now }.count
        } ?? 0

        let daysSinceLast = last.map { session in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: session.date), to: calendar.startOfDay(for: now)).day ?? 0
        }

        return PeakWidgetSnapshot(
            currentStreakWeeks: StatsCalculator.surfDaysThisYear(sessions: sessions, referenceDate: now, calendar: calendar).currentWeekStreak,
            totalSessions: sessions.count,
            sessionsThisMonth: sessionsThisMonth,
            lastSessionSpot: last?.spot?.name,
            lastSessionDate: last?.date,
            lastSessionRating: last.map { $0.rating },
            daysSinceLastSession: daysSinceLast,
            generatedAt: now
        )
    }
}
