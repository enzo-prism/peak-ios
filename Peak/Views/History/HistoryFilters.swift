import Foundation
import SwiftData

struct HistoryFilters {
    var spot: Spot?
    var gear: Gear?
    var buddy: Buddy?

    var isActive: Bool {
        spot != nil || gear != nil || buddy != nil
    }

    func matches(session: SurfSession) -> Bool {
        if let spot, session.spot?.persistentModelID != spot.persistentModelID {
            return false
        }
        if let gear, !session.gear.contains(where: { $0.persistentModelID == gear.persistentModelID }) {
            return false
        }
        if let buddy, !session.buddies.contains(where: { $0.persistentModelID == buddy.persistentModelID }) {
            return false
        }
        return true
    }

    mutating func clear() {
        spot = nil
        gear = nil
        buddy = nil
    }
}
