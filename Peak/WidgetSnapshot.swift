import Foundation

/// A small, derived snapshot the app writes to a shared App Group container so
/// the widget can render without touching the SwiftData store (the store stays
/// in the app's own container — no risky App Group store migration). The app
/// recomputes and rewrites this whenever its data changes; the widget only reads.
struct PeakWidgetSnapshot: Codable, Equatable {
    var currentStreakWeeks: Int
    var totalSessions: Int
    var sessionsThisMonth: Int
    var lastSessionSpot: String?
    var lastSessionDate: Date?
    var lastSessionRating: Int?
    var daysSinceLastSession: Int?
    var generatedAt: Date

    static let empty = PeakWidgetSnapshot(
        currentStreakWeeks: 0,
        totalSessions: 0,
        sessionsThisMonth: 0,
        lastSessionSpot: nil,
        lastSessionDate: nil,
        lastSessionRating: nil,
        daysSinceLastSession: nil,
        generatedAt: .distantPast
    )
}

/// Shared read/write for the widget snapshot, backed by a JSON file in the App
/// Group container. Safe to call from either the app or the widget extension.
enum PeakWidgetStore {
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
