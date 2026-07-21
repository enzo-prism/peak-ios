import Foundation
import SwiftData

/// Binds the user's logbook to `WindowScorer` for the Best Window Today card.
///
/// Stateless, like every other calculator in `Supporting/`. The SwiftData-touching
/// parts stay on the main actor because they walk already-loaded models; only the
/// network fetch and the ranking go off it.
enum TodayWindowService {

    /// Opt-in on-appear fetching. **Default off.**
    ///
    /// Peak does not make network calls the surfer did not ask for, and a card
    /// that silently phones a weather API every time the Log tab appears would
    /// break that promise no matter how useful it is. The surfer can turn it on
    /// in Settings; until then the card waits for "Check conditions".
    static let autoRefreshKey = "peak.window.autoRefreshOnAppear"

    /// How many favourite spots the card offers.
    ///
    /// Three: enough to cover a surfer with a home break, a swell-magnet backup
    /// and a wind refuge, few enough that the picker stays a glance rather than a
    /// menu — and few enough that turning them all over is at most three requests.
    static let favouriteSpotLimit = 3

    /// Hard ceiling on hours requested from the provider, matching
    /// `SurfConditionsService.fetchDayForecast`'s own cap. Reaching the end of
    /// tomorrow from late this evening is the widest span the card ever needs.
    static let maxForecastHours = 48

    /// Below this many whole hours left in the local day, the card stops calling
    /// the rest of today an answer and plans tomorrow instead.
    ///
    /// A window has to be long enough to drive to and surf. Three hours is the
    /// shortest span where "6:00 - 9:00 pm" is a plan rather than a countdown,
    /// and evening is exactly when a surfer is deciding about tomorrow anyway.
    /// The label always says which day it found — see `Recommendation.dayOffset`.
    static let minRemainingHoursToday = 3

    // MARK: Spot selection

    /// The spots this surfer actually surfs, most-logged first.
    ///
    /// Coordinates are deliberately **not** required. They used to be, on the
    /// reasoning that an unlocatable spot cannot be forecast — which is true, and
    /// which made the entire card vanish for anyone whose home break was created
    /// by import or typed by name (both produce a `Spot` with no coordinate). The
    /// card is now responsible for that case: it resolves the coordinate from the
    /// break catalog where it can and asks for a location where it cannot. Both
    /// are more useful than rendering nothing.
    ///
    /// Ties break on the most recent session, then on name, so the order is stable
    /// between launches rather than shuffling with dictionary iteration.
    static func favouriteSpots(sessions: [SurfSession], limit: Int = favouriteSpotLimit) -> [Spot] {
        guard limit > 0 else { return [] }

        var counts: [PersistentIdentifier: (spot: Spot, count: Int, latest: Date)] = [:]
        for session in sessions {
            guard let spot = session.spot else { continue }
            let id = spot.persistentModelID
            if let existing = counts[id] {
                counts[id] = (spot, existing.count + 1, max(existing.latest, session.date))
            } else {
                counts[id] = (spot, 1, session.date)
            }
        }

        return counts.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.latest != rhs.latest { return lhs.latest > rhs.latest }
                return lhs.spot.name.localizedCaseInsensitiveCompare(rhs.spot.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.spot)
    }

    // MARK: History

    /// The conditions the scorer should see for one session.
    ///
    /// The numeric fields are the auto-filled truth and always win. Where one is
    /// missing and the surfer answered the editor's coarse picker instead, the
    /// picker's band is converted to a representative number — see
    /// `ManualConditionEstimate` for the mapping and for why these values carry no
    /// extra penalty. This is a *fallback*, never an overwrite: a session that
    /// recorded a real 12.4 km/h keeps 12.4 km/h even if the picker says "windy".
    ///
    /// Without this, a logbook whose conditions were only ever described with the
    /// pickers produced zero usable sessions and therefore zero confidence, and
    /// the card asked for more of exactly the sessions it was throwing away.
    static func conditionsSample(for session: SurfSession) -> ConditionsSample {
        ConditionsSample(
            swellWaveHeightMeters: session.swellWaveHeightMeters,
            swellWavePeriodSeconds: session.swellWavePeriodSeconds,
            swellWaveDirectionDegrees: session.swellWaveDirectionDegrees,
            windWaveHeightMeters: session.windWaveHeightMeters,
            waveHeightMeters: session.waveHeightMeters
                ?? session.waveHeight.map(ManualConditionEstimate.waveHeightMeters(for:)),
            windSpeedKph: session.windSpeedKph
                ?? session.windCondition.map(ManualConditionEstimate.windSpeedKph(for:)),
            windDirectionDegrees: session.windDirectionDegrees,
            seaSurfaceTemperatureC: session.seaSurfaceTemperatureC,
            seaLevelHeightMeters: session.seaLevelHeightM,
            tideTrend: session.tide
        )
    }

    /// The rated sessions at one spot, in the scorer's own shape.
    ///
    /// Only sessions at *this* spot are included — feeding in a different break's
    /// history would defeat the entire premise, which is that the user's own
    /// results at this particular patch of water are the model of it.
    ///
    /// Unrated sessions (rating 0) are kept rather than dropped: "I paddled out
    /// and it was worth nothing" is real signal about these conditions, and the
    /// rating spread it creates is exactly what the confidence term needs.
    static func ratedHistory(sessions: [SurfSession], at spot: Spot) -> [RatedSession] {
        let spotID = spot.persistentModelID
        return sessions.compactMap { session in
            guard session.spot?.persistentModelID == spotID else { return nil }
            return RatedSession(
                date: session.date,
                rating: session.rating,
                conditions: conditionsSample(for: session),
                sessionID: session.persistentModelID
            )
        }
    }

    // MARK: Day planning

    /// Which calendar day the card is answering for, and the slice of it to score.
    ///
    /// The card used to score a rolling 24 hours from now and print the result as
    /// a bare time range under the heading "Best window today". At 6 pm that
    /// renders tomorrow's dawn as today's answer, which is simply false. A window
    /// now belongs to one local calendar day, and `dayOffset` makes the card say
    /// which.
    struct DayPlan: Sendable, Hashable {
        /// First instant to score. Never in the past.
        let from: Date
        /// Exclusive end: the start of the day after `from`'s day.
        let until: Date
        /// 0 = the rest of today, 1 = tomorrow. Never negative.
        let dayOffset: Int

        /// Hours of forecast to request so the provider covers `until`.
        ///
        /// Measured from the top of the current hour because that is where the
        /// provider's series starts, and clamped to the service's own cap.
        func hoursToRequest(from now: Date) -> Int {
            let span = until.timeIntervalSince(TodayWindowService.floorToHour(now)) / 3600
            guard span.isFinite else { return maxForecastHours }
            return max(1, min(maxForecastHours, Int(span.rounded(.up))))
        }
    }

    /// Top of the hour containing `date`.
    ///
    /// Mirrors `SurfConditionsService`'s own hour flooring, which is where the
    /// provider's series starts, so the hour count asked for really does reach
    /// the end of the planned day. Duplicated rather than shared because the
    /// service's copy is fileprivate and this is two lines of arithmetic.
    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate:
                (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
    }

    /// Picks the day to answer for. See `minRemainingHoursToday`.
    static func dayPlan(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> DayPlan {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)
            ?? todayStart.addingTimeInterval(86_400)
        let dayAfterStart = calendar.date(byAdding: .day, value: 2, to: todayStart)
            ?? tomorrowStart.addingTimeInterval(86_400)

        let hoursLeftToday = tomorrowStart.timeIntervalSince(now) / 3600
        if hoursLeftToday >= Double(minRemainingHoursToday) {
            return DayPlan(from: now, until: tomorrowStart, dayOffset: 0)
        }
        return DayPlan(from: tomorrowStart, until: dayAfterStart, dayOffset: 1)
    }

    // MARK: Presentation

    /// What the card renders. Deliberately a value type with no model references,
    /// so it can be produced off the main actor and handed back whole.
    struct Recommendation: Sendable, Hashable {
        let start: Date
        let end: Date
        let predictedRating: Double
        let confidence: Double
        /// e.g. ["1.2 m swell", "12 s period", "wind from NE"].
        let factors: [String]
        let matchDate: Date?
        let matchRating: Int?
        let matchSessionID: PersistentIdentifier?
        /// 0 = today, 1 = tomorrow, 2+ = later. Drives the label and the heading:
        /// a window that is not today must never be presented as one.
        let dayOffset: Int

        init(window: ScoredWindow, dayOffset: Int) {
            self.start = window.start
            self.end = window.end
            self.predictedRating = window.predictedRating
            self.confidence = window.confidence
            self.factors = window.matchFactors
            self.matchDate = window.bestMatch?.date
            self.matchRating = window.bestMatch?.rating
            self.matchSessionID = window.bestMatch?.sessionID
            self.dayOffset = max(0, dayOffset)
        }

        /// "6:00 - 9:00 AM", or "Tomorrow 5:00 - 10:00 AM" when the window is not
        /// today. Uses a time range so it reads as a window, not an instant, and
        /// never prints a bare time for a day that is not the one on screen.
        func timeRangeLabel(locale: Locale = .autoupdatingCurrent) -> String {
            let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
            let range = "\(start.formatted(style)) - \(end.formatted(style))"
            switch dayOffset {
            case 0:
                return range
            case 1:
                return "Tomorrow \(range)"
            default:
                let day = start.formatted(
                    .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale)
                )
                return "\(day), \(range)"
            }
        }

        /// "1.2 m @ 12 s, wind from NE, dropping tide" — whatever the scorer could
        /// honestly justify, joined. Never padded out with invented detail.
        var factorSummary: String {
            factors.joined(separator: ", ")
        }
    }

    /// The forecast conditions themselves, with no claim attached.
    ///
    /// Shown when the history cannot support a recommendation, which for most
    /// surfers is most of the time. It is a plain report of what the provider says
    /// the water is doing — clearly labelled as such — and it makes the card
    /// useful on day one instead of being a permanent apology.
    struct Conditions: Sendable, Hashable {
        let date: Date
        let waveHeightMeters: Double?
        let swellPeriodSeconds: Double?
        let windSpeedKph: Double?
        let windDirectionDegrees: Double?
        let seaLevelHeightMeters: Double?
        let tideTrend: TideTrend?

        init(hour: ForecastHour) {
            let c = hour.conditions
            self.date = hour.date
            self.waveHeightMeters = c.waveHeightMeters ?? c.swellWaveHeightMeters
            self.swellPeriodSeconds = c.swellWavePeriodSeconds
            self.windSpeedKph = c.windSpeedKph
            self.windDirectionDegrees = c.windDirectionDegrees
            self.seaLevelHeightMeters = c.seaLevelHeightMeters
            self.tideTrend = c.tideTrend
        }

        var hasAnyReading: Bool {
            waveHeightMeters != nil || swellPeriodSeconds != nil || windSpeedKph != nil
                || seaLevelHeightMeters != nil || tideTrend != nil
        }

        /// "1.4 m · 12 s · 14 km/h from NE · falling tide", in the surfer's units.
        func summary(locale: Locale = .autoupdatingCurrent) -> String {
            var parts: [String] = []
            if let waveHeightMeters {
                parts.append(SurfConditionsFormatter.meters(waveHeightMeters, locale: locale))
            }
            if let swellPeriodSeconds {
                parts.append(SurfConditionsFormatter.period(swellPeriodSeconds))
            }
            if let windSpeedKph {
                let speed = SurfConditionsFormatter.speed(windSpeedKph, locale: locale)
                if let windDirectionDegrees {
                    parts.append("\(speed) from \(SurfConditionsFormatter.direction(windDirectionDegrees))")
                } else {
                    parts.append("\(speed) wind")
                }
            }
            if let tide = SurfConditionsFormatter.tide(
                trend: tideTrend, seaLevelMeters: seaLevelHeightMeters, locale: locale
            ) {
                parts.append(tide)
            }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    /// One fetch's worth of answer.
    ///
    /// `recommendation` is nil whenever nothing cleared the confidence gate, which
    /// is the honest outcome for a thin logbook and is not an error.
    /// `conditions` is present whenever the provider returned anything at all, so
    /// the card has something true to show either way.
    struct Outlook: Sendable, Hashable {
        /// The spot this answer was computed for.
        ///
        /// Carried on the value itself, not tracked beside it in view state, so
        /// that a result which arrives after the surfer has switched spots can be
        /// recognised as stale by looking at the result. Switching spots used to
        /// leave the in-flight fetch running and its answer was rendered — cited
        /// session and all — under whichever break happened to be selected when it
        /// landed.
        var spotID: PersistentIdentifier?
        var recommendation: Recommendation?
        var conditions: Conditions?
        /// The day that was scored: 0 = today, 1 = tomorrow.
        var dayOffset: Int
    }

    /// Whether an outlook may be shown for `spot`.
    ///
    /// The whole race fix, in one place so it can be tested rather than only
    /// inspected: an answer is displayable only against the spot it was asked
    /// about, and never when nothing is selected.
    static func accepts(_ outlook: Outlook, for spot: Spot?) -> Bool {
        guard let spot, let spotID = outlook.spotID else { return false }
        return spotID == spot.persistentModelID
    }

    /// Fetches and ranks the remainder of the planned day.
    ///
    /// The ranking hop is the important one: at a few hundred sessions `rank`
    /// costs well over a frame, so it goes through `rankOffMain`.
    ///
    /// Returns an `Outlook` rather than an optional recommendation, because
    /// "nothing clears the gate" and "nothing to say" are different answers. The
    /// former still carries the day's conditions.
    static func outlook(
        history: [RatedSession],
        spotID: PersistentIdentifier?,
        latitude: Double,
        longitude: Double,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        session: URLSession = .shared
    ) async throws -> Outlook {
        let plan = dayPlan(now: now, calendar: calendar)
        let forecast = try await SurfConditionsService.fetchDayForecast(
            latitude: latitude,
            longitude: longitude,
            start: now,
            hours: plan.hoursToRequest(from: now),
            session: session
        )

        // Only the planned day is scored. An hour of tomorrow morning is not an
        // answer to "when today?", and a rolling 24 hours quietly made it one.
        let hours = forecast
            .filter { $0.date >= plan.from && $0.date < plan.until }
            .sorted { $0.date < $1.date }

        let windows = await WindowScorer.rankOffMain(forecast: hours, history: history)
        let conditions = (hours.first ?? forecast.first).map(Conditions.init(hour:))

        return Outlook(
            spotID: spotID,
            recommendation: windows.first.map { Recommendation(window: $0, dayOffset: plan.dayOffset) },
            conditions: conditions.flatMap { $0.hasAnyReading ? $0 : nil },
            dayOffset: plan.dayOffset
        )
    }
}
