import Foundation

/// A saved surf break reduced to the three things spot-guessing needs.
///
/// Deliberately not `Spot`: this type is compiled into the watch app, and the
/// SwiftData model drags in the whole store. Callers on iOS map their `Spot`s
/// down to this at the call site, which keeps the matcher pure and testable
/// with no `ModelContainer`.
nonisolated struct SpotCandidate: Equatable, Sendable {
    let key: String
    let name: String
    let latitude: Double
    let longitude: Double

    init(key: String, name: String, latitude: Double, longitude: Double) {
        self.key = key
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Guesses which saved spot a workout happened at, from where its GPS route
/// started.
///
/// Used by the post-session nudge ("Log Saturday's 1 h 12 m session at
/// ~Trestles?"). The guess is always presented to the surfer for confirmation,
/// never applied silently — a wrong spot quietly attached to a session is worse
/// than no spot at all, because the surfer has no reason to go looking for it.
nonisolated enum NearestSpotMatcher {
    /// How far from a saved spot a route may start and still be called a match.
    ///
    /// 2 km is chosen to be generous about *where along a beach* the surfer
    /// paddled out (a saved pin sits at one peak; the same break can run for a
    /// mile) while still refusing to claim a neighbouring town's break. Beyond
    /// this the nudge offers no spot at all and the surfer picks one.
    static let defaultMaxDistanceMeters: Double = 2_000

    /// Mean Earth radius (metres), the same constant the tide and wave code uses.
    private static let earthRadiusMeters: Double = 6_371_000

    /// The closest candidate within `maxDistanceMeters`, or nil.
    ///
    /// Ties break on `key` so the same inputs always produce the same guess —
    /// two spots pinned at an identical coordinate must not make the nudge
    /// flicker between them across launches.
    static func nearest(
        toLatitude latitude: Double,
        longitude: Double,
        among candidates: [SpotCandidate],
        maxDistanceMeters: Double = defaultMaxDistanceMeters
    ) -> SpotCandidate? {
        guard latitude.isFinite, longitude.isFinite else { return nil }

        var best: (candidate: SpotCandidate, distance: Double)?
        for candidate in candidates {
            let distance = distanceMeters(
                fromLatitude: latitude,
                longitude: longitude,
                toLatitude: candidate.latitude,
                longitude: candidate.longitude
            )
            guard distance <= maxDistanceMeters else { continue }
            guard let current = best else {
                best = (candidate, distance)
                continue
            }
            if distance < current.distance ||
                (distance == current.distance && candidate.key < current.candidate.key) {
                best = (candidate, distance)
            }
        }
        return best?.candidate
    }

    /// Great-circle distance in metres.
    ///
    /// Returns `.infinity` for non-finite inputs so a corrupt coordinate can
    /// never win a nearest-match comparison.
    static func distanceMeters(
        fromLatitude lat1: Double,
        longitude lon1: Double,
        toLatitude lat2: Double,
        longitude lon2: Double
    ) -> Double {
        guard lat1.isFinite, lon1.isFinite, lat2.isFinite, lon2.isFinite else { return .infinity }

        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        // Wrap the longitude delta so a pair straddling the antimeridian is
        // measured the short way round, not most of the way across the planet.
        var deltaLonDegrees = lon2 - lon1
        if deltaLonDegrees > 180 { deltaLonDegrees -= 360 }
        if deltaLonDegrees < -180 { deltaLonDegrees += 360 }
        let deltaLambda = deltaLonDegrees * .pi / 180

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadiusMeters * c
    }
}
