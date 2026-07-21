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

    /// Hours ahead to score. A day, because the card answers "when today?".
    static let forecastHours = 24

    // MARK: Spot selection

    /// The spots this surfer actually surfs, most-logged first.
    ///
    /// Coordinates are required, not preferred: without them there is no forecast
    /// to fetch, so a spot that cannot be located simply is not a candidate. Ties
    /// break on the most recent session, then on name, so the order is stable
    /// between launches rather than shuffling with dictionary iteration.
    static func favouriteSpots(sessions: [SurfSession], limit: Int = favouriteSpotLimit) -> [Spot] {
        guard limit > 0 else { return [] }

        var counts: [PersistentIdentifier: (spot: Spot, count: Int, latest: Date)] = [:]
        for session in sessions {
            guard let spot = session.spot, spot.latitude != nil, spot.longitude != nil else { continue }
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
                conditions: ConditionsSample(
                    swellWaveHeightMeters: session.swellWaveHeightMeters,
                    swellWavePeriodSeconds: session.swellWavePeriodSeconds,
                    swellWaveDirectionDegrees: session.swellWaveDirectionDegrees,
                    windWaveHeightMeters: session.windWaveHeightMeters,
                    waveHeightMeters: session.waveHeightMeters,
                    windSpeedKph: session.windSpeedKph,
                    windDirectionDegrees: session.windDirectionDegrees,
                    seaSurfaceTemperatureC: session.seaSurfaceTemperatureC,
                    seaLevelHeightMeters: session.seaLevelHeightM,
                    tideTrend: session.tide
                ),
                sessionID: session.persistentModelID
            )
        }
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

        init(window: ScoredWindow) {
            self.start = window.start
            self.end = window.end
            self.predictedRating = window.predictedRating
            self.confidence = window.confidence
            self.factors = window.matchFactors
            self.matchDate = window.bestMatch?.date
            self.matchRating = window.bestMatch?.rating
            self.matchSessionID = window.bestMatch?.sessionID
        }

        /// "6-9 am". Uses a time range so it reads as a window, not an instant.
        func timeRangeLabel(locale: Locale = .autoupdatingCurrent) -> String {
            let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
            return "\(start.formatted(style)) - \(end.formatted(style))"
        }

        /// "1.2 m @ 12 s, wind from NE, dropping tide" — whatever the scorer could
        /// honestly justify, joined. Never padded out with invented detail.
        var factorSummary: String {
            factors.joined(separator: ", ")
        }
    }

    /// Fetches and ranks. The ranking hop is the important one: at a few hundred
    /// sessions `rank` costs well over a frame, so it goes through `rankOffMain`.
    ///
    /// Returns `nil` when the day produces nothing worth recommending — a thin
    /// logbook, an unremarkable day, or conditions unlike anything logged here.
    /// That is a real answer and the card says so rather than inventing one.
    static func bestWindow(
        history: [RatedSession],
        latitude: Double,
        longitude: Double,
        now: Date = Date(),
        session: URLSession = .shared
    ) async throws -> Recommendation? {
        let forecast = try await SurfConditionsService.fetchDayForecast(
            latitude: latitude,
            longitude: longitude,
            start: now,
            hours: forecastHours,
            session: session
        )
        let windows = await WindowScorer.rankOffMain(forecast: forecast, history: history)
        return windows.first.map(Recommendation.init(window:))
    }
}
