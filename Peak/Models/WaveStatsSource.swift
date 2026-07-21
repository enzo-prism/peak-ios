import Foundation

/// Where a session's wave statistics came from.
///
/// Stored on `SurfSession` as a raw `String?` for the same reason `TideTrend` is:
/// the V9 -> V10 delta stays purely additive, and a value written by a future
/// release this build does not know about decodes to `nil` rather than corrupting
/// the row.
///
/// This distinction is the whole reason the feature is safe to ship. The analyzer
/// is measurably good but not exact (roughly 85% exact wave counts, 98.5% within
/// one, with a good watch signal — worse when the watch reports no Doppler speed),
/// so an `auto` number is always presented as an estimate the surfer can correct.
/// The moment they do, the value becomes `edited` and Peak never overwrites it
/// again: a person who counted their own waves outranks a GPS trace, every time.
nonisolated enum WaveStatsSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// Derived by `WaveAnalyzer` from an Apple Watch workout route.
    case auto
    /// Derived automatically, then corrected by hand. Never re-derived.
    case edited
    /// Typed in by hand with no workout involved at all.
    case manual

    /// Short label for the detail hero and the editor footer.
    var label: String {
        switch self {
        case .auto: return "Estimated"
        case .edited: return "Edited"
        case .manual: return "Entered by you"
        }
    }

    /// The line that must appear anywhere an `auto` number is shown. Competitor
    /// surf apps' single biggest source of one-star reviews is a confidently
    /// wrong wave count, so Peak never presents these as ground truth.
    var caption: String {
        switch self {
        case .auto:
            return "Estimated from your Apple Watch route — tap to correct"
        case .edited:
            return "You corrected these numbers"
        case .manual:
            return "You entered these numbers"
        }
    }

    /// True when Peak generated the value and the user has not vouched for it.
    var isEstimate: Bool { self == .auto }
}
