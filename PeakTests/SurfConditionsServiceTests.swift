import Foundation
import XCTest

@testable import Peak

final class SurfConditionsServiceTests: XCTestCase {
    func testFetchParsesISO8601TimesWithTimezone() async throws {
        let start = makeRecentGMTDate()
        let marineTime = hourStringWithZone(start)
        let windTime = hourStringWithZone(start, includeSeconds: true)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["\(marineTime)"],
            "wave_height": [1.2],
            "swell_wave_height": [1.1],
            "swell_wave_period": [12.0],
            "swell_wave_direction": [270.0],
            "wind_wave_height": [0.6],
            "wind_wave_period": [6.0],
            "wind_wave_direction": [300.0],
            "sea_surface_temperature": [18.0]
          }
        }
        """
        let windJSON = """
        {
          "hourly": {
            "time": ["\(windTime)"],
            "wind_speed_10m": [12.0],
            "wind_direction_10m": [280.0]
          }
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            if host == "api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(windJSON.utf8))
            }
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        let snapshot = try await SurfConditionsService.fetch(
            start: start,
            durationMinutes: 60,
            latitude: 33.3,
            longitude: -117.6,
            session: session
        )

        XCTAssertEqual(snapshot.waveHeightMeters ?? 0, 1.2, accuracy: 0.01)
        XCTAssertEqual(snapshot.windSpeedKph ?? 0, 12.0, accuracy: 0.01)
        XCTAssertTrue(snapshot.hasWaveReadings)
        XCTAssertTrue(snapshot.hasWindReadings)
    }

    func testFetchDecodesRemoteErrorResponse() async {
        let start = makeRecentGMTDate()
        let errorJSON = """
        {"error": true, "reason": "Invalid latitude"}
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            return (self.makeResponse(url: url, statusCode: 400), Data(errorJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        do {
            _ = try await SurfConditionsService.fetch(
                start: start,
                durationMinutes: 60,
                latitude: 0,
                longitude: 0,
                session: session
            )
            XCTFail("Expected remote error")
        } catch let error as SurfConditionsError {
            guard case .remoteError(let reason) = error else {
                XCTFail("Expected remoteError but got \(error)")
                return
            }
            XCTAssertEqual(reason, "Invalid latitude")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchReturnsPartialWhenWindFails() async throws {
        let start = makeRecentGMTDate()
        let hour = hourString(start)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["\(hour)"],
            "wave_height": [1.4],
            "swell_wave_height": [1.2],
            "swell_wave_period": [11.0],
            "swell_wave_direction": [275.0],
            "wind_wave_height": [0.5],
            "wind_wave_period": [5.0],
            "wind_wave_direction": [290.0],
            "sea_surface_temperature": [17.5]
          }
        }
        """
        let errorJSON = """
        {"error": true, "reason": "Wind endpoint unavailable"}
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            if host == "api.open-meteo.com" {
                return (self.makeResponse(url: url, statusCode: 503), Data(errorJSON.utf8))
            }
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        let snapshot = try await SurfConditionsService.fetch(
            start: start,
            durationMinutes: 60,
            latitude: 33.3,
            longitude: -117.6,
            session: session
        )

        XCTAssertTrue(snapshot.hasWaveReadings)
        XCTAssertFalse(snapshot.hasWindReadings)
        XCTAssertEqual(snapshot.waveHeightMeters ?? 0, 1.4, accuracy: 0.01)
        XCTAssertNil(snapshot.windSpeedKph)
    }

    func testFetchThrowsNoDataWhenAllValuesNil() async {
        let start = makeRecentGMTDate()
        let hour = hourString(start)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["\(hour)"],
            "wave_height": [null],
            "swell_wave_height": [null],
            "swell_wave_period": [null],
            "swell_wave_direction": [null],
            "wind_wave_height": [null],
            "wind_wave_period": [null],
            "wind_wave_direction": [null],
            "sea_surface_temperature": [null]
          }
        }
        """
        let windJSON = """
        {
          "hourly": {
            "time": ["\(hour)"],
            "wind_speed_10m": [null],
            "wind_direction_10m": [null]
          }
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            if host == "api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(windJSON.utf8))
            }
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        do {
            _ = try await SurfConditionsService.fetch(
                start: start,
                durationMinutes: 60,
                latitude: 33.3,
                longitude: -117.6,
                session: session
            )
            XCTFail("Expected no data error")
        } catch let error as SurfConditionsError {
            guard case .noDataAvailable = error else {
                XCTFail("Expected noDataAvailable but got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchThrowsOutOfRange() async {
        let start = Date().addingTimeInterval(-120 * 24 * 60 * 60)

        let session = makeSession()
        do {
            _ = try await SurfConditionsService.fetch(
                start: start,
                durationMinutes: 60,
                latitude: 33.3,
                longitude: -117.6,
                session: session
            )
            XCTFail("Expected out-of-range error")
        } catch let error as SurfConditionsError {
            guard case .outOfRange = error else {
                XCTFail("Expected outOfRange but got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Inverted from `testFetchIncludesPastAndForecastQueryItems`, and the
    /// inversion is the fix rather than a weakened assertion.
    ///
    /// Open-Meteo rejects `past_days` / `forecast_days` outright when the request
    /// also carries an explicit range, and `start_hour` / `end_hour` count as
    /// one: "Parameter 'forecast_days' is mutually exclusive with 'start_date'
    /// and 'end_date'", HTTP 400, no data. Peak sent both together on every
    /// request that reached outside today, which meant auto-fill failed for any
    /// session not logged the same day and the Best Window fetch — a 24-hour span
    /// from now, so always across midnight — failed every single time. The range
    /// is fully specified by the hours, so the day counts must not be sent.
    func testFetchDoesNotSendDayCountsAlongsideAnExplicitHourRange() async throws {
        let start = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        let durationMinutes = 60 * 24 * 5

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timeString = formatter.string(from: start)

        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["\(timeString)"],
            "wave_height": [1.2],
            "swell_wave_height": [1.1],
            "swell_wave_period": [12.0],
            "swell_wave_direction": [270.0],
            "wind_wave_height": [0.6],
            "wind_wave_period": [6.0],
            "wind_wave_direction": [300.0],
            "sea_surface_temperature": [18.0]
          }
        }
        """
        let windJSON = """
        {
          "hourly": {
            "time": ["\(timeString)"],
            "wind_speed_10m": [12.0],
            "wind_direction_10m": [280.0]
          }
        }
        """

        var requestURLs: [URL] = []
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            requestURLs.append(url)
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            if host == "api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(windJSON.utf8))
            }
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        _ = try await SurfConditionsService.fetch(
            start: start,
            durationMinutes: durationMinutes,
            latitude: 33.3,
            longitude: -117.6,
            session: session
        )

        let marineURL = requestURLs.first { $0.host == "marine-api.open-meteo.com" }
        let windURL = requestURLs.first { $0.host == "api.open-meteo.com" }

        let marineItems = marineURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let windItems = windURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []

        for (label, items) in [("marine", marineItems), ("wind", windItems)] {
            XCTAssertNil(items.first { $0.name == "past_days" },
                         "\(label) request still sends past_days, which the provider rejects")
            XCTAssertNil(items.first { $0.name == "forecast_days" },
                         "\(label) request still sends forecast_days, which the provider rejects")
            // The range still has to be pinned — dropping the day counts must not
            // turn into dropping the bounds.
            XCTAssertNotNil(items.first { $0.name == "start_hour" }, "\(label) request lost its start_hour")
            XCTAssertNotNil(items.first { $0.name == "end_hour" }, "\(label) request lost its end_hour")
        }

        // A session snapshot is about an hour that has already happened, so it has
        // no business asking for sunrise and sunset.
        XCTAssertNil(windItems.first { $0.name == "daily" },
                     "the session-snapshot request asked for daily data it does not use")
    }

    func testFetchReturnsPartialWhenMarineFails() async throws {
        let start = makeRecentGMTDate()
        let windTime = hourStringWithZone(start, includeSeconds: true)
        let errorJSON = """
        {"error": true, "reason": "Marine endpoint unavailable"}
        """
        let windJSON = """
        {
          "hourly": {
            "time": ["\(windTime)"],
            "wind_speed_10m": [9.0],
            "wind_direction_10m": [250.0]
          }
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url, statusCode: 503), Data(errorJSON.utf8))
            }
            if host == "api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(windJSON.utf8))
            }
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        let snapshot = try await SurfConditionsService.fetch(
            start: start,
            durationMinutes: 60,
            latitude: 33.3,
            longitude: -117.6,
            session: session
        )

        XCTAssertTrue(snapshot.hasWindReadings)
        XCTAssertFalse(snapshot.hasWaveReadings)
        XCTAssertEqual(snapshot.windSpeedKph ?? 0, 9.0, accuracy: 0.01)
    }

    func testFetchThrowsNoMatchingHoursWhenTimesEmpty() async {
        let start = makeRecentGMTDate()
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": [],
            "wave_height": [],
            "swell_wave_height": [],
            "swell_wave_period": [],
            "swell_wave_direction": [],
            "wind_wave_height": [],
            "wind_wave_period": [],
            "wind_wave_direction": [],
            "sea_surface_temperature": []
          }
        }
        """
        let windJSON = """
        {
          "hourly": {
            "time": [],
            "wind_speed_10m": [],
            "wind_direction_10m": []
          }
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            if host == "api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(windJSON.utf8))
            }
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let session = makeSession()
        do {
            _ = try await SurfConditionsService.fetch(
                start: start,
                durationMinutes: 60,
                latitude: 33.3,
                longitude: -117.6,
                session: session
            )
            XCTFail("Expected noMatchingHours error")
        } catch let error as SurfConditionsError {
            guard case .noMatchingHours = error else {
                XCTFail("Expected noMatchingHours but got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Tide

    func testFetchParsesSeaLevelAndDerivesFallingTide() async throws {
        let start = makeRecentGMTDate(hour: 10)
        // A clean falling limb through the session window, with the padded context
        // hours either side that the real request now asks for.
        let hours = (-3...4).map { start.addingTimeInterval(Double($0) * 3600) }
        let levels = [0.85, 0.80, 0.65, 0.42, 0.15, -0.15, -0.45, -0.68]
        let times = hours.map { hourString($0) }.map { "\"\($0)\"" }.joined(separator: ",")
        let levelList = levels.map { String($0) }.joined(separator: ",")
        let nulls = Array(repeating: "null", count: levels.count).joined(separator: ",")

        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": [\(times)],
            "wave_height": [\(nulls)],
            "swell_wave_height": [\(nulls)],
            "swell_wave_period": [\(nulls)],
            "swell_wave_direction": [\(nulls)],
            "wind_wave_height": [\(nulls)],
            "wind_wave_period": [\(nulls)],
            "wind_wave_direction": [\(nulls)],
            "sea_surface_temperature": [\(nulls)],
            "sea_level_height_msl": [\(levelList)]
          }
        }
        """
        let windJSON = """
        {"hourly": {"time": [], "wind_speed_10m": [], "wind_direction_10m": []}}
        """

        var marineURL: URL?
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else { throw URLError(.badURL) }
            if host == "marine-api.open-meteo.com" {
                marineURL = url
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            return (self.makeResponse(url: url), Data(windJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let snapshot = try await SurfConditionsService.fetch(
            start: start,
            durationMinutes: 60,
            latitude: 33.3,
            longitude: -117.6,
            session: makeSession()
        )

        // Sea level averages over the SESSION window only (10:00 and 11:00), never
        // over the padded context hours.
        XCTAssertEqual(snapshot.seaLevelHeightMeters ?? 0, (0.42 + 0.15) / 2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.tideTrend, .falling)
        XCTAssertTrue(snapshot.hasWaveReadings, "tide alone should count as a wave reading")

        let items = marineURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let hourly = items.first { $0.name == "hourly" }?.value ?? ""
        XCTAssertTrue(hourly.contains("sea_level_height_msl"), "marine request did not ask for sea level: \(hourly)")
    }

    func testDeriveTideTrendReadsRisingAndFallingLimbs() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let times = (0..<8).map { base.addingTimeInterval(Double($0) * 3600) }

        let rising: [Double?] = [-0.8, -0.6, -0.3, 0.05, 0.35, 0.6, 0.75, 0.8]
        XCTAssertEqual(
            SurfConditionsService.deriveTideTrend(times: times, levels: rising, around: times[3]),
            .rising
        )

        let falling: [Double?] = rising.reversed()
        XCTAssertEqual(
            SurfConditionsService.deriveTideTrend(times: times, levels: falling, around: times[3]),
            .falling
        )
    }

    /// Near a turn the slope flattens, and that is a materially different thing to
    /// tell a surfer than "rising" — a spot that only works on a pushing tide is
    /// already done when the tide is standing at the top.
    func testDeriveTideTrendReadsTurningPointsAsHighAndLow() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // One full semi-diurnal cycle sampled hourly, peak at index 3.
        let times = (0..<13).map { base.addingTimeInterval(Double($0) * 3600) }
        let levels: [Double?] = (0..<13).map { i in
            0.9 * cos(2 * Double.pi * (Double(i) - 3) / 12.42)
        }

        XCTAssertEqual(SurfConditionsService.deriveTideTrend(times: times, levels: levels, around: times[3]), .high)
        XCTAssertEqual(SurfConditionsService.deriveTideTrend(times: times, levels: levels, around: times[9]), .low)
        XCTAssertEqual(SurfConditionsService.deriveTideTrend(times: times, levels: levels, around: times[6]), .falling)
        XCTAssertEqual(SurfConditionsService.deriveTideTrend(times: times, levels: levels, around: times[0]), .rising)
    }

    func testDeriveTideTrendReturnsNilRatherThanGuessing() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let times = (0..<6).map { base.addingTimeInterval(Double($0) * 3600) }

        // No series at all.
        XCTAssertNil(SurfConditionsService.deriveTideTrend(times: times, levels: nil, around: times[2]))
        // Every value missing.
        XCTAssertNil(SurfConditionsService.deriveTideTrend(
            times: times, levels: Array(repeating: nil, count: 6), around: times[2]))
        // A single usable sample cannot produce a slope.
        XCTAssertNil(SurfConditionsService.deriveTideTrend(
            times: times, levels: [nil, nil, 0.4, nil, nil, nil], around: times[2]))
        // Dead flat: no tide signal, so no claim. Better than reporting "high"
        // because the level happens to sit at its own maximum.
        XCTAssertNil(SurfConditionsService.deriveTideTrend(
            times: times, levels: Array(repeating: 0.3, count: 6), around: times[2]))
        // Non-finite values are corrupt, not data.
        XCTAssertNil(SurfConditionsService.deriveTideTrend(
            times: times, levels: [.nan, .infinity, -.infinity, .nan, nil, nil], around: times[2]))
    }

    func testDeriveTideTrendHandlesUnsortedSeriesAndNegativeLevels() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let times = (0..<6).map { base.addingTimeInterval(Double($0) * 3600) }
        let levels: [Double?] = [-1.4, -1.1, -0.7, -0.25, 0.2, 0.6]

        // Provider order should not matter: the derivation sorts by time.
        let forward = SurfConditionsService.deriveTideTrend(times: times, levels: levels, around: times[2])
        let reversed = SurfConditionsService.deriveTideTrend(
            times: times.reversed(), levels: levels.reversed(), around: times[2])
        XCTAssertEqual(forward, .rising)
        XCTAssertEqual(reversed, .rising, "reversing the provider's series changed the answer")
    }

    func testTideSeriesReuseMatchesPerCallDerivation() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let times = (0..<13).map { base.addingTimeInterval(Double($0) * 3600) }
        let levels: [Double?] = (0..<13).map { i in
            0.9 * cos(2 * Double.pi * (Double(i) - 3) / 12.42)
        }
        let series = try XCTUnwrap(SurfConditionsService.tideSeries(times: times, levels: levels))

        for time in times {
            XCTAssertEqual(
                SurfConditionsService.deriveTideTrend(from: series, around: time),
                SurfConditionsService.deriveTideTrend(times: times, levels: levels, around: time)
            )
        }
    }

    /// Missing sea level must not break the rest of the snapshot — the marine
    /// endpoint returns it as a separate array and can omit it entirely.
    func testFetchSucceedsWhenSeaLevelIsAbsent() async throws {
        let start = makeRecentGMTDate()
        let hour = hourString(start)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["\(hour)"],
            "wave_height": [1.3],
            "swell_wave_height": [1.1],
            "swell_wave_period": [11.0],
            "swell_wave_direction": [270.0],
            "wind_wave_height": [0.5],
            "wind_wave_period": [5.0],
            "wind_wave_direction": [290.0],
            "sea_surface_temperature": [17.0]
          }
        }
        """
        let windJSON = """
        {"hourly": {"time": ["\(hour)"], "wind_speed_10m": [10.0], "wind_direction_10m": [250.0]}}
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, let host = url.host else { throw URLError(.badURL) }
            if host == "marine-api.open-meteo.com" {
                return (self.makeResponse(url: url), Data(marineJSON.utf8))
            }
            return (self.makeResponse(url: url), Data(windJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let snapshot = try await SurfConditionsService.fetch(
            start: start, durationMinutes: 60, latitude: 33.3, longitude: -117.6, session: makeSession()
        )

        XCTAssertNil(snapshot.seaLevelHeightMeters)
        XCTAssertNil(snapshot.tideTrend)
        XCTAssertEqual(snapshot.waveHeightMeters ?? 0, 1.3, accuracy: 0.01)
    }
}

/// NOAA CO-OPS is the *optional* precision layer. The behaviour that matters most
/// is what it does when it cannot help: a spot outside US coverage must fall back
/// to the Open-Meteo curve silently, never surface an error, and never adopt a
/// distant American gauge as if it described the local water.
final class TideServiceTests: XCTestCase {

    // Real-ish coordinates for well-known gauges.
    private let sanDiego = TideService.Station(id: "9410170", name: "San Diego", latitude: 32.7133, longitude: -117.1733)
    private let laJolla = TideService.Station(id: "9410230", name: "La Jolla", latitude: 32.8669, longitude: -117.2571)
    private let santaMonica = TideService.Station(id: "9410840", name: "Santa Monica", latitude: 34.0083, longitude: -118.5)
    private let lisbon = TideService.Station(id: "0000001", name: "Fictional Lisbon gauge", latitude: 38.7, longitude: -9.4)

    // MARK: Station selection

    func testNearestStationPicksTheClosestWithinRange() throws {
        let stations = [santaMonica, sanDiego, laJolla]
        // Black's Beach, a few km from the La Jolla gauge.
        let match = try XCTUnwrap(TideService.nearestStation(in: stations, latitude: 32.8886, longitude: -117.2519))
        XCTAssertEqual(match.station.id, laJolla.id)
        XCTAssertLessThan(match.distanceKm, 10)
    }

    func testNonUSSpotResolvesToNoStationRatherThanADistantOne() {
        // Ericeira, Portugal. The only stations on offer are in California; every
        // one is thousands of km away and none of them describes this water.
        let stations = [santaMonica, sanDiego, laJolla]
        XCTAssertNil(
            TideService.nearestStation(in: stations, latitude: 38.9631, longitude: -9.4186),
            "a Portuguese spot adopted a Californian tide gauge"
        )
    }

    func testStationBeyondTheDistanceCutIsRejected() {
        // Just outside the cut in one direction, just inside in the other, so the
        // boundary itself is exercised rather than a comfortable margin.
        let far = TideService.Station(id: "9999999", name: "Far", latitude: 34.0, longitude: -120.0)
        let justInside = 0.9 * TideService.maxStationDistanceKm
        let insideLatitude = far.latitude + justInside / 111.0

        XCTAssertNil(
            TideService.nearestStation(in: [far], latitude: far.latitude + 3.0, longitude: far.longitude),
            "accepted a station over \(TideService.maxStationDistanceKm) km away"
        )
        XCTAssertNotNil(
            TideService.nearestStation(in: [far], latitude: insideLatitude, longitude: far.longitude),
            "rejected a station comfortably inside the cut"
        )
    }

    func testNearestStationHandlesEmptyAndCorruptInput() {
        XCTAssertNil(TideService.nearestStation(in: [], latitude: 32.8, longitude: -117.2))
        XCTAssertNil(TideService.nearestStation(in: [laJolla], latitude: .nan, longitude: -117.2))
        XCTAssertNil(TideService.nearestStation(in: [laJolla], latitude: 32.8, longitude: .infinity))
    }

    func testDistanceWrapsAcrossTheAntimeridian() {
        // -179.5 and +179.5 are 1 degree apart, not 359.
        let wrapped = TideService.distanceKm(
            fromLatitude: 0, longitude: -179.5, toLatitude: 0, longitude: 179.5)
        XCTAssertLessThan(wrapped, 130, "antimeridian was not wrapped: \(wrapped) km")
        XCTAssertGreaterThan(wrapped, 100)
    }

    // MARK: Parsing

    func testParseStationsSkipsRowsWithoutUsableCoordinates() throws {
        let json = """
        {"count": 4, "stations": [
          {"id": "9410230", "name": "La Jolla", "lat": 32.8669, "lng": -117.2571},
          {"id": "9410170", "name": "San Diego", "lat": 32.7133, "lng": -117.1733},
          {"id": "  ", "name": "Blank id", "lat": 1.0, "lng": 2.0},
          {"id": "9999999", "name": "No coordinates"}
        ]}
        """
        let stations = try TideService.parseStations(Data(json.utf8))
        XCTAssertEqual(stations.map(\.id), ["9410230", "9410170"])
        XCTAssertEqual(stations.first?.name, "La Jolla")
        XCTAssertEqual(stations.first?.latitude ?? 0, 32.8669, accuracy: 0.0001)
    }

    func testParsePredictionsReadsHighsAndLowsInOrder() throws {
        // NOAA sends heights as strings and marks each row H or L. Deliberately
        // supplied out of order, with one unusable row.
        let json = """
        {"predictions": [
          {"t": "2026-07-20 15:12", "v": "0.213", "type": "L"},
          {"t": "2026-07-20 09:04", "v": "1.612", "type": "H"},
          {"t": "2026-07-20 21:47", "v": "1.402", "type": "h"},
          {"t": "2026-07-20 12:00", "v": "not-a-number", "type": "H"},
          {"t": "garbage", "v": "1.0", "type": "L"},
          {"t": "2026-07-20 18:30", "v": "0.9", "type": "X"}
        ]}
        """
        let extremes = try TideService.parsePredictions(Data(json.utf8))

        XCTAssertEqual(extremes.count, 3, "expected 3 usable rows, got \(extremes.map(\.heightMeters))")
        XCTAssertTrue(extremes.map(\.date) == extremes.map(\.date).sorted(), "predictions were not sorted")
        XCTAssertEqual(extremes[0].heightMeters, 1.612, accuracy: 0.0001)
        XCTAssertTrue(extremes[0].isHigh)
        XCTAssertFalse(extremes[1].isHigh)
        // Lower-case "h" is still a high; an unknown marker like "X" is dropped.
        XCTAssertTrue(extremes[2].isHigh)
    }

    func testParsingSurfacesNOAAErrorPayloads() {
        let json = """
        {"error": {"message": "No Predictions data was found."}}
        """
        XCTAssertThrowsError(try TideService.parsePredictions(Data(json.utf8))) { error in
            guard case TideServiceError.remoteError(let reason) = error else {
                return XCTFail("expected remoteError, got \(error)")
            }
            XCTAssertEqual(reason, "No Predictions data was found.")
        }
        XCTAssertThrowsError(try TideService.parseStations(Data(json.utf8)))
        XCTAssertThrowsError(try TideService.parsePredictions(Data("not json".utf8)))
    }

    // MARK: URLs

    func testPredictionsURLRequestsHiLoPredictionsInMetric() throws {
        let start = Date(timeIntervalSince1970: 1_753_000_000)
        let url = try TideService.makePredictionsURL(
            stationId: "9410230", start: start, end: start.addingTimeInterval(86_400))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "api.tidesandcurrents.noaa.gov")
        XCTAssertEqual(value("station"), "9410230")
        XCTAssertEqual(value("interval"), "hilo")
        XCTAssertEqual(value("units"), "metric")
        XCTAssertEqual(value("time_zone"), "gmt")
        XCTAssertEqual(value("datum"), "MLLW")
        XCTAssertEqual(value("format"), "json")
        // No API key, no account, and nothing identifying the user.
        XCTAssertNil(value("token"))
        XCTAssertNil(value("key"))
    }

    func testPredictionsURLOrdersReversedDatesRatherThanFailing() throws {
        let start = Date(timeIntervalSince1970: 1_753_000_000)
        let url = try TideService.makePredictionsURL(
            stationId: "9410230", start: start.addingTimeInterval(86_400), end: start)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let begin = items.first { $0.name == "begin_date" }?.value ?? ""
        let end = items.first { $0.name == "end_date" }?.value ?? ""
        XCTAssertLessThanOrEqual(begin, end, "begin_date \(begin) came after end_date \(end)")
    }

    func testBlankStationIdIsRejected() {
        XCTAssertThrowsError(try TideService.makePredictionsURL(
            stationId: "   ", start: Date(), end: Date()))
    }

    // MARK: Station caching

    /// The whole point of caching the id on the Spot: resolving must not touch the
    /// network when a station is already known. The mock session fails any request,
    /// so a single call would fail this test.
    func testCachedStationIdSkipsTheNetworkEntirely() async {
        var requestCount = 0
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let resolved = await TideService.resolveStationId(
            cached: "9410230", latitude: 32.8669, longitude: -117.2571, session: makeSession())

        XCTAssertEqual(resolved, "9410230")
        XCTAssertEqual(requestCount, 0, "a cached station id still hit the network \(requestCount) time(s)")
    }

    func testBlankCachedIdFallsThroughToLookup() async {
        let json = """
        {"count": 1, "stations": [{"id": "9410230", "name": "La Jolla", "lat": 32.8669, "lng": -117.2571}]}
        """
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let resolved = await TideService.resolveStationId(
            cached: "   ", latitude: 32.8669, longitude: -117.2571, session: makeSession())
        XCTAssertEqual(resolved, "9410230", "a whitespace-only cached id was treated as a real station")
    }

    /// A failing lookup is not an error the surfer should ever see; it just means
    /// the Open-Meteo curve stays in charge.
    func testLookupFailureResolvesToNilWithoutThrowing() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        defer { MockURLProtocol.requestHandler = nil }

        let resolved = await TideService.resolveStationId(
            cached: nil, latitude: 32.8669, longitude: -117.2571, session: makeSession())
        XCTAssertNil(resolved)
    }

    func testNonUSLookupResolvesToNilAgainstARealStationList() async {
        let json = """
        {"count": 2, "stations": [
          {"id": "9410230", "name": "La Jolla", "lat": 32.8669, "lng": -117.2571},
          {"id": "9410170", "name": "San Diego", "lat": 32.7133, "lng": -117.1733}
        ]}
        """
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        // Ericeira, Portugal.
        let resolved = await TideService.resolveStationId(
            cached: nil, latitude: 38.9631, longitude: -9.4186, session: makeSession())
        XCTAssertNil(resolved, "resolved a Californian station for a Portuguese spot")
        XCTAssertNotNil(lisbon)  // keeps the fixture referenced and the intent readable
    }

    func testEndToEndPredictionsFetchParsesRealShapedResponse() async throws {
        let json = """
        {"predictions": [
          {"t": "2026-07-20 03:31", "v": "1.612", "type": "H"},
          {"t": "2026-07-20 10:02", "v": "0.152", "type": "L"}
        ]}
        """
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let start = Date(timeIntervalSince1970: 1_753_000_000)
        let extremes = try await TideService.predictions(
            stationId: "9410230", start: start, end: start.addingTimeInterval(86_400), session: makeSession())

        XCTAssertEqual(extremes.count, 2)
        XCTAssertTrue(extremes[0].isHigh)
        XCTAssertEqual(extremes[0].heightMeters, 1.612, accuracy: 0.0001)
        XCTAssertLessThan(extremes[0].date, extremes[1].date)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private extension SurfConditionsServiceTests {
    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func makeResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    func makeRecentGMTDate(hour: Int = 10, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let base = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let components = calendar.dateComponents([.year, .month, .day], from: base)
        return calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: hour,
            minute: minute
        ))!
    }

    func hourString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }

    func hourStringWithZone(_ date: Date, includeSeconds: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = includeSeconds ? "yyyy-MM-dd'T'HH:mm:ss'Z'" : "yyyy-MM-dd'T'HH:mm'Z'"
        return formatter.string(from: date)
    }
}
