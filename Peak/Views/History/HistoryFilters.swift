import Foundation
import SwiftData

/// The History tab's filter state plus the pure matching logic that applies it
/// (together with free-text search) to a list of sessions. Kept UI-free so the
/// whole pipeline is unit-testable: `apply(to:searchText:now:calendar:)` is a
/// pure function of its inputs.
struct HistoryFilters: Equatable {
    /// Relative date windows for narrowing the session list.
    enum DateRange: String, CaseIterable, Identifiable, Equatable {
        case allTime
        case thisMonth
        case lastThreeMonths
        case thisYear

        var id: String { rawValue }

        var label: String {
            switch self {
            case .allTime:
                return "All time"
            case .thisMonth:
                return "This month"
            case .lastThreeMonths:
                return "Last 3 months"
            case .thisYear:
                return "This year"
            }
        }

        /// Whether `date` falls inside the window, evaluated against `now`.
        func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
            switch self {
            case .allTime:
                return true
            case .thisMonth:
                return calendar.isDate(date, equalTo: now, toGranularity: .month)
            case .lastThreeMonths:
                guard let cutoff = calendar.date(byAdding: .month, value: -3, to: now) else {
                    return true
                }
                return date >= cutoff
            case .thisYear:
                return calendar.isDate(date, equalTo: now, toGranularity: .year)
            }
        }
    }

    /// Empty set means "all spots"; within a category selections are OR'd,
    /// across categories filters are AND'd.
    var spots: Set<Spot> = []
    var gear: Set<Gear> = []
    var buddies: Set<Buddy> = []
    /// 0 means "any rating"; 1...5 keeps sessions rated at least this value.
    var minimumRating: Int = 0
    var dateRange: DateRange = .allTime

    var isActive: Bool {
        !spots.isEmpty || !gear.isEmpty || !buddies.isEmpty || minimumRating > 0 || dateRange != .allTime
    }

    // MARK: - Pure filter pipeline

    /// Applies filters + free-text search (AND semantics) preserving order.
    func apply(
        to sessions: [SurfSession],
        searchText: String = "",
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SurfSession] {
        let query = HistoryFilters.foldedQuery(from: searchText)
        return sessions.filter { matches(session: $0, foldedQuery: query, now: now, calendar: calendar) }
    }

    func matches(
        session: SurfSession,
        searchText: String = "",
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        matches(
            session: session,
            foldedQuery: HistoryFilters.foldedQuery(from: searchText),
            now: now,
            calendar: calendar
        )
    }

    private func matches(session: SurfSession, foldedQuery: String, now: Date, calendar: Calendar) -> Bool {
        if !spots.isEmpty {
            guard let spotID = session.spot?.persistentModelID,
                  spots.contains(where: { $0.persistentModelID == spotID }) else {
                return false
            }
        }
        if !gear.isEmpty {
            guard gear.contains(where: { selected in
                session.gear.contains { $0.persistentModelID == selected.persistentModelID }
            }) else {
                return false
            }
        }
        if !buddies.isEmpty {
            guard buddies.contains(where: { selected in
                session.buddies.contains { $0.persistentModelID == selected.persistentModelID }
            }) else {
                return false
            }
        }
        if minimumRating > 0, session.rating < minimumRating {
            return false
        }
        if !dateRange.contains(session.date, now: now, calendar: calendar) {
            return false
        }
        return HistoryFilters.sessionMatches(session, foldedQuery: foldedQuery)
    }

    // MARK: - Search matching

    /// Case-, diacritic-, and width-insensitive query form (see `String.searchFolded`).
    static func foldedQuery(from raw: String) -> String {
        raw.searchFolded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matches spot name, spot location, notes, buddy names, and gear names.
    static func sessionMatches(_ session: SurfSession, foldedQuery: String) -> Bool {
        guard !foldedQuery.isEmpty else { return true }
        if let spot = session.spot {
            if spot.name.searchFolded.contains(foldedQuery) {
                return true
            }
            if let location = spot.locationName, location.searchFolded.contains(foldedQuery) {
                return true
            }
        }
        if session.notes.searchFolded.contains(foldedQuery) {
            return true
        }
        if session.buddies.contains(where: { $0.name.searchFolded.contains(foldedQuery) }) {
            return true
        }
        if session.gear.contains(where: { $0.name.searchFolded.contains(foldedQuery) }) {
            return true
        }
        return false
    }

    // MARK: - Mutation

    mutating func clear() {
        spots.removeAll()
        gear.removeAll()
        buddies.removeAll()
        minimumRating = 0
        dateRange = .allTime
    }

    mutating func toggleSpot(_ spot: Spot) {
        if spots.contains(spot) {
            spots.remove(spot)
        } else {
            spots.insert(spot)
        }
    }

    mutating func toggleGear(_ item: Gear) {
        if gear.contains(item) {
            gear.remove(item)
        } else {
            gear.insert(item)
        }
    }

    mutating func toggleBuddy(_ buddy: Buddy) {
        if buddies.contains(buddy) {
            buddies.remove(buddy)
        } else {
            buddies.insert(buddy)
        }
    }
}

/// Which History/Search body to show. Kept UI-free so the Search tab's idle
/// prompt (not a second copy of the timeline) is unit-testable.
enum HistoryListMode: Equatable {
    case emptyLogbook
    case searchPrompt
    case noMatches
    case results

    static func resolve(
        sessionCount: Int,
        isDedicatedSearchTab: Bool,
        hasActiveCriteria: Bool,
        matchCount: Int
    ) -> HistoryListMode {
        if sessionCount == 0 {
            return .emptyLogbook
        }
        if isDedicatedSearchTab && !hasActiveCriteria {
            return .searchPrompt
        }
        if hasActiveCriteria && matchCount == 0 {
            return .noMatches
        }
        return .results
    }
}
