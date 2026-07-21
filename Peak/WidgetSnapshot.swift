import Foundation

/// A small, derived snapshot the app writes to a shared App Group container so
/// the widget can render without touching the SwiftData store (the store stays
/// in the app's own container — no risky App Group store migration). The app
/// recomputes and rewrites this whenever its data changes; the widget only reads.
nonisolated struct PeakWidgetSnapshot: Codable, Equatable {
    var currentStreakWeeks: Int
    var totalSessions: Int
    var sessionsThisMonth: Int
    var lastSessionSpot: String?
    /// `Spot.key` for the last session's spot, so a session started from the
    /// Action button or Control Center can preselect it without the store.
    var lastSessionSpotKey: String?
    var lastSessionDate: Date?
    var lastSessionRating: Int?
    var daysSinceLastSession: Int?
    var generatedAt: Date

    init(
        currentStreakWeeks: Int,
        totalSessions: Int,
        sessionsThisMonth: Int,
        lastSessionSpot: String? = nil,
        lastSessionSpotKey: String? = nil,
        lastSessionDate: Date? = nil,
        lastSessionRating: Int? = nil,
        daysSinceLastSession: Int? = nil,
        generatedAt: Date
    ) {
        self.currentStreakWeeks = currentStreakWeeks
        self.totalSessions = totalSessions
        self.sessionsThisMonth = sessionsThisMonth
        self.lastSessionSpot = lastSessionSpot
        self.lastSessionSpotKey = lastSessionSpotKey
        self.lastSessionDate = lastSessionDate
        self.lastSessionRating = lastSessionRating
        self.daysSinceLastSession = daysSinceLastSession
        self.generatedAt = generatedAt
    }

    static let empty = PeakWidgetSnapshot(
        currentStreakWeeks: 0,
        totalSessions: 0,
        sessionsThisMonth: 0,
        generatedAt: .distantPast
    )
}

/// The URL scheme the widgets and Live Activity use to hand the surfer back to
/// the app. Shared so the writer of the link and the reader of the link can
/// never drift apart.
nonisolated enum PeakDeepLink {
    /// Opens Peak straight into the new-session sheet.
    static let newSession = URL(string: "peak://new-session")!

    static func isNewSession(_ url: URL) -> Bool {
        guard url.scheme == newSession.scheme else { return false }
        // Widgets hand back `peak://new-session` (host), but a link built with a
        // trailing slash lands the same word in `path` — accept both.
        return url.host == "new-session" || url.path == "/new-session"
    }
}

/// Shared read/write for the widget snapshot, backed by a JSON file in the App
/// Group container. Safe to call from either the app or the widget extension.
nonisolated enum PeakWidgetStore {
    static let appGroupIdentifier = "group.com.designprism.peak"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func write(_ snapshot: PeakWidgetSnapshot) {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> PeakWidgetSnapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(PeakWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
