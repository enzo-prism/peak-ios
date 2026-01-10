import Foundation

struct HistoryFilters {
    var spot: Spot?
    var gear: Gear?
    var buddy: Buddy?

    var isActive: Bool {
        spot != nil || gear != nil || buddy != nil
    }

    mutating func clear() {
        spot = nil
        gear = nil
        buddy = nil
    }
}
