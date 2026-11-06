import Foundation

/// Exact questions use the whole candidate set, never a top-k semantic result.
/// This intentionally bounded grammar is also the offline/non-AI fallback.
enum LogbookQuery {
    enum Operation { case find, count, boardUsage }
    struct Answer {
        let title: String
        let explanation: String
        let sessions: [SurfSession]
    }

    static func answer(_ question: String, sessions: [SurfSession], now: Date = Date(),
                       calendar: Calendar = .current) -> Answer {
        let query = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard query.trimmedNonEmpty != nil else {
            return Answer(title: "Ask about your surfing", explanation: "Try “How many sessions this month?” or “Which board did I use most?”", sessions: [])
        }
        let unsupported = ["not ", "without ", "except ", "before ", "after ", "waves", "fastest", "longest", "last week", "yesterday", "last year", "hours"]
        if unsupported.contains(where: { query.contains($0) }) || query.range(of: "\\b[0-9]{4}\\b", options: .regularExpression) != nil {
            return Answer(title: "That question needs a filter", explanation: "I can count sessions, compare board usage, and find saved spots, boards or clean/crowded/windy notes for this month, last month or this year. Use History filters for other date ranges.", sessions: [])
        }
        let operation: Operation = query.contains("how many") || query.contains("count") ? .count
            : (query.contains("which board") || query.contains("most used board")) ? .boardUsage : .find
        var matches = sessions
        if query.contains("this month"), let interval = calendar.dateInterval(of: .month, for: now) {
            matches = matches.filter { interval.contains($0.date) && $0.date < interval.end }
        } else if query.contains("last month"),
                  let previous = calendar.date(byAdding: .month, value: -1, to: now),
                  let interval = calendar.dateInterval(of: .month, for: previous) {
            matches = matches.filter { $0.date >= interval.start && $0.date < interval.end }
        } else if query.contains("this year"), let interval = calendar.dateInterval(of: .year, for: now) {
            matches = matches.filter { $0.date >= interval.start && $0.date < interval.end }
        }
        let spotNames = Set(sessions.compactMap { $0.spot?.name })
        let spotMatches = spotNames.filter { containsName($0, in: query) }
        if (query.contains(" at ") || query.contains(" in ")) && spotMatches.isEmpty
            && !query.contains(" in peak") && !query.contains(" in my ") && !query.contains(" in the ") {
            return Answer(title: "Choose a saved spot", explanation: "Use the exact name of a spot in your library so an unknown place never becomes an unfiltered count.", sessions: [])
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
        for scope in ["this month", "last month", "this year"] { remainder = remainder.replacingOccurrences(of: scope, with: " ") }
        let allowed = Set("how many count session sessions surfs surf surfing did do have had i my me log logged show find search for most used use which board boards with at in on the a an all clean crowded windy morning afternoon peak notes and".split(separator: " ").map(String.init))
        let words = remainder.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if operation != .find || !spotMatches.isEmpty || !namedBoards.isEmpty ||
            ["morning", "afternoon", "clean", "crowded", "windy", "this month", "last month", "this year"].contains(where: query.contains) {
            guard words.allSatisfy(allowed.contains) else {
                return Answer(title: "That question needs a filter", explanation: "I could not apply every condition in this question. Use a saved spot or board name, this month/last month/this year, morning/afternoon, or clean/crowded/windy notes. No partial count is shown.", sessions: [])
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
                || ["morning", "afternoon", "this month", "last month", "this year", "all sessions"].contains { query.contains($0) }
            guard recognized else {
                // A literal free-text search has a truthful fallback; do not
                // answer arbitrary questions with the whole logbook.
                let literal = sessions.filter { $0.notes.localizedCaseInsensitiveContains(question) }
                return Answer(title: literal.isEmpty ? "Try a more specific question" : "Matching notes",
                              explanation: "Search a saved spot or board name, clean/crowded/windy notes, or a month. Peak only answers from logged records.", sessions: literal)
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
