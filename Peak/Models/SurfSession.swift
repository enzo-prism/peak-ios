import Foundation
import SwiftData

@Model
final class SurfSession {
    var date: Date
    var spot: Spot?
    var notes: String
    var rating: Int
    var durationMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .nullify) var gear: [Gear]
    @Relationship(deleteRule: .nullify) var buddies: [Buddy]
    @Relationship(deleteRule: .cascade) var photos: [SessionPhoto]

    init(
        date: Date,
        spot: Spot?,
        gear: [Gear] = [],
        buddies: [Buddy] = [],
        photos: [SessionPhoto] = [],
        rating: Int = 0,
        durationMinutes: Int? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.spot = spot
        self.gear = gear
        self.buddies = buddies
        self.photos = photos
        self.rating = max(0, min(5, rating))
        self.durationMinutes = SurfSession.normalizedDuration(durationMinutes)
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func normalizedDuration(_ minutes: Int?) -> Int? {
        guard let minutes, minutes > 0 else { return nil }
        let clamped = min(minutes, 180)
        let step = 15
        let snapped = Int((Double(clamped) / Double(step)).rounded()) * step
        return max(step, min(snapped, 180))
    }
}
