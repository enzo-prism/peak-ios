import Foundation
import SwiftData

extension ModelContext {
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
            return existing
        }
        let gear = Gear(name: name, kind: kind)
        insert(gear)
        return gear
    }

    func existingSession(createdAt: Date) -> SurfSession? {
        let descriptor = FetchDescriptor<SurfSession>(predicate: #Predicate { $0.createdAt == createdAt })
        return (try? fetch(descriptor))?.first
    }

    func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let items = try fetch(descriptor)
        for item in items {
            delete(item)
        }
    }

    func resetAllData() throws {
        try deleteAll(SurfSession.self)
        try deleteAll(Gear.self)
        try deleteAll(Spot.self)
        try deleteAll(Buddy.self)
    }
}
