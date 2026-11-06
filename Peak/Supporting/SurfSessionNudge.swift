import Foundation

/// A "we noticed you surfed — want to log it?" prompt, ready to render.
///
/// Built from a surf workout that appeared in HealthKit (usually from the Peak
/// watch app, but any source works — the native Workout app, Dawn Patrol,
/// anything that writes `.surfingSports`). The surfer always confirms before a
/// session is created: the spot here is a *guess* from GPS, and silently
/// writing a wrong spot into someone's logbook is worse than not offering.
/// Note: deliberately *not* `nonisolated`. Unlike the types in `PeakShared/`,
/// this is iOS-only — it builds user-facing copy out of `SessionDurationFormatter`,
/// which is main-actor isolated like the rest of the app. Marking it nonisolated
/// would only buy a cross-actor call warning for no benefit.
struct SurfSessionNudge: Equatable, Identifiable {
    /// Stable across relaunches so the same workout is never offered twice.
    let id: String
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
    /// `Spot.key` of the guessed spot, when one was close enough.
    let spotKey: String?
    let spotName: String?
    /// The prompt itself, e.g. "Log Saturday's 1h 12m session at Trestles?"
    let message: String
}

/// Builds the nudge. Pure and stateless so the copy, the day naming and the
/// duration rounding are all unit-testable without HealthKit or a store.
enum SurfSessionNudgeBuilder {
    /// Workouts older than this are not worth interrupting anyone about — if it
    /// has been a fortnight, the surfer has moved on and the prompt reads as
    /// nagging rather than helpful.
    static let maximumAgeDays = 14

    /// Below this a "session" is almost certainly a mis-tap on the watch.
    static let minimumDurationMinutes = 10

    /// Builds a nudge, or nil when this workout should not raise one.
    ///
    /// `spots` is the current spot library reduced to coordinates; pass an empty
    /// array and the nudge simply arrives without a spot guess.
    static func make(
        workoutID: UUID,
        startDate: Date,
        endDate: Date,
        routeStartLatitude: Double?,
        routeStartLongitude: Double?,
        spots: [SpotCandidate],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SurfSessionNudge? {
        let elapsed = endDate.timeIntervalSince(startDate)
        guard elapsed.isFinite, elapsed > 0, elapsed / 60 < Double(Int.max),
              startDate.timeIntervalSince1970.isFinite, endDate <= now else { return nil }
        let rawMinutes = Int((elapsed / 60).rounded())
        guard rawMinutes >= minimumDurationMinutes else { return nil }

        let ageDays = calendar.dateComponents([.day], from: startDate, to: now).day ?? 0
        guard ageDays <= maximumAgeDays, startDate <= now else { return nil }

        let duration = SurfSession.normalizedDuration(rawMinutes) ?? rawMinutes

        var spot: SpotCandidate?
        if let latitude = routeStartLatitude, let longitude = routeStartLongitude {
            spot = NearestSpotMatcher.nearest(
                toLatitude: latitude,
                longitude: longitude,
                among: spots
            )
        }

        return SurfSessionNudge(
            id: workoutID.uuidString,
            startDate: startDate,
            endDate: endDate,
            durationMinutes: duration,
            spotKey: spot?.key,
            spotName: spot?.name,
            message: message(
                startDate: startDate,
                durationMinutes: duration,
                spotName: spot?.name,
                now: now,
                calendar: calendar
            )
        )
    }

    /// "Log Saturday's 1h 12m session at Trestles?"
    ///
    /// Uses a weekday name only while it is still unambiguous — past six days
    /// "Saturday" could mean either of two Saturdays, so it switches to a date.
    static func message(
        startDate: Date,
        durationMinutes: Int,
        spotName: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let duration = SessionDurationFormatter.string(from: durationMinutes)
        let day = dayReference(for: startDate, now: now, calendar: calendar)
        let place = spotName.map { " at \($0)" } ?? ""
        return "Log \(day) \(duration) session\(place)?"
    }

    /// "today's" / "yesterday's" / "Saturday's" / "Mar 12's".
    ///
    /// Everything is measured against the passed-in `now` rather than
    /// `Calendar.isDateInToday(_:)`, which silently consults the system clock.
    /// That distinction matters twice over: it is what makes this testable, and
    /// it is what stops the copy saying "today's" for a session that HealthKit
    /// delivered late and is actually from yesterday.
    static func dayReference(for date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ..<1:
            return "today's"
        case 1:
            return "yesterday's"
        case 2...6:
            // Still unambiguous — past six days "Saturday" could mean either of
            // two Saturdays, so the date takes over below.
            return "\(date.formatted(.dateTime.weekday(.wide)))'s"
        default:
            return "\(date.formatted(.dateTime.month(.abbreviated).day()))'s"
        }
    }
}
