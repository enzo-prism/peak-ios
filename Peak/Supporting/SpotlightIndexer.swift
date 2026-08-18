import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

/// Donates Peak's App Entities to Spotlight so sessions, spots, and gear are
/// findable by meaning — not just by opening the app and typing in History.
///
/// Indexing is on-device. Nothing is uploaded. Quiet no-op below iOS 18, under
/// UI tests (the suite does not assert Spotlight), and when the entity arrays
/// are empty.
enum SpotlightIndexer {
    static let indexName = "PeakLogbook"

    @MainActor
    static func donate(
        sessions: [SurfSession],
        spots: [Spot],
        gear: [Gear]
    ) {
        guard !TestingDefaults.isUITest else { return }
        guard #available(iOS 18.0, *) else { return }

        let sessionEntities = SessionIntentQueries.recentSessions(from: sessions, limit: 200)
            .map(SurfSessionEntity.init(session:))
        let spotEntities = spots.map(SpotEntity.init(spot:))
        let gearEntities = gear.map(GearEntity.init(gear:))

        Task {
            await donateEntities(sessions: sessionEntities, spots: spotEntities, gear: gearEntities)
        }
    }

    @available(iOS 18.0, *)
    private static func donateEntities(
        sessions: [SurfSessionEntity],
        spots: [SpotEntity],
        gear: [GearEntity]
    ) async {
        let index = CSSearchableIndex(name: indexName)
        do {
            if !sessions.isEmpty {
                try await index.indexAppEntities(sessions)
            }
            if !spots.isEmpty {
                try await index.indexAppEntities(spots)
            }
            if !gear.isEmpty {
                try await index.indexAppEntities(gear)
            }
        } catch {
            // Spotlight donation is best-effort; a failed index must never
            // interrupt logging or show an error the surfer cannot act on.
        }
    }
}
