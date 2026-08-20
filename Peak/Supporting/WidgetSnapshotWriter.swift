import Foundation
import SwiftData

/// App-side helper that derives a `PeakWidgetSnapshot` from the current sessions
/// and publishes it to the shared App Group store, then asks WidgetKit to reload.
/// Called on launch and whenever sessions change.
enum WidgetSnapshotWriter {
    static func update(from sessions: [SurfSession], now: Date = Date(), calendar: Calendar = .current) {
        let snapshot = makeSnapshot(from: sessions, now: now, calendar: calendar)
        let existing = PeakWidgetStore.read()
        guard shouldPublish(snapshot, replacing: existing) else { return }
        PeakWidgetStore.write(snapshot)
        PeakWidgetRefresh.reloadTimelines()
    }

    /// `PeakWidgetSnapshot.empty` is the stand-in for a missing file, so the
    /// first write of a genuinely empty logbook still lands. After that, skip
    /// the App Group write and `WidgetCenter.reloadAllTimelines()` when the
    /// widgets would render the same payload (Apple: reload only when timelines
    /// change).
    static func shouldPublish(
        _ snapshot: PeakWidgetSnapshot,
        replacing existing: PeakWidgetSnapshot
    ) -> Bool {
        if existing.generatedAt == .distantPast { return true }
        return !existing.hasSameWidgetPayload(as: snapshot)
    }

    /// Pure, testable derivation of the snapshot.
    static func makeSnapshot(from sessions: [SurfSession], now: Date = Date(), calendar: Calendar = .current) -> PeakWidgetSnapshot {
        // One O(n) pass for "latest" — no extra sorted copy. Ties keep the
        // first maximum, matching a stable reverse-date sort.
        let last = sessions.max { $0.date < $1.date }
        let lastID = last.map(SessionIntentQueries.identifier(for:))

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
            lastSessionID: lastID,
            daysSinceLastSession: daysSinceLast,
            spotGlances: spotGlances(from: sessions, limit: 8),
            generatedAt: now
        )
    }

    /// Most-logged spots first so a configurable widget has something to pick.
    /// Tied spots sort by name. Spots with no name are skipped.
    static func spotGlances(from sessions: [SurfSession], limit: Int) -> [PeakSpotGlance] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var latest: [String: SurfSession] = [:]
        for session in sessions {
            guard let spot = session.spot, let name = spot.name.trimmedNonEmpty else { continue }
            counts[spot.key, default: 0] += 1
            names[spot.key] = name
            if let existing = latest[spot.key] {
                if session.date > existing.date { latest[spot.key] = session }
            } else {
                latest[spot.key] = session
            }
        }
        let orderedKeys = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return (names[lhs] ?? lhs).localizedCaseInsensitiveCompare(names[rhs] ?? rhs) == .orderedAscending
        }
        return Array(orderedKeys.prefix(max(0, limit))).compactMap { key in
            guard let name = names[key] else { return nil }
            let session = latest[key]
            return PeakSpotGlance(
                key: key,
                name: name,
                lastSessionID: session.map(SessionIntentQueries.identifier(for:)),
                lastSessionDate: session?.date,
                lastSessionRating: session.map(\.rating),
                sessionCount: counts[key] ?? 0
            )
        }
    }
}
