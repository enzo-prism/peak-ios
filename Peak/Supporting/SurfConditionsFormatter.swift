import Foundation

/// Formats Open-Meteo readings (always metric at the API boundary) in the
/// user's locale units: mph/ft/°F for US users, km/h/m/°C for metric locales.
enum SurfConditionsFormatter {
    static func speed(_ kilometersPerHour: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit = UnitSpeed(forLocale: locale, usage: .wind)
        let measurement = Measurement(value: kilometersPerHour, unit: UnitSpeed.kilometersPerHour)
        return format(measurement.converted(to: unit), locale: locale, fractionLength: 0...0)
    }

    static func meters(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit: UnitLength = locale.measurementSystem == .metric ? .meters : .feet
        let measurement = Measurement(value: value, unit: UnitLength.meters)
        return format(measurement.converted(to: unit), locale: locale, fractionLength: 1...1)
    }

    static func period(_ value: Double) -> String {
        let rounded = Double(Int(value.rounded()))
        return String(format: "%.0f s", rounded)
    }

    static func temperature(_ celsius: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit = UnitTemperature(forLocale: locale)
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        return format(measurement.converted(to: unit), locale: locale, fractionLength: 0...1)
    }

    static func direction(_ degrees: Double) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45.0)
        let label = labels[min(max(index, 0), labels.count - 1)]
        let rounded = Int(normalized.rounded())
        return "\(label) (\(rounded)°)"
    }

    static func compactSummary(
        waveHeightMeters: Double?,
        windSpeedKph: Double?,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        var parts: [String] = []
        if let waveHeightMeters {
            parts.append("\(meters(waveHeightMeters, locale: locale)) waves")
        }
        if let windSpeedKph {
            parts.append("\(speed(windSpeedKph, locale: locale)) wind")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " | ")
    }

    private static func format<UnitType: Dimension>(
        _ measurement: Measurement<UnitType>,
        locale: Locale,
        fractionLength: ClosedRange<Int>
    ) -> String {
        measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
            .locale(locale)
        )
    }
}
