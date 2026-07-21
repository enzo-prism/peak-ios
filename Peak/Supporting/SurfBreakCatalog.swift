import Foundation

/// Read-only catalog of popular surf breaks (bundled JSON), powering the Add Spot autocomplete.
/// Loaded once into a case/diacritic-folded index; search is prefix-first then contains, capped.
final class SurfBreakCatalog {
    static let shared = SurfBreakCatalog()

    private struct Indexed {
        let foldedName: String
        let foldedLocation: String
        /// Same form as `Spot.makeKey(from:)` / `String.normalizedKey` — precomputed so search
        /// never touches the SwiftData `@Model Spot` type (avoids host-test heap stress).
        let key: String
        let value: SurfBreak
    }

    private let index: [Indexed]

    init(breaks: [SurfBreak]? = nil) {
        let source = breaks ?? Self.loadBundled()
        index = source.map {
            Indexed(
                foldedName: $0.name.searchFolded,
                foldedLocation: $0.locationLabel.searchFolded,
                key: $0.name.normalizedKey,
                value: $0
            )
        }
    }

    var count: Int { index.count }

    /// Matches `raw` (>= 2 chars) against break names then locations, excluding any break the user
    /// has already saved (matched by `Spot.makeKey` / `normalizedKey`), returning at most `limit`
    /// results (name-prefix matches ranked above contains matches).
    func search(_ raw: String, limit: Int = 6, excludingKeys: Set<String> = []) -> [SurfBreak] {
        let query = raw.searchFolded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        var prefix: [SurfBreak] = []
        var contains: [SurfBreak] = []
        for entry in index {
            if !excludingKeys.isEmpty, excludingKeys.contains(entry.key) { continue }
            if entry.foldedName.hasPrefix(query) {
                prefix.append(entry.value)
                if prefix.count >= limit { break }
            } else if entry.foldedName.contains(query) || entry.foldedLocation.contains(query) {
                contains.append(entry.value)
            }
        }
        return Array((prefix + contains).prefix(limit))
    }

    /// Every catalog break whose name normalises to the same key as `name`.
    ///
    /// Uses `Spot.makeKey`'s own normalisation, so a saved spot and a catalog
    /// break agree on identity exactly where the store would consider them the
    /// same spot. Returns *all* matches rather than the first: two breaks sharing
    /// a name (there are none in the shipped 257, but nothing prevents it) make
    /// the match ambiguous, and the caller must be able to see that and decline.
    func exactMatches(name: String) -> [SurfBreak] {
        let key = name.normalizedKey
        guard !key.isEmpty else { return [] }
        return index.filter { $0.key == key }.map(\.value)
    }

    private static func loadBundled() -> [SurfBreak] {
        let url = Bundle.main.url(forResource: "SurfBreaks", withExtension: "json", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "SurfBreaks", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SurfBreak].self, from: data)) ?? []
    }
}
