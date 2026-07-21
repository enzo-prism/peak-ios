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

    func testSeaLevelAlwaysCarriesItsSign() {
        // The sign is the information: "-0.4 m" means below mean sea level.
        XCTAssertEqual(normalized(SurfConditionsFormatter.seaLevel(0.4, locale: metricLocale)), "+0.4 m")
        XCTAssertEqual(normalized(SurfConditionsFormatter.seaLevel(-0.4, locale: metricLocale)), "\u{2212}0.4 m")
        XCTAssertEqual(normalized(SurfConditionsFormatter.seaLevel(0, locale: metricLocale)), "+0.0 m")
        // A real minus sign, not a hyphen.
        XCTAssertFalse(SurfConditionsFormatter.seaLevel(-0.4, locale: metricLocale).contains("-"))
    }

    func testTideRowDegradesGracefullyWhenHalfTheDataIsMissing() {
        XCTAssertEqual(
            normalized(SurfConditionsFormatter.tide(trend: .falling, seaLevelMeters: -0.3, locale: metricLocale)),
            "Falling tide (\u{2212}0.3 m from mean)"
        )
        XCTAssertEqual(
            SurfConditionsFormatter.tide(trend: .high, seaLevelMeters: nil, locale: metricLocale),
            "High tide"
        )
        XCTAssertEqual(
            normalized(SurfConditionsFormatter.tide(trend: nil, seaLevelMeters: 0.6, locale: metricLocale)),
            "+0.6 m from mean"
        )
        XCTAssertNil(SurfConditionsFormatter.tide(trend: nil, seaLevelMeters: nil, locale: metricLocale))
    }

    /// The copy must never imply chart-datum precision the modelled MSL curve
    /// cannot support: no clock times, no "high tide at", no datum names.
    func testTideCopyClaimsNoPrecisionItDoesNotHave() {
        let text = SurfConditionsFormatter.tide(trend: .high, seaLevelMeters: 1.7, locale: metricLocale) ?? ""
        for forbidden in [":", "at ", "MLLW", "datum", "chart"] {
            XCTAssertFalse(text.contains(forbidden), "tide copy '\(text)' implies precision via '\(forbidden)'")
        }
        XCTAssertTrue(text.contains("from mean"), "tide copy should say what it is relative to: \(text)")
    }

    func testCompactSummaryIncludesTideWhenPresent() {
        let summary = SurfConditionsFormatter.compactSummary(
            waveHeightMeters: 1.2,
            windSpeedKph: 10,
            tideTrend: .falling,
            locale: metricLocale
        )
        XCTAssertEqual(normalized(summary), "1.2 m waves | 10 km/h wind | falling tide")

        // Tide is optional and the summary still works without it.
        XCTAssertEqual(
            normalized(SurfConditionsFormatter.compactSummary(
                waveHeightMeters: 1.2, windSpeedKph: 10, locale: metricLocale)),
            "1.2 m waves | 10 km/h wind"
        )
        XCTAssertEqual(
            SurfConditionsFormatter.compactSummary(
                waveHeightMeters: nil, windSpeedKph: nil, tideTrend: .rising, locale: metricLocale),
            "rising tide"
        )
        XCTAssertNil(SurfConditionsFormatter.compactSummary(
            waveHeightMeters: nil, windSpeedKph: nil, locale: metricLocale))
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
