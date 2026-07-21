import Foundation

// `nonisolated`: these are pure functions of the string itself with no actor
// state, and the target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
// which would otherwise pin them to the main actor and make them unusable from
// the `@concurrent` networking paths (TideService, SurfConditionsService).
nonisolated extension String {
    var normalizedKey: String {
        let parts = components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ").lowercased()
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Case- and diacritic-insensitive form for matching user-typed queries against catalog text
    /// (so "sao", "São" and "SÃO" all match).
    var searchFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }
}
