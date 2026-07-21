import Foundation

/// Fills in a saved spot's missing coordinates from the bundled break catalog.
///
/// Since 2.6 a `Spot` needs nothing but a name, and `ModelContext.upsertSpot(named:)`
/// — the path every CSV/JSON import takes — always creates one with no
/// coordinates. Those spots could never auto-fill conditions and could never be
/// forecast, silently, forever. But a great many of them are real named breaks
/// that are already in `SurfBreaks.json` with a coordinate: "Pipeline",
/// "Uluwatu", "Trestles". Matching them by name costs nothing and repairs the
/// spot permanently.
///
/// **Only on an unambiguous match.** Writing a coordinate onto a spot changes
/// which patch of ocean the app reports on and which readings get stored against
/// the surfer's sessions, so a guess is worse than nothing. The match must be an
/// exact normalised-name hit on exactly one catalog entry; a near miss, a
/// substring, or two catalog breaks sharing the name all resolve to nothing and
/// the card falls back to asking the surfer to place the spot themselves.
enum SpotCoordinateResolver {

    /// The single catalog break named exactly `name`, or `nil` if there is no
    /// match or more than one.
    static func unambiguousMatch(forSpotNamed name: String, catalog: SurfBreakCatalog = .shared) -> SurfBreak? {
        let matches = catalog.exactMatches(name: name)
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    /// Writes the catalog coordinate onto `spot` when it has none.
    ///
    /// Returns whether anything was written, so a caller can report honestly and
    /// so the no-op case costs no store write. A spot that already has a
    /// coordinate is never touched — the surfer's own pin (or a previously
    /// resolved one) always wins over the catalog.
    ///
    /// `locationName` is filled at the same time only if it was empty: it is the
    /// human label under the spot's name, and leaving it blank while the map
    /// suddenly knows where the break is reads as a bug.
    @discardableResult
    static func resolveMissingCoordinates(for spot: Spot, catalog: SurfBreakCatalog = .shared) -> Bool {
        // Both halves must be absent, not either. A spot carrying one of the two
        // has a coordinate the surfer's data put there — a hand-edited or
        // truncated JSON import can produce exactly that, since `restore` copies
        // `latitude` and `longitude` across independently — and overwriting a
        // real latitude because its longitude went missing would be silently
        // moving a break the surfer supplied. Half-located spots stay
        // unforecastable and the card asks, which is the honest outcome.
        guard spot.latitude == nil, spot.longitude == nil else { return false }
        guard let match = unambiguousMatch(forSpotNamed: spot.name, catalog: catalog) else { return false }

        spot.latitude = match.latitude
        spot.longitude = match.longitude
        if spot.locationName?.trimmedNonEmpty == nil {
            spot.locationName = match.locationLabel.trimmedNonEmpty
        }
        return true
    }

    /// Convenience for a list of spots. Returns how many were repaired.
    @discardableResult
    static func resolveMissingCoordinates(for spots: [Spot], catalog: SurfBreakCatalog = .shared) -> Int {
        spots.reduce(0) { total, spot in
            total + (resolveMissingCoordinates(for: spot, catalog: catalog) ? 1 : 0)
        }
    }
}
