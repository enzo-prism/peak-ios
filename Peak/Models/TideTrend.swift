import Foundation

/// Direction of tidal movement over a session or forecast hour.
///
/// Stored on `SurfSession` as a raw `String?` rather than as a SwiftData enum
/// column: an optional string keeps the V8 -> V9 delta purely additive, and a
/// value written by a future release that this build does not know about decodes
/// to `nil` instead of corrupting the row.
///
/// The four cases form a *cycle* — rising -> high -> falling -> low -> rising —
/// and `WindowScorer` relies on that: `rising` is genuinely closer to `high` than
/// to `falling`, because the tide passes through high on the way.
nonisolated enum TideTrend: String, Codable, Sendable, Hashable, CaseIterable {
    case rising
    case high
    case falling
    case low

    /// Sentence-case label for the surf report and the window card.
    var label: String {
        switch self {
        case .rising: return "Rising tide"
        case .high: return "High tide"
        case .falling: return "Falling tide"
        case .low: return "Low tide"
        }
    }

    /// Lower-case phrase for mid-sentence use ("... , dropping tide").
    var phrase: String {
        switch self {
        case .rising: return "rising tide"
        case .high: return "high tide"
        case .falling: return "falling tide"
        case .low: return "low tide"
        }
    }
}
