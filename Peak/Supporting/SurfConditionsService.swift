import Foundation

struct SurfConditionsSnapshot: Sendable {
    let source: String
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double
    let windSpeedKph: Double?
    let windDirectionDegrees: Double?
    let waveHeightMeters: Double?
    let swellWaveHeightMeters: Double?
    let swellWavePeriodSeconds: Double?
    let swellWaveDirectionDegrees: Double?
    let windWaveHeightMeters: Double?
    let windWavePeriodSeconds: Double?
    let windWaveDirectionDegrees: Double?
    let seaSurfaceTemperatureC: Double?

    var windCondition: WindCondition? {
        SurfConditionsMapping.windCondition(for: windSpeedKph)
    }

    var waveHeightCategory: WaveHeight? {
        SurfConditionsMapping.waveHeightCategory(for: waveHeightMeters)
    }

    var hasWindReadings: Bool {
        windSpeedKph != nil || windDirectionDegrees != nil
    }

    var hasWaveReadings: Bool {
        waveHeightMeters != nil ||
        swellWaveHeightMeters != nil ||
        swellWavePeriodSeconds != nil ||
        swellWaveDirectionDegrees != nil ||
        windWaveHeightMeters != nil ||
        windWavePeriodSeconds != nil ||
        windWaveDirectionDegrees != nil ||
        seaSurfaceTemperatureC != nil
    }

    var hasAnyReadings: Bool {
        hasWindReadings || hasWaveReadings
    }
}

enum SurfConditionsService {
    static let sourceName = "Open-Meteo"

    static func fetch(
        start: Date,
        durationMinutes: Int,
        latitude: Double,
        longitude: Double,
        session: URLSession = .shared
    ) async throws -> SurfConditionsSnapshot {
        if TestingDefaults.isUITest,
           let scenario = TestingDefaults.surfConditionsScenario {
            return try mockSnapshot(
                for: scenario,
                start: start,
                durationMinutes: durationMinutes,
                latitude: latitude,
                longitude: longitude
            )
        }

        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        try validateRange(start: start, end: end, maxPastDays: 92, maxForecastDays: 8)

        async let marineResult = fetchMarineConditions(
            start: start,
            end: end,
            latitude: latitude,
            longitude: longitude,
            session: session
        )
        async let windResult = fetchWindConditions(
            start: start,
            end: end,
            latitude: latitude,
            longitude: longitude,
            session: session
        )

        var marine: MarineConditions?
        var wind: WindConditions?
        var errors: [Error] = []

        do {
            marine = try await marineResult
        } catch {
            errors.append(error)
        }

        do {
            wind = try await windResult
        } catch {
            errors.append(error)
        }

        if marine == nil && wind == nil {
            throw mostInformativeError(from: errors)
        }

        let snapshot = SurfConditionsSnapshot(
            source: sourceName,
            fetchedAt: Date(),
            latitude: marine?.latitude ?? latitude,
            longitude: marine?.longitude ?? longitude,
            windSpeedKph: wind?.windSpeedKph,
            windDirectionDegrees: wind?.windDirectionDegrees,
            waveHeightMeters: marine?.waveHeightMeters,
            swellWaveHeightMeters: marine?.swellWaveHeightMeters,
            swellWavePeriodSeconds: marine?.swellWavePeriodSeconds,
            swellWaveDirectionDegrees: marine?.swellWaveDirectionDegrees,
            windWaveHeightMeters: marine?.windWaveHeightMeters,
            windWavePeriodSeconds: marine?.windWavePeriodSeconds,
            windWaveDirectionDegrees: marine?.windWaveDirectionDegrees,
            seaSurfaceTemperatureC: marine?.seaSurfaceTemperatureC
        )

        guard snapshot.hasAnyReadings else {
            throw SurfConditionsError.noDataAvailable
        }

        return snapshot
    }

    private static func mockSnapshot(
        for scenario: String,
        start: Date,
        durationMinutes: Int,
        latitude: Double,
        longitude: Double
    ) throws -> SurfConditionsSnapshot {
        switch scenario.lowercased() {
        case "success", "success_full", "default":
            let end = start.addingTimeInterval(Double(durationMinutes) * 60)
            guard start <= end else {
                throw SurfConditionsError.outOfRange(maxPastDays: 92, maxForecastDays: 8)
            }
            return SurfConditionsSnapshot(
                source: sourceName,
                fetchedAt: Date(),
                latitude: latitude,
                longitude: longitude,
                windSpeedKph: 12.4,
                windDirectionDegrees: 270,
                waveHeightMeters: 1.45,
                swellWaveHeightMeters: 1.2,
                swellWavePeriodSeconds: 11,
                swellWaveDirectionDegrees: 268,
                windWaveHeightMeters: 0.6,
                windWavePeriodSeconds: 6,
                windWaveDirectionDegrees: 298,
                seaSurfaceTemperatureC: 17.8
            )
        case "no_data", "nodata":
            throw SurfConditionsError.noDataAvailable
        case "remote_error", "error":
            throw SurfConditionsError.remoteError("Mock surf report service error")
        case "out_of_range":
            throw SurfConditionsError.outOfRange(maxPastDays: 92, maxForecastDays: 8)
        default:
            throw SurfConditionsError.invalidResponse
        }
    }
}

private extension SurfConditionsService {
    struct MarineConditions: Sendable {
        let latitude: Double
        let longitude: Double
        let waveHeightMeters: Double?
        let swellWaveHeightMeters: Double?
        let swellWavePeriodSeconds: Double?
        let swellWaveDirectionDegrees: Double?
        let windWaveHeightMeters: Double?
        let windWavePeriodSeconds: Double?
        let windWaveDirectionDegrees: Double?
        let seaSurfaceTemperatureC: Double?
    }

    struct WindConditions: Sendable {
        let windSpeedKph: Double?
        let windDirectionDegrees: Double?
    }

    /// `@concurrent` so the network round trip, JSON decode, and hourly-series
    /// parsing all happen off the main actor; only the Sendable result hops back.
    @concurrent
    nonisolated static func fetchMarineConditions(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double,
        session: URLSession
    ) async throws -> MarineConditions {
        let url = try makeMarineURL(
            start: start,
            end: end,
            latitude: latitude,
            longitude: longitude
        )
        let response: OpenMeteoMarineResponse = try await fetchJSON(url: url, session: session)
        let times = parseTimes(response.hourly.time)
        let indices = indices(in: times, start: start, end: end)
        guard !indices.isEmpty else {
            throw SurfConditionsError.noMatchingHours
        }

        let waveHeightMeters = average(values: values(at: indices, in: response.hourly.wave_height))
        let swellWaveHeightMeters = average(values: values(at: indices, in: response.hourly.swell_wave_height))
        let swellWavePeriodSeconds = average(values: values(at: indices, in: response.hourly.swell_wave_period))
        let swellWaveDirectionDegrees = average(values: values(at: indices, in: response.hourly.swell_wave_direction))
        let windWaveHeightMeters = average(values: values(at: indices, in: response.hourly.wind_wave_height))
        let windWavePeriodSeconds = average(values: values(at: indices, in: response.hourly.wind_wave_period))
        let windWaveDirectionDegrees = average(values: values(at: indices, in: response.hourly.wind_wave_direction))
        let seaSurfaceTemperatureC = average(values: values(at: indices, in: response.hourly.sea_surface_temperature))

        return MarineConditions(
            latitude: response.latitude ?? latitude,
            longitude: response.longitude ?? longitude,
            waveHeightMeters: waveHeightMeters,
            swellWaveHeightMeters: swellWaveHeightMeters,
            swellWavePeriodSeconds: swellWavePeriodSeconds,
            swellWaveDirectionDegrees: swellWaveDirectionDegrees,
            windWaveHeightMeters: windWaveHeightMeters,
            windWavePeriodSeconds: windWavePeriodSeconds,
            windWaveDirectionDegrees: windWaveDirectionDegrees,
            seaSurfaceTemperatureC: seaSurfaceTemperatureC
        )
    }

    /// See `fetchMarineConditions` — runs off-main end to end.
    @concurrent
    nonisolated static func fetchWindConditions(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double,
        session: URLSession
    ) async throws -> WindConditions {
        let url = try makeWindURL(
            start: start,
            end: end,
            latitude: latitude,
            longitude: longitude
        )
        let response: OpenMeteoWeatherResponse = try await fetchJSON(url: url, session: session)
        let times = parseTimes(response.hourly.time)
        let indices = indices(in: times, start: start, end: end)
        guard !indices.isEmpty else {
            throw SurfConditionsError.noMatchingHours
        }
        let windSpeedKph = average(values: values(at: indices, in: response.hourly.wind_speed_10m))
        let windDirectionDegrees = average(values: values(at: indices, in: response.hourly.wind_direction_10m))
        return WindConditions(
            windSpeedKph: windSpeedKph,
            windDirectionDegrees: windDirectionDegrees
        )
    }

    // The helpers below are pure functions over Sendable values; `nonisolated`
    // lets the `@concurrent` fetch path above call them without hopping to main.
    nonisolated static func makeMarineURL(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "marine-api.open-meteo.com"
        components.path = "/v1/marine"

        let startHour = floorToHour(start)
        let endHour = ceilToHour(end)
        let hourlyVariables = [
            "wave_height",
            "swell_wave_height",
            "swell_wave_period",
            "swell_wave_direction",
            "wind_wave_height",
            "wind_wave_period",
            "wind_wave_direction",
            "sea_surface_temperature"
        ]

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: hourlyVariables.joined(separator: ",")),
            URLQueryItem(name: "start_hour", value: hourFormatter.string(from: startHour)),
            URLQueryItem(name: "end_hour", value: hourFormatter.string(from: endHour)),
            URLQueryItem(name: "timeformat", value: "iso8601"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "length_unit", value: "metric"),
            URLQueryItem(name: "cell_selection", value: "sea")
        ] + pastFutureQueryItems(start: start, end: end, maxPastDays: 92, maxForecastDays: 8)

        components.queryItems = queryItems
        guard let url = components.url else {
            throw SurfConditionsError.invalidURL
        }
        return url
    }

    nonisolated static func makeWindURL(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"

        let startHour = floorToHour(start)
        let endHour = ceilToHour(end)
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "start_hour", value: hourFormatter.string(from: startHour)),
            URLQueryItem(name: "end_hour", value: hourFormatter.string(from: endHour)),
            URLQueryItem(name: "timeformat", value: "iso8601"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh")
        ] + pastFutureQueryItems(start: start, end: end, maxPastDays: 92, maxForecastDays: 16)

        components.queryItems = queryItems
        guard let url = components.url else {
            throw SurfConditionsError.invalidURL
        }
        return url
    }

    @concurrent
    nonisolated static func fetchJSON<T: Decodable & Sendable>(url: URL, session: URLSession) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let reason = decodeRemoteError(from: data) {
                throw SurfConditionsError.remoteError(reason)
            }
            throw SurfConditionsError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let reason = decodeRemoteError(from: data) {
                throw SurfConditionsError.remoteError(reason)
            }
            throw SurfConditionsError.decodingFailed
        }
    }

    nonisolated static func pastFutureQueryItems(
        start: Date,
        end: Date,
        maxPastDays: Int,
        maxForecastDays: Int
    ) -> [URLQueryItem] {
        let calendar = utcCalendar
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let today = calendar.startOfDay(for: Date())

        var items: [URLQueryItem] = []

        if startDay < today {
            let pastDays = min(maxPastDays, max(1, calendar.dateComponents([.day], from: startDay, to: today).day ?? 0))
            items.append(URLQueryItem(name: "past_days", value: "\(pastDays)"))
        }

        if endDay > today {
            let forecastDays = min(maxForecastDays, max(1, calendar.dateComponents([.day], from: today, to: endDay).day ?? 0))
            items.append(URLQueryItem(name: "forecast_days", value: "\(forecastDays)"))
        }

        return items
    }

    nonisolated static func parseTimes(_ values: [String]) -> [Date] {
        values.compactMap { parseTime($0) }
    }

    nonisolated static func parseTime(_ value: String) -> Date? {
        if let date = iso8601Formatter.date(from: value) {
            return date
        }
        if let date = iso8601FractionalFormatter.date(from: value) {
            return date
        }
        for formatter in timeParsers {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    nonisolated static func indices(in times: [Date], start: Date, end: Date) -> [Int] {
        let indices = times.enumerated().compactMap { index, time in
            time >= start && time <= end ? index : nil
        }
        if !indices.isEmpty {
            return indices
        }
        if let nearest = nearestIndex(for: start, in: times) {
            return [nearest]
        }
        return []
    }

    nonisolated static func nearestIndex(for date: Date, in times: [Date]) -> Int? {
        guard !times.isEmpty else { return nil }
        var bestIndex = 0
        var bestInterval = abs(times[0].timeIntervalSince(date))
        for (index, time) in times.enumerated() {
            let interval = abs(time.timeIntervalSince(date))
            if interval < bestInterval {
                bestInterval = interval
                bestIndex = index
            }
        }
        return bestIndex
    }

    nonisolated static func values(at indices: [Int], in values: [Double?]?) -> [Double?] {
        guard let values else { return [] }
        return indices.compactMap { index in
            guard values.indices.contains(index) else { return nil }
            return values[index]
        }
    }

    nonisolated static func average(values: [Double?]) -> Double? {
        let filtered = values.compactMap { $0 }
        guard !filtered.isEmpty else { return nil }
        let total = filtered.reduce(0, +)
        return total / Double(filtered.count)
    }

    static func validateRange(start: Date, end: Date, maxPastDays: Int, maxForecastDays: Int) throws {
        let calendar = utcCalendar
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let today = calendar.startOfDay(for: Date())
        let earliest = calendar.date(byAdding: .day, value: -maxPastDays, to: today) ?? today
        let latest = calendar.date(byAdding: .day, value: maxForecastDays, to: today) ?? today
        guard startDay >= earliest, endDay <= latest else {
            throw SurfConditionsError.outOfRange(maxPastDays: maxPastDays, maxForecastDays: maxForecastDays)
        }
    }

    nonisolated static func floorToHour(_ date: Date) -> Date {
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour], from: date)
        return utcCalendar.date(from: components) ?? date
    }

    nonisolated static func ceilToHour(_ date: Date) -> Date {
        let floored = floorToHour(date)
        if floored == date {
            return date
        }
        return utcCalendar.date(byAdding: .hour, value: 1, to: floored) ?? date
    }

    /// Stored constants: these were computed `static var`s, so every access
    /// re-allocated a Calendar/DateFormatter — hundreds of times per auto-fill
    /// (once per hourly time string, per format). `Calendar` is Sendable, so a
    /// `nonisolated` constant is fine as-is.
    nonisolated static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// `nonisolated(unsafe)`: DateFormatter/ISO8601DateFormatter are documented
    /// thread-safe for formatting/parsing, and these are fully configured before
    /// first use and never mutated afterward, so sharing them across the
    /// `@concurrent` fetch/parse path is safe despite not being Sendable.
    nonisolated(unsafe) static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    // See `hourFormatter` for why `nonisolated(unsafe)` is safe here.
    nonisolated(unsafe) static let timeParsers: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mmXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    // See `hourFormatter` for why `nonisolated(unsafe)` is safe here.
    nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // See `hourFormatter` for why `nonisolated(unsafe)` is safe here.
    nonisolated(unsafe) static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static func decodeRemoteError(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(OpenMeteoErrorResponse.self, from: data) else {
            return nil
        }
        guard response.error == true || response.reason != nil else {
            return nil
        }
        return response.reason ?? "Unknown error"
    }

    static func mostInformativeError(from errors: [Error]) -> Error {
        let surfErrors = errors.compactMap { $0 as? SurfConditionsError }
        if let best = surfErrors.sorted(by: { priority(for: $0) < priority(for: $1) }).first {
            return best
        }
        return errors.first ?? SurfConditionsError.invalidResponse
    }

    static func priority(for error: SurfConditionsError) -> Int {
        switch error {
        case .outOfRange:
            return 0
        case .remoteError:
            return 1
        case .noMatchingHours:
            return 2
        case .invalidResponse:
            return 3
        case .decodingFailed:
            return 4
        case .invalidURL:
            return 5
        case .noDataAvailable:
            return 6
        }
    }
}

private enum SurfConditionsMapping {
    static func windCondition(for speedKph: Double?) -> WindCondition? {
        guard let speedKph else { return nil }
        switch speedKph {
        case ..<5:
            return .calm
        case ..<15:
            return .breezy
        case ..<25:
            return .windy
        default:
            return .strong
        }
    }

    static func waveHeightCategory(for meters: Double?) -> WaveHeight? {
        guard let meters else { return nil }
        switch meters {
        case ..<0.6:
            return .kneeHigh
        case ..<1.2:
            return .waistHigh
        case ..<1.8:
            return .shoulderHigh
        case ..<2.4:
            return .overhead
        default:
            return .wayOverhead
        }
    }
}

enum SurfConditionsError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case noMatchingHours
    case noDataAvailable
    case outOfRange(maxPastDays: Int, maxForecastDays: Int)
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the surf report request."
        case .invalidResponse:
            return "Surf report service is unavailable."
        case .decodingFailed:
            return "Surf report data could not be read."
        case .noMatchingHours:
            return "Surf report data is unavailable for that time."
        case .noDataAvailable:
            return "Surf report data is unavailable for that location or time."
        case .outOfRange(let maxPastDays, let maxForecastDays):
            return "Surf report data is available for the past \(maxPastDays) days and the next \(maxForecastDays) days."
        case .remoteError(let reason):
            return "Surf report service error: \(reason)"
        }
    }
}

private struct OpenMeteoMarineResponse: Decodable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let hourly: Hourly

    struct Hourly: Decodable, Sendable {
        let time: [String]
        let wave_height: [Double?]?
        let swell_wave_height: [Double?]?
        let swell_wave_period: [Double?]?
        let swell_wave_direction: [Double?]?
        let wind_wave_height: [Double?]?
        let wind_wave_period: [Double?]?
        let wind_wave_direction: [Double?]?
        let sea_surface_temperature: [Double?]?
    }
}

private struct OpenMeteoWeatherResponse: Decodable, Sendable {
    let hourly: Hourly

    struct Hourly: Decodable, Sendable {
        let time: [String]
        let wind_speed_10m: [Double?]?
        let wind_direction_10m: [Double?]?
    }
}

private struct OpenMeteoErrorResponse: Decodable, Sendable {
    let error: Bool?
    let reason: String?
}
