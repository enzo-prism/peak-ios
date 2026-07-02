import Foundation

/// Small display + VoiceOver formatting helpers shared across the Stats 2.0
/// cards. Pure functions, cheap to call from a view body.
enum StatsFormat {
    /// Compact duration label, e.g. "87h", "1h 25m", "45m".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    /// Spoken duration for accessibility, e.g. "1 hour 25 minutes".
    static func spokenDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if mins > 0 { parts.append("\(mins) minute\(mins == 1 ? "" : "s")") }
        return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
    }

    /// Spoken week count, e.g. "1 week", "3 weeks".
    static func spokenWeeks(_ weeks: Int) -> String {
        "\(weeks) week\(weeks == 1 ? "" : "s")"
    }

    /// One-decimal rating, e.g. "4.2".
    static func rating(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
