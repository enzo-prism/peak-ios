import Foundation

/// Exact questions use the whole candidate set, never a top-k semantic result.
/// This intentionally bounded grammar is also the offline/non-AI fallback.
enum LogbookQuery {
    enum Operation { case find, count, boardUsage, time }
    struct Answer {
        let title: String
        let explanation: String
        let sessions: [SurfSession]
        var needsFilters: Bool = false
    }

    static let dateScopes: [(String, HistoryFilters.DateRange)] = [
        ("this month", .thisMonth), ("last month", .lastMonth), ("this year", .thisYear),
        ("last week", .lastWeek), ("yesterday", .yesterday), ("today", .today)
    ]

    static func suggestedFilters(_ question: String, sessions: [SurfSession]) -> HistoryFilters {
        let query = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var filters = HistoryFilters()
        let scopes = dateScopes.filter { query.contains($0.0) }
        if scopes.count == 1 { filters.dateRange = scopes[0].1 }
        filters.spots = Set(sessions.compactMap(\.spot).filter { containsName($0.name, in: query) })
        filters.gear = Set(sessions.flatMap(\.gear).filter { containsName($0.name, in: query) })
        return filters
    }

    static func answer(_ question: String, sessions: [SurfSession], now: Date = Date(),
                       calendar: Calendar = .current) -> Answer {
        let query = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard query.trimmedNonEmpty != nil else {
            return Answer(title: "Ask about your surfing", explanation: "Try “How many sessions this month?” or “Which board did I use most?”", sessions: [], needsFilters: true)
        }
        let unsupported = ["not ", "without ", "except ", "before ", "after ", "waves", "fastest", "longest", "last year"]
        if unsupported.contains(where: { query.contains($0) }) || query.range(of: "\\b[0-9]{4}\\b", options: .regularExpression) != nil {
            return Answer(title: "That question needs a filter", explanation: "I can count sessions, compare board usage, and find saved spots, boards or clean/crowded/windy notes for a supported date range. Use History filters for other date ranges.", sessions: [], needsFilters: true)
        }
        let operation: Operation = query.contains("hours") || query.contains("time in water") ? .time : query.contains("how many") || query.contains("count") ? .count
            : (query.contains("which board") || query.contains("most used board")) ? .boardUsage : .find
        var matches = sessions
        let requestedScopes = dateScopes.filter { query.contains($0.0) }
        guard requestedScopes.count <= 1 else {
            return Answer(title: "Choose one date range", explanation: "Ask about one date range at a time. No partial count is shown.", sessions: [], needsFilters: true)
        }
        if let scope = requestedScopes.first {
            matches = matches.filter { scope.1.contains($0.date, now: now, calendar: calendar) }
        }
        let spotNames = Set(sessions.compactMap { $0.spot?.name })
        let spotMatches = spotNames.filter { containsName($0, in: query) }
        if (query.contains(" at ") || query.contains(" in ")) && spotMatches.isEmpty
            && !query.contains("time in water") && !query.contains(" in peak") && !query.contains(" in my ") && !query.contains(" in the ") {
            return Answer(title: "Choose a saved spot", explanation: "Use the exact name of a spot in your library so an unknown place never becomes an unfiltered count.", sessions: [], needsFilters: true)
        }
        if !spotMatches.isEmpty { matches = matches.filter { spotMatches.contains($0.spot?.name ?? "") } }
        let boards = Dictionary(sessions.flatMap(\.gear).filter { $0.kind == .board }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let namedBoards = boards.values.filter { containsName($0.name, in: query) }
        // A partially understood question must never become an exact-looking
        // total. Remove supported scopes/entities, then reject unknown criteria.
        var remainder = query
        for name in Array(spotMatches) + namedBoards.map(\.name) {
            let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            remainder = remainder.replacingOccurrences(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: normalized) + "(?![\\p{L}\\p{N}])", with: " ", options: .regularExpression)
        }
        for (scope, _) in dateScopes { remainder = remainder.replacingOccurrences(of: scope, with: " ") }
        let allowed = Set("how many count session sessions surfs surf surfing did do have had i my me log logged show find search for most used use which board boards with at in on the a an all clean crowded windy morning afternoon peak notes and hours time water".split(separator: " ").map(String.init))
        let words = remainder.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if operation != .find || !spotMatches.isEmpty || !namedBoards.isEmpty ||
            (["morning", "afternoon", "clean", "crowded", "windy"] + dateScopes.map(\.0)).contains(where: query.contains) {
            guard words.allSatisfy(allowed.contains) else {
                return Answer(title: "That question needs a filter", explanation: "I could not apply every condition in this question. Use a saved spot or board name, this month/last month/this year, morning/afternoon, or clean/crowded/windy notes. No partial count is shown.", sessions: [], needsFilters: true)
            }
        }
        if !namedBoards.isEmpty { matches = matches.filter { session in namedBoards.contains { board in session.gear.contains { $0.key == board.key } } } }
        if query.contains("morning") { matches = matches.filter { calendar.component(.hour, from: $0.date) < 12 } }
        if query.contains("afternoon") { matches = matches.filter { calendar.component(.hour, from: $0.date) >= 12 } }
        // These describe the person's written notes; never infer actual wind
        // quality from a compass direction without a break orientation model.
        let concepts: [(String, [String])] = [
            ("clean", ["clean", "glassy", "smooth"]),
            ("crowded", ["crowded", "crowd", "busy", "packed"]),
            ("windy", ["windy", "blown", "choppy"])
        ]
        for (concept, terms) in concepts where query.contains(concept) {
            matches = matches.filter { session in terms.contains { session.notes.localizedCaseInsensitiveContains($0) } }
        }
        matches.sort { $0.date > $1.date }
        switch operation {
        case .time:
            let time = StatsCalculator.timeInWater(sessions: matches)
            return Answer(title: time.sessionsWithDuration > 0 ? SessionDurationFormatter.string(from: time.totalMinutes) : "No durations logged",
                          explanation: "Recorded time from \(time.sessionsWithDuration) of \(matches.count) matching sessions. Missing durations are excluded.", sessions: matches)
        case .count:
            return Answer(title: "\(matches.count) logged session\(matches.count == 1 ? "" : "s")",
                          explanation: "Exact count from the matching records in your logbook.", sessions: matches)
        case .boardUsage:
            var counts: [String: Int] = [:]
            for session in matches {
                for key in Set(session.gear.filter { $0.kind == .board }.map(\.key)) { counts[key, default: 0] += 1 }
            }
            guard let maximum = counts.values.max() else {
                return Answer(title: "No board history yet", explanation: "Attach a board to a session to compare usage.", sessions: matches)
            }
            let winners = counts.filter { $0.value == maximum }.keys.sorted()
            let names = winners.compactMap { boards[$0]?.name }.joined(separator: ", ")
            return Answer(title: names, explanation: "\(maximum) matching sessions each\(winners.count > 1 ? " — tied for most used" : " — most used board"). Usage is not a measure of performance.", sessions: matches.filter { session in session.gear.contains { winners.contains($0.key) } })
        case .find:
            let recognized = !spotMatches.isEmpty || !namedBoards.isEmpty || concepts.contains { query.contains($0.0) }
                || (["morning", "afternoon", "all sessions"] + dateScopes.map(\.0)).contains { query.contains($0) }
            guard recognized else {
                // A literal free-text search has a truthful fallback; do not
                // answer arbitrary questions with the whole logbook.
                let literal = sessions.filter { $0.notes.localizedCaseInsensitiveContains(question) }
                return Answer(title: literal.isEmpty ? "Try a more specific question" : "Matching notes",
                              explanation: "Search a saved spot or board name, clean/crowded/windy notes, or a month. Peak only answers from logged records.", sessions: literal, needsFilters: literal.isEmpty)
            }
            return Answer(title: "\(matches.count) matching sessions", explanation: "Matches use saved names, dates and your written notes. Open a record to check the evidence.", sessions: matches)
        }
    }
    private static func containsName(_ name: String, in query: String) -> Bool {
        let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: normalized) + "(?![\\p{L}\\p{N}])"
        return query.range(of: pattern, options: .regularExpression) != nil
    }

}
