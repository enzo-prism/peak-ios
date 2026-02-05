import XCTest

@testable import Peak

final class SurfConditionsFormatterTests: XCTestCase {
    func testDirectionFormattingUsesCompassLabels() {
        XCTAssertEqual(SurfConditionsFormatter.direction(0), "N (0 deg)")
        XCTAssertEqual(SurfConditionsFormatter.direction(45), "NE (45 deg)")
        XCTAssertEqual(SurfConditionsFormatter.direction(90), "E (90 deg)")
        XCTAssertEqual(SurfConditionsFormatter.direction(225), "SW (225 deg)")
        XCTAssertEqual(SurfConditionsFormatter.direction(359), "N (359 deg)")
    }

    func testCompactSummaryOutputsExpectedParts() {
        let both = SurfConditionsFormatter.compactSummary(waveHeightMeters: 1.04, windSpeedKph: 10.4)
        XCTAssertEqual(both, "1.0 m waves | 10 km/h wind")

        let wavesOnly = SurfConditionsFormatter.compactSummary(waveHeightMeters: 0.6, windSpeedKph: nil)
        XCTAssertEqual(wavesOnly, "0.6 m waves")

        let none = SurfConditionsFormatter.compactSummary(waveHeightMeters: nil, windSpeedKph: nil)
        XCTAssertNil(none)
    }
}
