import Foundation
@testable import Peak

enum TestFixture {
    static func spot(
        name: String = "Trestles",
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = TestCalendar.makeDate(year: 2026, month: 2, day: 1, hour: 6)
    ) -> Spot {
        Spot(
            name: name,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            createdAt: createdAt
        )
    }

    static func gear(
        name: String = "6'2\" Fish",
        kind: GearKind = .board,
        brand: String? = nil,
        model: String? = nil,
        size: String? = nil,
        volumeLiters: Double? = nil,
        notes: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = TestCalendar.makeDate(year: 2026, month: 2, day: 1, hour: 6)
    ) -> Gear {
        Gear(
            name: name,
            kind: kind,
            brand: brand,
            model: model,
            size: size,
            volumeLiters: volumeLiters,
            notes: notes,
            isArchived: isArchived,
            createdAt: createdAt
        )
    }

    static func buddy(
        name: String = "Kai",
        createdAt: Date = TestCalendar.makeDate(year: 2026, month: 2, day: 1, hour: 6)
    ) -> Buddy {
        Buddy(name: name, createdAt: createdAt)
    }

    static func session(
        date: Date = TestCalendar.makeDate(year: 2026, month: 2, day: 2, hour: 7),
        spot: Spot? = nil,
        gear: [Gear] = [],
        buddies: [Buddy] = [],
        rating: Int = 0,
        durationMinutes: Int? = nil,
        notes: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> SurfSession {
        let created = createdAt ?? date
        let updated = updatedAt ?? created
        return SurfSession(
            date: date,
            spot: spot,
            gear: gear,
            buddies: buddies,
            rating: rating,
            durationMinutes: durationMinutes,
            notes: notes,
            createdAt: created,
            updatedAt: updated
        )
    }
}
