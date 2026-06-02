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

    func testFetchIncludesPastAndForecastQueryItems() async throws {
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

        XCTAssertNotNil(marineItems.first { $0.name == "past_days" })
        XCTAssertNotNil(marineItems.first { $0.name == "forecast_days" })
        XCTAssertNotNil(windItems.first { $0.name == "past_days" })
        XCTAssertNotNil(windItems.first { $0.name == "forecast_days" })
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
