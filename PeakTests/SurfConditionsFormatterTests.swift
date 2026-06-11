import XCTest

@testable import Peak

final class SurfConditionsFormatterTests: XCTestCase {
    // en_AU is a metric, English-language locale; en_US exercises the
    // imperial conversions. Both keep "." as the decimal separator so the
    // expected strings stay readable.
    private let metricLocale = Locale(identifier: "en_AU")
    private let usLocale = Locale(identifier: "en_US")

    func testDirectionFormattingUsesCompassLabels() {
        XCTAssertEqual(SurfConditionsFormatter.direction(0), "N (0°)")
        XCTAssertEqual(SurfConditionsFormatter.direction(45), "NE (45°)")
        XCTAssertEqual(SurfConditionsFormatter.direction(90), "E (90°)")
        XCTAssertEqual(SurfConditionsFormatter.direction(225), "SW (225°)")
        XCTAssertEqual(SurfConditionsFormatter.direction(359), "N (359°)")
    }

    func testCompactSummaryOutputsExpectedParts() {
        let both = SurfConditionsFormatter.compactSummary(
            waveHeightMeters: 1.04,
            windSpeedKph: 10.4,
            locale: metricLocale
        )
        XCTAssertEqual(normalized(both), "1.0 m waves | 10 km/h wind")

        let wavesOnly = SurfConditionsFormatter.compactSummary(
            waveHeightMeters: 0.6,
            windSpeedKph: nil,
            locale: metricLocale
        )
        XCTAssertEqual(normalized(wavesOnly), "0.6 m waves")

        let none = SurfConditionsFormatter.compactSummary(
            waveHeightMeters: nil,
            windSpeedKph: nil,
            locale: metricLocale
        )
        XCTAssertNil(none)
    }

    func testMetricLocaleKeepsMetricUnits() {
        XCTAssertEqual(normalized(SurfConditionsFormatter.speed(12, locale: metricLocale)), "12 km/h")
        XCTAssertEqual(normalized(SurfConditionsFormatter.meters(1.5, locale: metricLocale)), "1.5 m")
        XCTAssertEqual(normalized(SurfConditionsFormatter.temperature(13.5, locale: metricLocale)), "13.5°C")
    }

    func testUSLocaleUsesImperialUnits() {
        XCTAssertEqual(normalized(SurfConditionsFormatter.meters(1.0, locale: usLocale)), "3.3 ft")
        XCTAssertEqual(normalized(SurfConditionsFormatter.speed(16.0934, locale: usLocale)), "10 mph")
        XCTAssertEqual(normalized(SurfConditionsFormatter.temperature(20, locale: usLocale)), "68°F")
    }

    /// Measurement formatting may emit no-break or narrow no-break spaces
    /// between value and unit; normalize so assertions stay stable across
    /// ICU versions.
    private func normalized(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
