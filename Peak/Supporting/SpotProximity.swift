import Foundation

/// Nearest saved surf break to a coordinate, used when an imported Watch
/// workout has a route start but Peak has not asked the surfer which spot it
/// was. Pure Foundation so tests never touch CoreLocation.
///
/// Spots without a pin are ignored — guessing from a name-only row would be
/// fabrication. Beyond `maxGuessDistanceMeters` we return nil rather than
/// assigning a distant break as if it were fact.
enum SpotProximity {
    /// Beach-scale: far enough to cover a long point-break walk, tight enough
    /// that a session at Blacks cannot adopt Windansea as the guess.
    static let maxGuessDistanceMeters: Double = 2_500

    struct LocatedSpot: Equatable {
        var key: String
        var latitude: Double
        var longitude: Double
    }

    static func nearestKey(
        latitude: Double,
        longitude: Double,
        among spots: [LocatedSpot],
        maxDistanceMeters: Double = maxGuessDistanceMeters
    ) -> String? {
        guard latitude.isFinite, longitude.isFinite, !spots.isEmpty else { return nil }
        var bestKey: String?
        var bestDistance = maxDistanceMeters
        for spot in spots {
            guard spot.latitude.isFinite, spot.longitude.isFinite else { continue }
            let distance = WaveAnalyzer.haversineMeters(
                lat1: latitude,
                lon1: longitude,
                lat2: spot.latitude,
                lon2: spot.longitude
            )
            if distance < bestDistance {
                bestDistance = distance
                bestKey = spot.key
            }
        }
        return bestKey
    }

    static func nearest(
        to sample: RouteSample?,
        in spots: [Spot]
    ) -> Spot? {
        guard let sample else { return nil }
        let located = spots.compactMap { spot -> LocatedSpot? in
            guard let latitude = spot.latitude, let longitude = spot.longitude else { return nil }
            return LocatedSpot(key: spot.key, latitude: latitude, longitude: longitude)
        }
        guard let key = nearestKey(
            latitude: sample.latitude,
            longitude: sample.longitude,
            among: located
        ) else { return nil }
        return spots.first { $0.key == key }
    }

    /// Watch GPS often starts in a parking lot (`samples.first`). Invalid fixes
    /// (`horizontalAccuracyMeters < 0`) are skipped; the mid-route valid sample
    /// is the break, not the walk.
    static func guessSample(from samples: [RouteSample]) -> RouteSample? {
        let valid = samples.filter { sample in
            sample.latitude.isFinite
                && sample.longitude.isFinite
                && sample.horizontalAccuracyMeters >= 0
        }
        guard !valid.isEmpty else { return nil }
        return valid[valid.count / 2]
    }

    static func nearest(to samples: [RouteSample], in spots: [Spot]) -> Spot? {
        nearest(to: guessSample(from: samples), in: spots)
    }
}
