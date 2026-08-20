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
    /// Sea level relative to MSL, in metres, averaged over the session window.
    /// Model-derived, not a chart-datum tide table — see `SurfConditionsService`.
    let seaLevelHeightMeters: Double?
    let tideTrend: TideTrend?

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
        seaSurfaceTemperatureC != nil ||
        seaLevelHeightMeters != nil ||
        tideTrend != nil
    }

    var hasAnyReadings: Bool {
        hasWindReadings || hasWaveReadings
    }
}

enum SurfConditionsService {
    static let sourceName = "Open-Meteo"

    /// Hours of extra marine data fetched either side of the session window,
    /// purely so the tide series has enough shape to read.
    ///
    /// A 90-minute session yields two or three hourly sea-level samples — enough
    /// for a slope, nowhere near enough to tell "just past high" from "halfway
    /// down". Three hours each side covers roughly half a semi-diurnal cycle, so
    /// the local maximum or minimum is visible. Every other reading still averages
    /// over the real window only: `indices(in:start:end:)` filters back to it, so
    /// the pad cannot leak into wave height or wind.
    nonisolated static let tideContextHours = 3

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
            seaSurfaceTemperatureC: marine?.seaSurfaceTemperatureC,
            seaLevelHeightMeters: marine?.seaLevelHeightMeters,
            tideTrend: marine?.tideTrend
        )

        guard snapshot.hasAnyReadings else {
            throw SurfConditionsError.noDataAvailable
        }

        return snapshot
    }

    /// Classifies where in the tide cycle `date` sits, from an hourly sea-level
    /// series.
    ///
    /// **Honesty note.** Open-Meteo's `sea_level_height_msl` is a *model* field
    /// referenced to mean sea level, not a harmonic prediction against chart
    /// datum. It is reliable for the shape of the curve — which way the water is
    /// moving, and roughly when it turns — and not for "high tide is 1.7 m at
    /// 06:12". Everything derived here stays on the shape side of that line, and
    /// the UI copy says so.
    ///
    /// Method: central-difference the slope at the sample nearest `date`, then
    /// compare it against the steepest slope this curve could have. For a
    /// semi-diurnal sinusoid of amplitude A and period 12.42 h the peak rate is
    /// A * 2π/12.42 ≈ 0.51 A per hour, and the flat quarter around each turn is
    /// where the rate falls below a quarter of that — hence the 0.13 A cut for
    /// calling it high or low rather than rising or falling.
    nonisolated static func deriveTideTrend(
        times: [Date],
        levels: [Double?]?,
        around date: Date
    ) -> TideTrend? {
        guard let series = tideSeries(times: times, levels: levels) else { return nil }
        return deriveTideTrend(from: series, around: date)
    }

    /// Paired, sorted tide samples plus the amplitude extrema. Built once per
    /// marine series so Best Window doesn't rebuild the curve for every hour.
    nonisolated struct TideSampleSeries: Sendable {
        let samples: [(date: Date, level: Double)]
        let highest: Double
        let lowest: Double
    }

    nonisolated static func tideSeries(times: [Date], levels: [Double?]?) -> TideSampleSeries? {
        guard let levels else { return nil }

        // Pair up and drop anything unusable. Sea level is legitimately negative,
        // so only non-finite values are rejected.
        var samples: [(date: Date, level: Double)] = []
        samples.reserveCapacity(min(times.count, levels.count))
        for (index, time) in times.enumerated() {
            guard levels.indices.contains(index), let level = levels[index], level.isFinite else { continue }
            samples.append((time, level))
        }
        samples.sort { $0.date < $1.date }
        guard samples.count >= 2,
              let highest = samples.map(\.level).max(),
              let lowest = samples.map(\.level).min()
        else { return nil }
        return TideSampleSeries(samples: samples, highest: highest, lowest: lowest)
    }

    nonisolated static func deriveTideTrend(
        from series: TideSampleSeries,
        around date: Date
    ) -> TideTrend? {
        let samples = series.samples
        guard let pivot = nearestSortedSampleIndex(for: date, in: samples) else { return nil }

        // Central difference where possible; one-sided at the ends. Slope is per
        // hour so the threshold below is in metres-per-hour.
        let lower = max(0, pivot - 1)
        let upper = min(samples.count - 1, pivot + 1)
        guard lower != upper else { return nil }
        let hours = samples[upper].date.timeIntervalSince(samples[lower].date) / 3600
        guard hours > 0 else { return nil }
        let slope = (samples[upper].level - samples[lower].level) / hours
        guard slope.isFinite else { return nil }

        let highest = series.highest
        let lowest = series.lowest
        let amplitude = (highest - lowest) / 2
        // A dead-flat series carries no tide signal at all; claiming a trend from
        // it would be inventing one.
        guard amplitude > 0.01 else { return nil }

        if abs(slope) < 0.13 * amplitude {
            return samples[pivot].level >= (highest + lowest) / 2 ? .high : .low
        }
        return slope > 0 ? .rising : .falling
    }

    /// Closest sample in a date-sorted series. Ties keep the earlier index,
    /// matching `nearestIndex(for:in:)`.
    nonisolated static func nearestSortedSampleIndex(
        for date: Date,
        in samples: [(date: Date, level: Double)]
    ) -> Int? {
        guard !samples.isEmpty else { return nil }
        var lo = 0
        var hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].date < date {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo == 0 { return 0 }
        if lo == samples.count { return samples.count - 1 }
        let beforeDistance = abs(samples[lo - 1].date.timeIntervalSince(date))
        let afterDistance = abs(samples[lo].date.timeIntervalSince(date))
        return beforeDistance <= afterDistance ? lo - 1 : lo
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
                seaSurfaceTemperatureC: 17.8,
                seaLevelHeightMeters: 0.42,
                tideTrend: .falling
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

// MARK: - Hourly day forecast (Best Window Today)

/// One stretch of daylight: a sunrise and the sunset that follows it.
///
/// Absolute instants, not clock times, so comparing a forecast hour against one
/// needs no timezone reasoning at all.
nonisolated struct DaylightInterval: Sendable, Hashable {
    let sunrise: Date
    let sunset: Date
}

/// A day's hourly forecast plus the daylight it falls in.
///
/// `daylight` is empty when the provider did not give usable sunrise/sunset —
/// an older response shape, a failed wind request, a polar day. Callers must
/// treat empty as "unknown" and carry on unfiltered, never as "no daylight":
/// showing the surfer nothing is worse than showing them an unfiltered day.
nonisolated struct DayForecast: Sendable, Hashable {
    var hours: [ForecastHour]
    var daylight: [DaylightInterval]

    init(hours: [ForecastHour], daylight: [DaylightInterval] = []) {
        self.hours = hours
        self.daylight = daylight
    }
}

// Lives in this file rather than alongside the card because it reuses this
// file's URL building, time parsing and error mapping wholesale. Same provider,
// same shapes — the only difference is that nothing is averaged: the scorer wants
// the hour-by-hour series, not one summary number.
extension SurfConditionsService {

    /// Hourly marine, wind and sea-level readings for the next `hours` at a spot.
    ///
    /// Marine and wind come from two different endpoints on their own hourly
    /// grids, so they are joined on the hour rather than by index — a missing
    /// marine hour must not silently shift every wind reading by one.
    @concurrent
    nonisolated static func fetchDayForecast(
        latitude: Double,
        longitude: Double,
        start: Date = Date(),
        hours: Int = 24,
        session: URLSession = .shared
    ) async throws -> DayForecast {
        if TestingDefaults.isUITest, let scenario = TestingDefaults.windowScenario {
            return try mockDayForecast(for: scenario, start: start, hours: hours)
        }

        let hourCount = max(1, min(hours, 48))
        let first = floorToHour(start)
        let last = first.addingTimeInterval(Double(hourCount) * 3600)

        async let marineResult = fetchMarineSeries(
            start: first, end: last, latitude: latitude, longitude: longitude, session: session)
        async let windResult = fetchWindSeries(
            start: first, end: last, latitude: latitude, longitude: longitude, session: session)

        var marine: [Date: MarineSample] = [:]
        var wind = WindSeries()
        var errors: [Error] = []

        do { marine = try await marineResult } catch { errors.append(error) }
        do { wind = try await windResult } catch { errors.append(error) }

        // Wind alone cannot rank a surf day and marine alone is missing the single
        // most common ruiner of good swell, but either is better than nothing and
        // WindowScorer imputes what is absent rather than guessing at it.
        guard !marine.isEmpty || !wind.samples.isEmpty else {
            throw mostInformativeError(from: errors)
        }

        let stamps = Set(marine.keys).union(wind.samples.keys)
            .filter { $0 >= first && $0 <= last }
            .sorted()

        let hourly: [ForecastHour] = stamps.map { stamp in
            let m = marine[stamp]
            let w = wind.samples[stamp]
            return ForecastHour(
                date: stamp,
                conditions: ConditionsSample(
                    swellWaveHeightMeters: m?.swellWaveHeightMeters,
                    swellWavePeriodSeconds: m?.swellWavePeriodSeconds,
                    swellWaveDirectionDegrees: m?.swellWaveDirectionDegrees,
                    windWaveHeightMeters: m?.windWaveHeightMeters,
                    waveHeightMeters: m?.waveHeightMeters,
                    windSpeedKph: w?.windSpeedKph,
                    windDirectionDegrees: w?.windDirectionDegrees,
                    seaSurfaceTemperatureC: m?.seaSurfaceTemperatureC,
                    seaLevelHeightMeters: m?.seaLevelHeightMeters,
                    tideTrend: m?.tideTrend
                )
            )
        }

        return DayForecast(hours: hourly, daylight: wind.daylight)
    }

    struct MarineSample: Sendable {
        let waveHeightMeters: Double?
        let swellWaveHeightMeters: Double?
        let swellWavePeriodSeconds: Double?
        let swellWaveDirectionDegrees: Double?
        let windWaveHeightMeters: Double?
        let seaSurfaceTemperatureC: Double?
        let seaLevelHeightMeters: Double?
        let tideTrend: TideTrend?
    }

    struct WindSample: Sendable {
        let windSpeedKph: Double?
        let windDirectionDegrees: Double?
    }

    /// What one forecast-endpoint call yields for the day card: the hourly wind
    /// samples, and — because sunrise/sunset ride along on the same request —
    /// the daylight the day falls in.
    /// `nonisolated` for the same reason `SurfBreakCatalog` is: under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` even a plain value type's
    /// memberwise init is main-actor isolated, and this one is built inside the
    /// `@concurrent` fetch.
    nonisolated struct WindSeries: Sendable {
        var samples: [Date: WindSample] = [:]
        var daylight: [DaylightInterval] = []
    }

    @concurrent
    nonisolated static func fetchMarineSeries(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double,
        session: URLSession
    ) async throws -> [Date: MarineSample] {
        let url = try makeMarineURL(start: start, end: end, latitude: latitude, longitude: longitude)
        let response: OpenMeteoMarineResponse = try await fetchJSON(url: url, session: session)
        let times = parseTimes(response.hourly.time)
        guard !times.isEmpty else { throw SurfConditionsError.noMatchingHours }

        let hourly = response.hourly
        let series = tideSeries(times: times, levels: hourly.sea_level_height_msl)
        var out: [Date: MarineSample] = [:]
        out.reserveCapacity(times.count)
        for (index, time) in times.enumerated() {
            // Trend is per hour here, unlike the session snapshot: "when today?"
            // is largely a tide question, so each hour needs its own answer,
            // derived from the same full series (built once above).
            let trend = series.flatMap { deriveTideTrend(from: $0, around: time) }
            out[time] = MarineSample(
                waveHeightMeters: value(hourly.wave_height, at: index),
                swellWaveHeightMeters: value(hourly.swell_wave_height, at: index),
                swellWavePeriodSeconds: value(hourly.swell_wave_period, at: index),
                swellWaveDirectionDegrees: value(hourly.swell_wave_direction, at: index),
                windWaveHeightMeters: value(hourly.wind_wave_height, at: index),
                seaSurfaceTemperatureC: value(hourly.sea_surface_temperature, at: index),
                seaLevelHeightMeters: value(hourly.sea_level_height_msl, at: index),
                tideTrend: trend
            )
        }
        return out
    }

    @concurrent
    nonisolated static func fetchWindSeries(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double,
        session: URLSession
    ) async throws -> WindSeries {
        let url = try makeWindURL(
            start: start, end: end, latitude: latitude, longitude: longitude, includeDaylight: true)
        let response: OpenMeteoWeatherResponse = try await fetchJSON(url: url, session: session)
        let times = parseTimes(response.hourly.time)
        guard !times.isEmpty else { throw SurfConditionsError.noMatchingHours }

        var out: [Date: WindSample] = [:]
        for (index, time) in times.enumerated() {
            out[time] = WindSample(
                windSpeedKph: value(response.hourly.wind_speed_10m, at: index),
                windDirectionDegrees: value(response.hourly.wind_direction_10m, at: index)
            )
        }
        return WindSeries(
            samples: out,
            daylight: daylightIntervals(
                sunrise: response.daily?.sunrise ?? [], sunset: response.daily?.sunset ?? [])
        )
    }

    /// Pairs sunrises with the sunsets that follow them.
    ///
    /// Deliberately *not* index-paired. The provider buckets these by the day of
    /// the requested timezone, and Peak asks in GMT, so at a longitude far from
    /// Greenwich the sunrise and sunset in one bucket can belong to different
    /// local days and even come back out of order — for a break in Bali, GMT-day
    /// row `i` holds a sunset that happens *before* its sunrise. Merging the two
    /// lists by instant and walking them in order is immune to that, and to
    /// missing or null entries on either side.
    ///
    /// Rows the provider could not compute (polar day, polar night) parse to
    /// nothing and simply contribute no interval; a range with no intervals at
    /// all is reported as unknown, never as "dark all day".
    nonisolated static func daylightIntervals(sunrise: [String?], sunset: [String?]) -> [DaylightInterval] {
        let sunrises = sunrise.compactMap { $0.flatMap(parseTime) }.sorted()
        let sunsets = sunset.compactMap { $0.flatMap(parseTime) }.sorted()
        guard !sunrises.isEmpty, !sunsets.isEmpty else { return [] }

        var intervals: [DaylightInterval] = []
        var nextSunset = sunsets.startIndex
        for rise in sunrises {
            while nextSunset < sunsets.endIndex && sunsets[nextSunset] <= rise {
                nextSunset += 1
            }
            guard nextSunset < sunsets.endIndex else { break }
            intervals.append(DaylightInterval(sunrise: rise, sunset: sunsets[nextSunset]))
        }
        return intervals
    }

    nonisolated static func value(_ values: [Double?]?, at index: Int) -> Double? {
        guard let values, values.indices.contains(index), let value = values[index], value.isFinite else {
            return nil
        }
        return value
    }

    /// Vector (circular) mean for compass bearings in degrees. Directions are a
    /// circular quantity, so a plain arithmetic mean is wrong across the 0°/360°
    /// wrap — e.g. averaging 350° and 10° must yield 0° (N), not 180° (S). Used
    /// only for the direction fields; scalar quantities (height/period/speed/temp)
    /// keep the linear `average`.
    nonisolated static func circularAverage(values: [Double?]) -> Double? {
        let filtered = values.compactMap { $0 }
        guard !filtered.isEmpty else { return nil }
        var sinSum = 0.0
        var cosSum = 0.0
        for degrees in filtered {
            let radians = degrees * .pi / 180
            sinSum += sin(radians)
            cosSum += cos(radians)
        }
        // Perfectly opposing samples cancel out and leave the mean undefined;
        // fall back to the linear mean rather than returning an arbitrary bearing.
        guard abs(sinSum) > 1e-9 || abs(cosSum) > 1e-9 else {
            return average(values: values)
        }
        let degrees = atan2(sinSum, cosSum) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Deterministic stand-in for the network under UI test.
    ///
    /// Shaped like a real day rather than as flat filler: fixed groundswell, wind
    /// light at dawn and building through the afternoon, a semi-diurnal tide. That
    /// makes the early hours genuinely the best ones, so the card under test is
    /// showing a real answer from the real scorer — only the provider is faked.
    nonisolated static func mockDayForecast(
        for scenario: String,
        start: Date,
        hours: Int
    ) throws -> DayForecast {
        switch scenario.lowercased() {
        case "error", "remote_error":
            throw SurfConditionsError.remoteError("Mock window service error")
        case "no_data", "nodata":
            throw SurfConditionsError.noDataAvailable
        default:
            let count = max(1, hours)
            // Daylight covering the whole mocked span. The UI tests run at
            // whatever hour CI happens to reach them, and a mock that made half
            // the fixture "night" would make those tests pass or fail on the
            // wall clock. The daylight *filter* is pinned by unit tests, which
            // can control the clock; what these need is a deterministic day.
            let first = floorToHour(start)
            return DayForecast(
                hours: mockForecastHours(start: start, hours: count),
                daylight: [DaylightInterval(
                    sunrise: first.addingTimeInterval(-3600),
                    sunset: first.addingTimeInterval(Double(count + 1) * 3600)
                )]
            )
        }
    }

    /// Shared by the UI-test mock and by the unit test that proves this forecast,
    /// against the seeded history, really does clear the confidence gate.
    nonisolated static func mockForecastHours(start: Date, hours: Int) -> [ForecastHour] {
        let first = floorToHour(start)
        return (0..<hours).map { index in
            let t = Double(index)
            // Dawn glass building to an onshore afternoon.
            let windSpeed = min(34, 4 + max(0, t - 4) * 2.6)
            let windDirection = 40 + min(180, max(0, t - 4) * 12)
            let angle = 2 * Double.pi * t / 12.42
            let seaLevel = 0.8 * sin(angle)
            let slope = cos(angle)
            let trend: TideTrend
            if abs(slope) < 0.25 {
                trend = seaLevel >= 0 ? .high : .low
            } else {
                trend = slope > 0 ? .rising : .falling
            }
            let windWave = min(1.2, windSpeed / 45 * 0.9)
            return ForecastHour(
                date: first.addingTimeInterval(t * 3600),
                conditions: ConditionsSample(
                    swellWaveHeightMeters: 1.2,
                    swellWavePeriodSeconds: 12,
                    swellWaveDirectionDegrees: 268,
                    windWaveHeightMeters: windWave,
                    waveHeightMeters: (1.2 * 1.2 + windWave * windWave).squareRoot(),
                    windSpeedKph: windSpeed,
                    windDirectionDegrees: windDirection,
                    seaSurfaceTemperatureC: 17.5,
                    seaLevelHeightMeters: seaLevel,
                    tideTrend: trend
                )
            )
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
        let seaLevelHeightMeters: Double?
        let tideTrend: TideTrend?
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
        let swellWaveDirectionDegrees = circularAverage(values: values(at: indices, in: response.hourly.swell_wave_direction))
        let windWaveHeightMeters = average(values: values(at: indices, in: response.hourly.wind_wave_height))
        let windWavePeriodSeconds = average(values: values(at: indices, in: response.hourly.wind_wave_period))
        let windWaveDirectionDegrees = circularAverage(values: values(at: indices, in: response.hourly.wind_wave_direction))
        let seaSurfaceTemperatureC = average(values: values(at: indices, in: response.hourly.sea_surface_temperature))
        let seaLevelHeightMeters = average(values: values(at: indices, in: response.hourly.sea_level_height_msl))

        // Trend reads the WHOLE returned series (padded either side of the
        // session), not just the in-window slice, because a turning point is only
        // visible with context. Height still averages over the window alone.
        let tideTrend = deriveTideTrend(
            times: times,
            levels: response.hourly.sea_level_height_msl,
            around: start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        )

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
            seaSurfaceTemperatureC: seaSurfaceTemperatureC,
            seaLevelHeightMeters: seaLevelHeightMeters,
            tideTrend: tideTrend
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
        let windDirectionDegrees = circularAverage(values: values(at: indices, in: response.hourly.wind_direction_10m))
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

        // Padded so the tide series has context either side of the session; see
        // `tideContextHours`. Averaging is unaffected — it re-filters to the window.
        let pad = Double(tideContextHours) * 3600
        let paddedStart = start.addingTimeInterval(-pad)
        let paddedEnd = end.addingTimeInterval(pad)
        let startHour = floorToHour(paddedStart)
        let endHour = ceilToHour(paddedEnd)
        let hourlyVariables = [
            "wave_height",
            "swell_wave_height",
            "swell_wave_period",
            "swell_wave_direction",
            "wind_wave_height",
            "wind_wave_period",
            "wind_wave_direction",
            "sea_surface_temperature",
            "sea_level_height_msl"
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
        ]

        components.queryItems = queryItems
        guard let url = components.url else {
            throw SurfConditionsError.invalidURL
        }
        return url
    }

    /// - Parameter includeDaylight: also asks for `daily=sunrise,sunset` over the
    ///   same span. Only the day-forecast path wants it — a session snapshot is
    ///   about one hour that has already happened, and daylight cannot change
    ///   what was measured then. Requesting `daily` obliges us to send
    ///   `start_date`/`end_date` as well, because a bare `daily` alongside
    ///   `start_hour`/`end_hour` comes back with empty arrays.
    nonisolated static func makeWindURL(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double,
        includeDaylight: Bool = false
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"

        let startHour = floorToHour(start)
        let endHour = ceilToHour(end)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "start_hour", value: hourFormatter.string(from: startHour)),
            URLQueryItem(name: "end_hour", value: hourFormatter.string(from: endHour)),
            URLQueryItem(name: "timeformat", value: "iso8601"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh")
        ]

        if includeDaylight {
            // A day either side of the scored span, so there is always a sunrise
            // and a sunset bracketing every hour being classified. Without the
            // padding, an hour before the range's first sunrise has no event in
            // front of it and cannot be judged either way.
            queryItems += [
                URLQueryItem(name: "daily", value: "sunrise,sunset"),
                URLQueryItem(name: "start_date",
                             value: dayFormatter.string(from: startHour.addingTimeInterval(-86_400))),
                URLQueryItem(name: "end_date",
                             value: dayFormatter.string(from: endHour.addingTimeInterval(86_400)))
            ]
        }

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

    // `past_days` / `forecast_days` used to be appended to both URLs whenever the
    // requested span reached outside today. They are gone, and their absence is
    // load-bearing rather than a tidy-up.
    //
    // Open-Meteo rejects them outright when the request also carries an explicit
    // range — "Parameter 'forecast_days' is mutually exclusive with 'start_date'
    // and 'end_date'", 400, no data — and `start_hour`/`end_hour` count as an
    // explicit range. Every request Peak made that reached past midnight or into
    // a previous day therefore failed at the provider: auto-filling any session
    // not logged the same day, the entire backfill, and every single Best Window
    // fetch (a 24-hour span from now always crosses midnight). `start_hour` /
    // `end_hour` already bound the range on their own, and on their own they
    // serve the full archive and forecast horizon, so nothing is lost by
    // dropping the day counts. `validateRange` still keeps callers inside the
    // horizon those counts used to cap.

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

    /// Calendar days for `start_date` / `end_date`. GMT, matching `timezone=GMT`
    /// on every request.
    ///
    /// Plain `nonisolated`, unlike its neighbours: those predate `DateFormatter`
    /// being `Sendable` and marking a new one `nonisolated(unsafe)` now warns.
    nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
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

    nonisolated static func mostInformativeError(from errors: [Error]) -> Error {
        let surfErrors = errors.compactMap { $0 as? SurfConditionsError }
        if let best = surfErrors.sorted(by: { priority(for: $0) < priority(for: $1) }).first {
            return best
        }
        return errors.first ?? SurfConditionsError.invalidResponse
    }

    nonisolated static func priority(for error: SurfConditionsError) -> Int {
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

/// Bands a numeric reading into the editor's coarse pickers.
///
/// Internal rather than private because `ManualConditionEstimate` is its exact
/// inverse and the two are only correct *together* — a test pins the round trip,
/// which it cannot do if this is unreachable.
enum SurfConditionsMapping {
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

private nonisolated struct OpenMeteoMarineResponse: Decodable, Sendable {
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
        let sea_level_height_msl: [Double?]?
    }
}

private nonisolated struct OpenMeteoWeatherResponse: Decodable, Sendable {
    let hourly: Hourly
    /// Absent on every request that does not ask for `daily`, and on any older
    /// response shape, hence optional all the way down.
    let daily: Daily?

    struct Hourly: Decodable, Sendable {
        let time: [String]
        let wind_speed_10m: [Double?]?
        let wind_direction_10m: [Double?]?
    }

    struct Daily: Decodable, Sendable {
        /// Null for days the provider cannot compute a sunrise or sunset for —
        /// polar summer and polar winter — so the elements are optional too.
        let sunrise: [String?]?
        let sunset: [String?]?
    }
}

private nonisolated struct OpenMeteoErrorResponse: Decodable, Sendable {
    let error: Bool?
    let reason: String?
}
