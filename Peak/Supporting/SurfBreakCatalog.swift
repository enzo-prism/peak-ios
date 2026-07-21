import Foundation

/// Read-only catalog of popular surf breaks (bundled JSON), powering the Add Spot autocomplete.
/// Loaded once into a case/diacritic-folded index; search is prefix-first then contains, capped.
final class SurfBreakCatalog {
    static let shared = SurfBreakCatalog()

    private struct Indexed {
        let foldedName: String
        let foldedLocation: String
        let value: SurfBreak
    }

    private let index: [Indexed]

    init(breaks: [SurfBreak]? = nil) {
        let source = breaks ?? Self.loadBundled()
        index = source.map {
            Indexed(
                foldedName: $0.name.searchFolded,
                foldedLocation: $0.locationLabel.searchFolded,
                value: $0
            )
        }
    }

    var count: Int { index.count }

    /// Matches `raw` (>= 2 chars) against break names then locations, excluding any break the user
    /// has already saved (matched by spot key), returning at most `limit` results
    /// (name-prefix matches ranked above contains matches).
    func search(_ raw: String, limit: Int = 6, excludingKeys: Set<String> = []) -> [SurfBreak] {
        let query = raw.searchFolded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        var prefix: [SurfBreak] = []
        var contains: [SurfBreak] = []
        for entry in index {
            if excludingKeys.contains(entry.value.name.normalizedKey) { continue }
            if entry.foldedName.hasPrefix(query) {
                prefix.append(entry.value)
                if prefix.count >= limit { break }
            } else if entry.foldedName.contains(query) || entry.foldedLocation.contains(query) {
                contains.append(entry.value)
            }
        }
        return Array((prefix + contains).prefix(limit))
    }

    private static func loadBundled() -> [SurfBreak] {
        let url = Bundle.main.url(forResource: "SurfBreaks", withExtension: "json", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "SurfBreaks", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SurfBreak].self, from: data)) ?? []
    }
}
