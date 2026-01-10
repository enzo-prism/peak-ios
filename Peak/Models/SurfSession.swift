import Foundation
import SwiftData

@Model
final class SurfSession {
    var date: Date
    var spot: Spot?
    var notes: String
    var rating: Int
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .nullify) var gear: [Gear]
    @Relationship(deleteRule: .nullify) var buddies: [Buddy]

    init(
        date: Date,
        spot: Spot?,
        gear: [Gear] = [],
        buddies: [Buddy] = [],
        rating: Int = 0,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.spot = spot
        self.gear = gear
        self.buddies = buddies
        self.rating = max(0, min(5, rating))
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
