import Foundation
import SwiftData

enum SpotLimitError: LocalizedError {
    case limitReached(max: Int)

    var errorDescription: String? {
        switch self {
        case .limitReached(let max):
            return "You can save up to \(max) surf breaks."
        }
    }
}

extension SurfSession {
    /// Shared descriptor for date-descending session queries. Prefetching the
    /// relationships a view actually reads avoids one SwiftData fault (SQLite
    /// round trip) per row while scrolling or aggregating.
    static func sortedByDateDescending(
        limit: Int? = nil,
        prefetch: [PartialKeyPath<SurfSession>] = []
    ) -> FetchDescriptor<SurfSession> {
        var descriptor = FetchDescriptor<SurfSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        descriptor.relationshipKeyPathsForPrefetching = prefetch
        return descriptor
    }
}

extension ModelContext {
    /// Counts in SQLite via `fetchCount` instead of materializing every Spot
    /// just to read `.count`. (`deleteAll` below intentionally keeps its
    /// fetch-then-delete shape: batch `delete(model:)` skips in-memory model
    /// invalidation and delete-rule processing, which `resetAllData` and the
    /// in-memory test containers rely on, and it is not a hot path.)
    func spotCount() throws -> Int {
        try fetchCount(FetchDescriptor<Spot>())
    }

    func createSpot(
        name: String,
        locationName: String?,
        latitude: Double?,
        longitude: Double?,
        createdAt: Date = Date()
    ) throws -> Spot {
        let count = try spotCount()
        guard count < Spot.maxCount else {
            throw SpotLimitError.limitReached(max: Spot.maxCount)
        }
        let spot = Spot(
            name: name,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            createdAt: createdAt
        )
        insert(spot)
        return spot
    }

    func existingSpot(named name: String) -> Spot? {
        let key = Spot.makeKey(from: name)
        let descriptor = FetchDescriptor<Spot>(predicate: #Predicate { $0.key == key })
        return (try? fetch(descriptor))?.first
    }

    func upsertSpot(named name: String) -> Spot {
        if let existing = existingSpot(named: name) {
            return existing
        }
        let spot = Spot(name: name)
        insert(spot)
        return spot
    }

    func existingBuddy(named name: String) -> Buddy? {
        let key = Buddy.makeKey(from: name)
        let descriptor = FetchDescriptor<Buddy>(predicate: #Predicate { $0.key == key })
        return (try? fetch(descriptor))?.first
    }

    func upsertBuddy(named name: String) -> Buddy {
        if let existing = existingBuddy(named: name) {
            return existing
        }
        let buddy = Buddy(name: name)
        insert(buddy)
        return buddy
    }

    func existingGear(named name: String, kind: GearKind) -> Gear? {
        let key = Gear.makeKey(name: name, kind: kind)
        let descriptor = FetchDescriptor<Gear>(predicate: #Predicate { $0.key == key })
        return (try? fetch(descriptor))?.first
    }

    func upsertGear(named name: String, kind: GearKind) -> Gear {
        if let existing = existingGear(named: name, kind: kind) {
            existing.isArchived = false
            return existing
        }
        let gear = Gear(name: name, kind: kind)
        insert(gear)
        return gear
    }

    func existingSession(createdAt: Date) -> SurfSession? {
        // Match at millisecond precision, not exact `Date` equality: a stored
        // `createdAt` from `Date()` keeps sub-millisecond precision, while the
        // value parsed back from an export is truncated to milliseconds. Exact
        // equality therefore fails to match a session against its own export,
        // which would duplicate the entire library on a merge import/restore.
        // Narrow the fetch to the surrounding second in-store, then match on the
        // millisecond key in memory.
        let target = SurfSession.millisecondsKey(for: createdAt)
        let lower = createdAt.addingTimeInterval(-1)
        let upper = createdAt.addingTimeInterval(1)
        let descriptor = FetchDescriptor<SurfSession>(
            predicate: #Predicate { $0.createdAt >= lower && $0.createdAt <= upper }
        )
        let candidates = (try? fetch(descriptor)) ?? []
        return candidates.first { SurfSession.millisecondsKey(for: $0.createdAt) == target }
    }

    private func deleteSessionMediaFiles() throws {
        let descriptor = FetchDescriptor<SessionMedia>()
        let items = try fetch(descriptor)
        SessionMediaStore.deleteStoredMedia(for: items)
    }

    func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let items = try fetch(descriptor)
        for item in items {
            delete(item)
        }
    }

    func resetAllData() throws {
        try deleteSessionMediaFiles()
        try deleteAll(SurfSession.self)
        try deleteAll(SessionMedia.self)
        try deleteAll(Gear.self)
        try deleteAll(Spot.self)
        try deleteAll(Buddy.self)
    }
}
