import Foundation

enum SurfConditionsFormatter {
    static func speed(_ value: Double) -> String {
        let rounded = Double(Int(value.rounded()))
        return String(format: "%.0f km/h", rounded)
    }

    static func meters(_ value: Double) -> String {
        String(format: "%.1f m", value)
    }

    static func period(_ value: Double) -> String {
        let rounded = Double(Int(value.rounded()))
        return String(format: "%.0f s", rounded)
    }

    static func temperature(_ value: Double) -> String {
        String(format: "%.1f C", value)
    }

    static func direction(_ degrees: Double) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45.0)
        let label = labels[min(max(index, 0), labels.count - 1)]
        let rounded = Int(normalized.rounded())
        return "\(label) (\(rounded) deg)"
    }

    static func compactSummary(waveHeightMeters: Double?, windSpeedKph: Double?) -> String? {
        var parts: [String] = []
        if let waveHeightMeters {
            parts.append("\(meters(waveHeightMeters)) waves")
        }
        if let windSpeedKph {
            parts.append("\(speed(windSpeedKph)) wind")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " | ")
    }
}
