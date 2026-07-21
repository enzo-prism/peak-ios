import Foundation

/// Station-accurate tide predictions from NOAA CO-OPS, for US spots only.
///
/// **This is a bonus layer, never a requirement.** Open-Meteo's modelled sea
/// level already gives every spot on earth a rising/falling curve; NOAA adds real
/// harmonic high/low predictions for water the US actually gauges. So every
/// failure path here — no station nearby, station list unreachable, malformed
/// response, spot in Portugal — resolves to `nil` and the caller silently keeps
/// the Open-Meteo curve. Being outside the United States is not an error and must
/// never be presented as one.
///
/// Free, no API key, no account. `application` is sent as a courtesy identifier
/// because NOAA asks callers to identify themselves; it carries no user data.
nonisolated enum TideService {
    static let sourceName = "NOAA CO-OPS"
    private static let host = "api.tidesandcurrents.noaa.gov"
    private static let applicationName = "PeakSurfLog"

    /// Past this, the "nearest" station is no longer describing this spot's water.
    ///
    /// 120 km is chosen to be generous along the well-gauged US coasts (where
    /// stations are typically 20-60 km apart) while firmly excluding the case this
    /// exists to exclude: a spot in Baja or Nova Scotia silently adopting a distant
    /// American gauge and reporting its tides as fact. A surfer in Portugal gets
    /// no station, and that is the correct answer.
    static let maxStationDistanceKm: Double = 120

    struct Station: Sendable, Hashable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
    }

    /// One predicted turning point of the tide.
    struct TideExtreme: Sendable, Hashable {
        let date: Date
        let heightMeters: Double
        let isHigh: Bool
    }

    // MARK: Station resolution

    /// Returns the station id to use for a spot, doing no network work at all when
    /// one is already cached.
    ///
    /// The cache lives on `Spot.tideStationId` (schema V9). Resolving is a download
    /// of NOAA's entire station directory, so it must happen at most once per spot
    /// — hence the cached-first short circuit, which is the behaviour worth being
    /// certain about and is asserted directly in the tests.
    ///
    /// Never throws: a spot with no usable station is an ordinary outcome.
    static func resolveStationId(
        cached: String?,
        latitude: Double,
        longitude: Double,
        session: URLSession = .shared
    ) async -> String? {
        if let cached = cached?.trimmedNonEmpty {
            return cached
        }
        return try? await nearestStation(
            latitude: latitude, longitude: longitude, session: session
        )?.id
    }

    /// Downloads the tide-prediction station directory and picks the closest one
    /// within `maxStationDistanceKm`. `nil` means "no station covers this spot".
    @concurrent
    static func nearestStation(
        latitude: Double,
        longitude: Double,
        session: URLSession = .shared
    ) async throws -> Station? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        let url = try makeStationsURL()
        let data = try await fetchData(url: url, session: session)
        let stations = try parseStations(data)
        return nearestStation(in: stations, latitude: latitude, longitude: longitude)?.station
    }

    /// Pure selection step, split out so the distance cut-off is testable without
    /// a network round trip.
    static func nearestStation(
        in stations: [Station],
        latitude: Double,
        longitude: Double
    ) -> (station: Station, distanceKm: Double)? {
        guard latitude.isFinite, longitude.isFinite else { return nil }

        var best: (station: Station, distanceKm: Double)?
        for station in stations {
            let distance = distanceKm(
                fromLatitude: latitude, longitude: longitude,
                toLatitude: station.latitude, longitude: station.longitude
            )
            guard distance.isFinite else { continue }
            // Ties break on station id so the choice is stable across runs and
            // across NOAA reordering its directory.
            if let current = best {
                if distance < current.distanceKm
                    || (distance == current.distanceKm && station.id < current.station.id) {
                    best = (station, distance)
                }
            } else {
                best = (station, distance)
            }
        }

        guard let best, best.distanceKm <= maxStationDistanceKm else { return nil }
        return best
    }

    // MARK: Predictions

    /// High and low water predictions for a station over a date range.
    @concurrent
    static func predictions(
        stationId: String,
        start: Date,
        end: Date,
        session: URLSession = .shared
    ) async throws -> [TideExtreme] {
        let url = try makePredictionsURL(stationId: stationId, start: start, end: end)
        let data = try await fetchData(url: url, session: session)
        return try parsePredictions(data)
    }

    // MARK: Parsing

    static func parseStations(_ data: Data) throws -> [Station] {
        if let reason = decodeRemoteError(from: data) {
            throw TideServiceError.remoteError(reason)
        }
        guard let response = try? JSONDecoder().decode(StationsResponse.self, from: data) else {
            throw TideServiceError.decodingFailed
        }
        return response.stations.compactMap { raw in
            guard let id = raw.id?.trimmedNonEmpty,
                  let latitude = raw.lat, let longitude = raw.lng,
                  latitude.isFinite, longitude.isFinite else { return nil }
            return Station(
                id: id,
                name: raw.name?.trimmedNonEmpty ?? id,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    static func parsePredictions(_ data: Data) throws -> [TideExtreme] {
        if let reason = decodeRemoteError(from: data) {
            throw TideServiceError.remoteError(reason)
        }
        guard let response = try? JSONDecoder().decode(PredictionsResponse.self, from: data) else {
            throw TideServiceError.decodingFailed
        }
        return response.predictions.compactMap { raw in
            // NOAA sends heights as strings, and its "type" is "H" or "L". Rows
            // that are neither are skipped rather than coerced — an unexpected
            // marker is not something to guess about.
            guard let date = predictionTimeFormatter.date(from: raw.t),
                  let height = Double(raw.v), height.isFinite else { return nil }
            switch raw.type.uppercased() {
            case "H": return TideExtreme(date: date, heightMeters: height, isHigh: true)
            case "L": return TideExtreme(date: date, heightMeters: height, isHigh: false)
            default: return nil
            }
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: URLs

    static func makeStationsURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/mdapi/prod/webapi/stations.json"
        components.queryItems = [
            URLQueryItem(name: "type", value: "tidepredictions"),
            URLQueryItem(name: "application", value: applicationName)
        ]
        guard let url = components.url else { throw TideServiceError.invalidURL }
        return url
    }

    static func makePredictionsURL(stationId: String, start: Date, end: Date) throws -> URL {
        guard let station = stationId.trimmedNonEmpty else { throw TideServiceError.invalidURL }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/prod/datagetter"
        components.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: applicationName),
            URLQueryItem(name: "station", value: station),
            URLQueryItem(name: "begin_date", value: dayFormatter.string(from: min(start, end))),
            URLQueryItem(name: "end_date", value: dayFormatter.string(from: max(start, end))),
            // MLLW is the US chart datum: this is the one place in Peak where a tide
            // height IS datum-referenced and may honestly be quoted as such.
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "interval", value: "hilo"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw TideServiceError.invalidURL }
        return url
    }

    // MARK: Geometry

    /// Great-circle distance in kilometres (haversine). Good to a fraction of a
    /// percent at these ranges, which is far tighter than the 120 km cut needs.
    static func distanceKm(
        fromLatitude lat1: Double, longitude lon1: Double,
        toLatitude lat2: Double, longitude lon2: Double
    ) -> Double {
        guard lat1.isFinite, lon1.isFinite, lat2.isFinite, lon2.isFinite else { return .infinity }
        let earthRadiusKm = 6371.0
        let toRadians = Double.pi / 180
        let dLat = (lat2 - lat1) * toRadians
        // Longitude difference is wrapped so a spot at -179 and a station at +179
        // read as 2 degrees apart, not 358.
        var dLon = (lon2 - lon1).truncatingRemainder(dividingBy: 360)
        if dLon > 180 { dLon -= 360 }
        if dLon < -180 { dLon += 360 }
        dLon *= toRadians

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * toRadians) * cos(lat2 * toRadians) * sin(dLon / 2) * sin(dLon / 2)
        let clamped = min(1, max(0, a))
        return 2 * earthRadiusKm * atan2(clamped.squareRoot(), (1 - clamped).squareRoot())
    }

    // MARK: Networking

    @concurrent
    private static func fetchData(url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let reason = decodeRemoteError(from: data) {
                throw TideServiceError.remoteError(reason)
            }
            throw TideServiceError.invalidResponse
        }
        return data
    }

    private static func decodeRemoteError(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
              let message = response.error?.message?.trimmedNonEmpty else {
            return nil
        }
        return message
    }

    // Stored constants, not computed: a computed `var` would re-allocate a
    // DateFormatter for every prediction row parsed.
    private static let predictionTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

enum TideServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the tide request."
        case .invalidResponse:
            return "Tide service is unavailable."
        case .decodingFailed:
            return "Tide data could not be read."
        case .remoteError(let reason):
            return "Tide service error: \(reason)"
        }
    }
}

private nonisolated struct StationsResponse: Decodable, Sendable {
    let stations: [RawStation]

    struct RawStation: Decodable, Sendable {
        let id: String?
        let name: String?
        let lat: Double?
        let lng: Double?
    }
}

private nonisolated struct PredictionsResponse: Decodable, Sendable {
    let predictions: [RawPrediction]

    struct RawPrediction: Decodable, Sendable {
        let t: String
        let v: String
        let type: String
    }
}

private nonisolated struct ErrorResponse: Decodable, Sendable {
    let error: Payload?

    struct Payload: Decodable, Sendable {
        let message: String?
    }
}
