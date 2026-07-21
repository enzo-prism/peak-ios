import Foundation

/// Read-only catalog of popular surf breaks (bundled JSON), powering the Add Spot autocomplete.
/// Loaded once into a case/diacritic-folded index; search is prefix-first then contains, capped.
///
/// `nonisolated`: every stored property is a `let` and every method is a pure function of
/// them, so the catalog needs no actor. Marking it explicitly is load-bearing, not cosmetic.
/// The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise
/// infer `@MainActor` here — and a global-actor-isolated class gets an *isolated deinit*.
/// Because `IPHONEOS_DEPLOYMENT_TARGET` is 17.0, below the OS that provides
/// `swift_task_deinitOnExecutor` natively, that isolated deinit is routed through the
/// back-deployed `swift_task_deinitOnExecutorMainActorBackDeploy` shim emitted into the app
/// binary. On the iOS 26.2 simulator built by Xcode 26.3 that shim over-releases inside
/// `libswift_Concurrency` ("pointer being freed was not allocated"), so *deallocating* a
/// catalog aborted the whole unit-test host process. `SurfBreakCatalog.shared` is never
/// deallocated, which is why only the tests that build a throwaway catalog ever crashed.
/// Keep this `nonisolated`.
nonisolated final class SurfBreakCatalog {
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

    private static func loadBundled() -> [SurfBreak] {
        let url = Bundle.main.url(forResource: "SurfBreaks", withExtension: "json", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "SurfBreaks", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SurfBreak].self, from: data)) ?? []
    }
}
