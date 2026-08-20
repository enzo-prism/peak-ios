import Foundation

/// A session from a previous year, resurfaced near its anniversary.
struct OnThisDayMemory: Identifiable {
    let session: SurfSession
    let yearsAgo: Int
    /// True when the session fell on the exact calendar day rather than merely
    /// inside the window — the difference between "today" and "this week".
    let isExactAnniversary: Bool

    /// Object identity rather than `persistentModelID`: the provider is pure and
    /// must work on sessions that were never inserted into a context.
    var id: ObjectIdentifier { ObjectIdentifier(session) }

    var label: String {
        let years = yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago"
        return isExactAnniversary ? "\(years) today" : "\(years) this week"
    }
}

/// Resurfaces past sessions around their anniversary. Pure query over the
/// existing logbook — no schema change, nothing cached.
enum OnThisDayProvider {
    /// ±3 days: wide enough that a Saturday session still lands on the
    /// anniversary weekend, narrow enough that the memory still feels like
    /// *this* day rather than "sometime that month".
    static let windowDays = 3

    static func memories(
        sessions: [SurfSession],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        windowDays: Int = windowDays,
        limit: Int = 3
    ) -> [OnThisDayMemory] {
        guard !sessions.isEmpty, windowDays >= 0, limit > 0 else { return [] }

        let today = calendar.startOfDay(for: referenceDate)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today),
              let lastDay = calendar.date(byAdding: .day, value: windowDays, to: today),
              // Half-open upper bound so the final day counts in full.
              let windowEnd = calendar.date(byAdding: .day, value: 1, to: lastDay),
              let earliest = sessions.min(by: { $0.date < $1.date })?.date
        else { return [] }

        // Walk the *window* back a year at a time instead of projecting each
        // session forward onto this year. A Feb 29 session has no anniversary in
        // a common year, and a window straddling New Year would otherwise have to
        // be stitched together from two calendar years.
        let yearSpan = calendar.dateComponents([.year], from: earliest, to: referenceDate).year ?? 0
        let maxYearsBack = max(yearSpan, 0) + 1

        // Closest years always rank first, so once a closer year has filled
        // `limit` we can stop — Log only asks for 1. Previously every year
        // rescanned the whole array (O(years × sessions)).
        var memories: [OnThisDayMemory] = []
        memories.reserveCapacity(min(limit, sessions.count))
        for yearsAgo in 1...maxYearsBack {
            guard let start = calendar.date(byAdding: .year, value: -yearsAgo, to: windowStart),
                  let end = calendar.date(byAdding: .year, value: -yearsAgo, to: windowEnd),
                  let anniversary = calendar.date(byAdding: .year, value: -yearsAgo, to: today)
            else { continue }

            var yearMatches: [OnThisDayMemory] = []
            for session in sessions where session.date >= start && session.date < end {
                yearMatches.append(OnThisDayMemory(
                    session: session,
                    yearsAgo: yearsAgo,
                    isExactAnniversary: calendar.isDate(session.date, inSameDayAs: anniversary)
                ))
            }
            guard !yearMatches.isEmpty else { continue }

            yearMatches.sort(by: Self.ranksHigher)
            memories.append(contentsOf: yearMatches)
            if memories.count >= limit { break }
        }

        if memories.count > limit {
            memories.removeLast(memories.count - limit)
        }
        return memories
    }

    /// Same intra-year order the previous global sort used: photo, then rating,
    /// then recency. Across years the walk already emits closest first.
    private static func ranksHigher(_ lhs: OnThisDayMemory, _ rhs: OnThisDayMemory) -> Bool {
        let lhsHasMedia = !lhs.session.media.isEmpty
        let rhsHasMedia = !rhs.session.media.isEmpty
        if lhsHasMedia != rhsHasMedia {
            return lhsHasMedia
        }
        if lhs.session.rating != rhs.session.rating {
            return lhs.session.rating > rhs.session.rating
        }
        return lhs.session.date > rhs.session.date
    }
}
