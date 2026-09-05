import Foundation

/// The logic behind Peak's App Intents entities and intents, kept as a
/// stateless enum over plain arrays so every rule — identifier stability,
/// lookup, ordering, the sentences Siri speaks — is unit-testable without a
/// store, an intent runtime, or a device.
///
/// The `AppEntity` / `EntityQuery` types in `AppIntentsEntities.swift` fetch
/// from SwiftData and then delegate here.
enum SessionIntentQueries {
    /// How many entities a "suggested"/Spotlight listing offers before it stops
    /// being a menu and starts being a data dump.
    static let suggestionLimit = 12

    // MARK: - Stable identifiers

    /// Portable UUID identity survives edits, export and restore. The timestamp
    /// fallback only covers an unmigrated in-memory legacy fixture.
    static func identifier(for session: SurfSession) -> String {
        session.sessionID?.uuidString ?? String(SurfSession.millisecondsKey(for: session.createdAt))
    }

    /// Spots already carry a unique, normalized key — reuse it rather than
    /// inventing a second identity.
    static func identifier(for spot: Spot) -> String {
        spot.key
    }

    /// Gear already carries a unique `kind|normalized-name` key.
    static func identifier(for gear: Gear) -> String {
        gear.key
    }

    // MARK: - Lookup

    static func sessions(withIdentifiers identifiers: [String], in sessions: [SurfSession]) -> [SurfSession] {
        let wanted = Set(identifiers)
        guard !wanted.isEmpty else { return [] }
        let legacyGroups = Dictionary(grouping: sessions) {
            String(SurfSession.millisecondsKey(for: $0.createdAt))
        }
        return sessions.filter { session in
            if session.sessionID != nil && wanted.contains(identifier(for: session)) { return true }
            let legacy = String(SurfSession.millisecondsKey(for: session.createdAt))
            return wanted.contains(legacy) && legacyGroups[legacy]?.count == 1
        }
    }

    static func spots(withIdentifiers identifiers: [String], in spots: [Spot]) -> [Spot] {
        let wanted = Set(identifiers)
        guard !wanted.isEmpty else { return [] }
        return spots.filter { wanted.contains(identifier(for: $0)) }
    }

    /// Free-text spot matching for "…at Trestles" style phrasing. Tries the
    /// normalized key first, then a `searchFolded` contains match on the display
    /// name — the same case- and diacritic-insensitive comparison the rest of
    /// the app uses for user-typed queries, so "sao vicente" finds "São Vicente".
    static func spots(matching term: String, in spots: [Spot]) -> [Spot] {
        guard let cleaned = term.trimmedNonEmpty else { return orderedSpots(spots) }
        let key = Spot.makeKey(from: cleaned)
        let folded = cleaned.searchFolded

        let matches = spots.filter { spot in
            spot.key == key ||
            spot.key.contains(key) ||
            spot.name.searchFolded.contains(folded)
        }
        return orderedSpots(matches)
    }

    static func gearItems(withIdentifiers identifiers: [String], in gear: [Gear]) -> [Gear] {
        let wanted = Set(identifiers)
        guard !wanted.isEmpty else { return [] }
        return gear.filter { wanted.contains(identifier(for: $0)) }
    }

    /// Free-text gear matching for "…on my fish" style phrasing.
    static func gearItems(matching term: String, in gear: [Gear]) -> [Gear] {
        guard let cleaned = term.trimmedNonEmpty else { return orderedGear(gear) }
        let folded = cleaned.searchFolded
        let matches = gear.filter { item in
            item.key.contains(cleaned.normalizedKey) ||
            item.name.searchFolded.contains(folded) ||
            (item.brand?.searchFolded.contains(folded) ?? false)
        }
        return orderedGear(matches)
    }

    /// Most-used gear first, then alphabetical. Unused items still appear, last.
    static func frequentGear(
        from gear: [Gear],
        sessions: [SurfSession],
        limit: Int = suggestionLimit
    ) -> [Gear] {
        var counts: [String: Int] = [:]
        for session in sessions {
            for item in session.gear {
                counts[item.key, default: 0] += 1
            }
        }
        let ordered = gear.sorted { lhs, rhs in
            let lhsCount = counts[lhs.key] ?? 0
            let rhsCount = counts[rhs.key] ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return Array(ordered.prefix(max(0, limit)))
    }

    /// Most recent first — the order a surfer thinks in.
    static func recentSessions(from sessions: [SurfSession], limit: Int = suggestionLimit) -> [SurfSession] {
        Array(sessions.sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }

    /// Spots the surfer actually uses, most-logged first, then alphabetically so
    /// ties are stable. Spots with no sessions still appear, just last.
    static func frequentSpots(
        from spots: [Spot],
        sessions: [SurfSession],
        limit: Int = suggestionLimit
    ) -> [Spot] {
        var counts: [String: Int] = [:]
        for session in sessions {
            guard let key = session.spot?.key else { continue }
            counts[key, default: 0] += 1
        }
        let ordered = spots.sorted { lhs, rhs in
            let lhsCount = counts[lhs.key] ?? 0
            let rhsCount = counts[rhs.key] ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return Array(ordered.prefix(max(0, limit)))
    }

    private static func orderedSpots(_ spots: [Spot]) -> [Spot] {
        spots.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func orderedGear(_ gear: [Gear]) -> [Gear] {
        gear.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Intent answers

    static func lastSession(in sessions: [SurfSession]) -> SurfSession? {
        sessions.max { $0.date < $1.date }
    }

    static func sessionsThisMonth(
        in sessions: [SurfSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SurfSession] {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        // Half-open on purpose: `DateInterval.contains` is inclusive of `end`,
        // which would count the first instant of next month as this month.
        // Clamped to `now` so a session logged ahead of time doesn't count
        // until it has actually happened — the widget applies the same rule,
        // and the two surfaces must never disagree on this number.
        return sessions
            .filter { $0.date >= month.start && $0.date <= now }
            .sorted { $0.date > $1.date }
    }

    /// "When did I last surf?" — a sentence, not a data structure, because this
    /// is what Siri reads aloud.
    static func lastSessionDialog(
        for session: SurfSession?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let session else {
            return "You haven't logged a surf session yet."
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: session.date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        let whenPhrase: String
        switch days {
        case ..<0: whenPhrase = "You have a session logged for the future"
        case 0: whenPhrase = "You surfed today"
        case 1: whenPhrase = "You surfed yesterday"
        default: whenPhrase = "You last surfed \(days) days ago"
        }

        guard let spot = session.spot?.name.trimmedNonEmpty else {
            return whenPhrase + "."
        }
        return whenPhrase + " at \(spot)."
    }

    /// "How many sessions this month?"
    static func sessionsThisMonthDialog(count: Int, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        let month = formatter.string(from: now)

        switch count {
        case 0: return "You haven't logged any sessions in \(month) yet."
        case 1: return "You've logged 1 session in \(month)."
        default: return "You've logged \(count) sessions in \(month)."
        }
    }
}
