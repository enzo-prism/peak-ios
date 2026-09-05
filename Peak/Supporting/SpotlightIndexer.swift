import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

/// Donates Peak's App Entities to Spotlight so sessions, spots, and gear are
/// findable by meaning — not just by opening the app and typing in History.
///
/// Indexing is on-device. Nothing is uploaded. Quiet no-op below iOS 18, under
/// UI tests (the suite does not assert Spotlight). Empty snapshots clear the index.
enum SpotlightIndexer {
    static let indexName = "PeakLogbook"

    @MainActor
    private static let queue = SpotlightReconciliationQueue()

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

        queue.submit {
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
            // Replace only Peak's named index. This also removes entities donated
            // by older app versions, renamed spots/gear, and sessions that have
            // fallen outside the 200-session window. An empty logbook must clear
            // its old search results too. Do not add anything if deletion fails.
            try await index.deleteAllSearchableItems()
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

/// Serialize replacement jobs: cancelling a Swift task does not guarantee that
/// an already submitted Core Spotlight write has stopped. Wait for every older
/// write to finish before clearing/replacing it, and skip superseded queued jobs.
/// Jobs deliberately run to completion without cancellation so an older donation
/// cannot finish after a newer deletion and resurrect removed search results.
@MainActor
final class SpotlightReconciliationQueue {
    private var generation = 0
    private var pending: Task<Void, Never>?

    @discardableResult
    func submit(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        generation += 1
        let requestedGeneration = generation
        let previous = pending
        let task = Task {
            await previous?.value
            guard requestedGeneration == self.generation else { return }
            await operation()
        }
        pending = task
        return task
    }
}
