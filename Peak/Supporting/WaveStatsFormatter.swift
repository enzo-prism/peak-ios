import Foundation

/// Display formatting for the 3.0 wave statistics.
///
/// Follows `SurfConditionsFormatter`'s rule: values are stored metric and
/// converted to the user's locale units at the last possible moment, so a US
/// surfer reads "17 mph" and "92 ft" while the stored numbers stay comparable
/// across the whole logbook.
///
/// Everything here is deliberately terse — these strings live in hero tags and
/// stat tiles where a long label wraps badly at accessibility text sizes.
enum WaveStatsFormatter {

    /// "8 waves" / "1 wave". Zero is a real answer (a skunked session is still a
    /// session), so it is spelled out rather than suppressed.
    static func waveCount(_ count: Int) -> String {
        "\(count) wave\(count == 1 ? "" : "s")"
    }

    /// Bare numeral for a tile whose caption already says "waves".
    static func waveCountValue(_ count: Int) -> String {
        "\(count)"
    }

    /// Top speed in the locale's speed unit, e.g. "24 km/h" or "15 mph".
    static func speed(_ kilometersPerHour: Double, locale: Locale = .autoupdatingCurrent) -> String {
        SurfConditionsFormatter.speed(kilometersPerHour, locale: locale)
    }

    /// Ride length in the locale's length unit, e.g. "84 m" or "276 ft".
    ///
    /// Whole units only: the analyzer's distance is good to a few metres at best,
    /// and "83.7 m" claims a precision the GPS never had.
    static func distance(_ meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit: UnitLength = locale.measurementSystem == .metric ? .meters : .feet
        let measurement = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
            .locale(locale)
        )
    }

    /// Ride duration, e.g. "12s" or "1m 04s". Seconds matter here — the whole
    /// point of a long ride is that it was long.
    static func rideDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0s" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainder)
        }
        return "\(total)s"
    }

    /// Spoken form for VoiceOver, which must not read "12s" as "twelve ess".
    static func spokenRideDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if remainder > 0 { parts.append("\(remainder) second\(remainder == 1 ? "" : "s")") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// One-line summary for the import preview and the share card, e.g.
    /// "8 waves · top 24 km/h · longest 18s".
    ///
    /// Returns `nil` when there is nothing worth saying, so callers can omit the
    /// row entirely rather than render an empty separator.
    static func summary(
        waveCount: Int?,
        topSpeedKph: Double?,
        longestRideSeconds: Double?,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        var parts: [String] = []
        if let waveCount { parts.append(self.waveCount(waveCount)) }
        if let topSpeedKph, topSpeedKph > 0 { parts.append("top \(speed(topSpeedKph, locale: locale))") }
        if let longestRideSeconds, longestRideSeconds > 0 {
            parts.append("longest \(rideDuration(longestRideSeconds))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Microcopy

    /// The line that must accompany any automatically-derived figure.
    ///
    /// This is a product requirement, not decoration. Wave detection from a wrist
    /// GPS is roughly 85% exact and 98.5% within one wave under good conditions,
    /// and materially worse when the watch reports no Doppler speed. Competitor
    /// apps' single largest source of one-star reviews is a confidently wrong
    /// wave count, so Peak states the uncertainty everywhere the number appears
    /// and makes correcting it a two-tap operation.
    static let estimateCaption = "Estimated from your Apple Watch route — tap to correct"

    /// Same promise, phrased for a screen where tapping is not the affordance
    /// (the import preview, where the action is "Import").
    static let estimatePreviewCaption = "Estimates from the workout's GPS route. You can correct them after importing."

    /// Editor footer for a session with no workout behind it.
    static let manualCaption = "No Apple Watch route for this session — enter what you counted."
}
