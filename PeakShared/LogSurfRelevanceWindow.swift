import Foundation

/// When "Log your surf" is worth promoting in the watch Smart Stack on time of
/// day alone.
///
/// Lives in shared code purely so it is testable: the watch widget extension is
/// not a unit-test host, and this is the one piece of the relevance logic that
/// is pure enough to pin down in CI. The location half of relevance depends on
/// HealthKit route history and is not simulable here.
nonisolated enum LogSurfRelevanceWindow {
    static let startHour = 5
    static let endHour = 9

    /// The next 05:00–09:00 local window.
    ///
    /// Static hours rather than real sunrise: the watch widget has no location
    /// permission of its own to compute sunrise from, and being an hour off on a
    /// relevance hint is harmless in a way that asking for location would not be.
    static func dawnPatrolWindow(
        from date: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date) else {
            return nil
        }
        // Past this morning's window, point at tomorrow's rather than a window
        // that has already closed — a relevance hint in the past is ignored.
        guard date < end else {
            guard let nextStart = calendar.date(byAdding: .day, value: 1, to: start),
                  let nextEnd = calendar.date(byAdding: .day, value: 1, to: end) else {
                return nil
            }
            return DateInterval(start: nextStart, end: nextEnd)
        }
        return DateInterval(start: start, end: end)
    }
}
