import Foundation
import WidgetKit

/// A small, derived snapshot the app writes to a shared App Group container so
/// the widget can render without touching the SwiftData store (the store stays
/// in the app's own container — no risky App Group store migration). The app
/// recomputes and rewrites this whenever its data changes; the widget only reads.
/// Per-spot glance the Last Session widget can be configured to show, derived
/// in the app and stored on the snapshot so the extension never opens SwiftData.
nonisolated struct PeakSpotGlance: Codable, Equatable, Hashable, Identifiable {
    var key: String
    var name: String
    var lastSessionID: String?
    var lastSessionDate: Date?
    var lastSessionRating: Int?
    var sessionCount: Int

    var id: String { key }
}

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
    /// Waves logged on the last session, when it has any. Optional because most
    /// sessions carry no wave stats at all, and a widget must never print "0
    /// waves" for a session that simply was not tracked.
    var lastSessionWaveCount: Int?
    /// Stable session identifier (`SessionIntentQueries.identifier`) so a Last
    /// Session widget tap can open *that* session, not a blank editor.
    var lastSessionID: String?
    var daysSinceLastSession: Int?
    /// Frequent spots, most-logged first, so a configurable widget can pick one
    /// without the extension querying the store. Capped by the writer.
    var spotGlances: [PeakSpotGlance]?
    var generatedAt: Date

    init(
        currentStreakWeeks: Int,
        totalSessions: Int,
        sessionsThisMonth: Int,
        lastSessionSpot: String? = nil,
        lastSessionSpotKey: String? = nil,
        lastSessionDate: Date? = nil,
        lastSessionRating: Int? = nil,
        lastSessionWaveCount: Int? = nil,
        lastSessionID: String? = nil,
        daysSinceLastSession: Int? = nil,
        spotGlances: [PeakSpotGlance]? = nil,
        generatedAt: Date
    ) {
        self.currentStreakWeeks = currentStreakWeeks
        self.totalSessions = totalSessions
        self.sessionsThisMonth = sessionsThisMonth
        self.lastSessionSpot = lastSessionSpot
        self.lastSessionSpotKey = lastSessionSpotKey
        self.lastSessionDate = lastSessionDate
        self.lastSessionRating = lastSessionRating
        self.lastSessionWaveCount = lastSessionWaveCount
        self.lastSessionID = lastSessionID
        self.daysSinceLastSession = daysSinceLastSession
        self.spotGlances = spotGlances
        self.generatedAt = generatedAt
    }

    static let empty = PeakWidgetSnapshot(
        currentStreakWeeks: 0,
        totalSessions: 0,
        sessionsThisMonth: 0,
        generatedAt: .distantPast
    )

    /// Re-derives the time-relative values for display at `date`. The snapshot
    /// is only rewritten when the app runs, so a widget that keeps rendering the
    /// stored scalars shows "Surfed today" for a week if the app isn't opened.
    /// Sessions are only ever added through the app (which rewrites the
    /// snapshot), so between writes the library is known to be unchanged and
    /// every one of these values is derivable from `lastSessionDate` alone:
    /// - `daysSinceLastSession` is recounted against `date`.
    /// - `sessionsThisMonth` resets to zero once `date` leaves the month the
    ///   snapshot was generated in.
    /// - the week streak keeps its stored value while the last session sits in
    ///   `date`'s week or the week before (the same current-week grace
    ///   `StatsCalculator` gives), and breaks to zero after that.
    func adjusted(for date: Date, calendar: Calendar = .current) -> PeakWidgetSnapshot {
        var adjusted = self

        if let lastSessionDate {
            adjusted.daysSinceLastSession = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastSessionDate),
                to: calendar.startOfDay(for: date)
            ).day ?? daysSinceLastSession

            if let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastSessionDate),
               let graceEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: lastWeek.end),
               date >= graceEnd {
                adjusted.currentStreakWeeks = 0
            }
        }

        if !calendar.isDate(date, equalTo: generatedAt, toGranularity: .month) {
            adjusted.sessionsThisMonth = 0
        }

        return adjusted
    }
}

/// One place to ask WidgetKit for a refresh, so the test gate is stated once.
nonisolated enum PeakWidgetRefresh {
    /// Skipped under UI test: no widgets are installed for the suite to look at,
    /// and waking the extension on every session change costs enough simulator
    /// time to turn unrelated `waitForExistence` assertions flaky. The snapshot
    /// itself is still written, so nothing about the data path is bypassed.
    static func reloadTimelines() {
        guard !TestingDefaults.isUITest else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The URL scheme the widgets and Live Activity use to hand the surfer back to
/// the app. Shared so the writer of the link and the reader of the link can
/// never drift apart.
nonisolated enum PeakDeepLink {
    static let scheme = "peak"

    /// Opens Peak straight into the new-session sheet.
    static let newSession = URL(string: "peak://new-session")!

    enum Destination: Equatable {
        case newSession
        case session(id: String)
        case spot(id: String)
        case gear(id: String)
        case search(query: String)
    }

    static func isNewSession(_ url: URL) -> Bool {
        parse(url) == .newSession
    }

    static func session(_ id: String) -> URL {
        make(host: "session", id: id)
    }

    static func spot(_ id: String) -> URL {
        make(host: "spot", id: id)
    }

    static func gear(_ id: String) -> URL {
        make(host: "gear", id: id)
    }

    static func search(_ query: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "search"
        if !query.isEmpty {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components.url ?? URL(string: "peak://search")!
    }

    static func parse(_ url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }
        let host = (url.host ?? "").lowercased()
        let pathTrimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryID = components?.queryItems?.first(where: { $0.name == "id" })?.value
        let queryQ = components?.queryItems?.first(where: { $0.name == "q" })?.value

        func entityID() -> String? {
            if let queryID {
                let trimmed = queryID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            let trimmedPath = pathTrimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPath.isEmpty {
                return trimmedPath.removingPercentEncoding ?? trimmedPath
            }
            return nil
        }

        switch host {
        case "new-session":
            return .newSession
        case "session":
            guard let id = entityID() else { return nil }
            return .session(id: id)
        case "spot":
            guard let id = entityID() else { return nil }
            return .spot(id: id)
        case "gear":
            guard let id = entityID() else { return nil }
            return .gear(id: id)
        case "search":
            return .search(query: queryQ ?? "")
        case "":
            // `peak:///new-session` puts the host in the path.
            if pathTrimmed == "new-session" { return .newSession }
            return nil
        default:
            return nil
        }
    }

    private static func make(host: String, id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url ?? URL(string: "peak://\(host)")!
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
