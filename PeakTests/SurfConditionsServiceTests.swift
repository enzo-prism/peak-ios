import Foundation
import XCTest

@testable import Peak

final class SurfConditionsServiceTests: XCTestCase {
    override class var supportsParallelExecution: Bool { false }

    func testFetchParsesISO8601TimesWithTimezone() async throws {
        let start = makeGMTDate(year: 2026, month: 2, day: 4, hour: 10, minute: 0)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["2026-02-04T10:00Z"],
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
            "time": ["2026-02-04T10:00:00Z"],
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
        let start = makeGMTDate(year: 2026, month: 2, day: 4, hour: 10, minute: 0)
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
        let start = makeGMTDate(year: 2026, month: 2, day: 4, hour: 10, minute: 0)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["2026-02-04T10:00"],
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
        let start = makeGMTDate(year: 2026, month: 2, day: 4, hour: 10, minute: 0)
        let marineJSON = """
        {
          "latitude": 33.3,
          "longitude": -117.6,
          "hourly": {
            "time": ["2026-02-04T10:00"],
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
            "time": ["2026-02-04T10:00"],
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

    func makeGMTDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
