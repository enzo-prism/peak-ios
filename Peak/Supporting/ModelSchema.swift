import Foundation
import SwiftData

enum PeakSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self]
    }

    @Model
    final class Spot {
        @Attribute(.unique) var key: String
        var name: String
        var createdAt: Date

        init(name: String, createdAt: Date = Date()) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Spot.makeKey(from: cleaned)
            self.createdAt = createdAt
        }

        static func makeKey(from name: String) -> String {
            name.normalizedKey
        }
    }

    @Model
    final class Gear {
        @Attribute(.unique) var key: String
        var name: String
        var kind: GearKind
        var createdAt: Date

        init(name: String, kind: GearKind, createdAt: Date = Date()) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.createdAt = createdAt
        }

        static func makeKey(name: String, kind: GearKind) -> String {
            "\(kind.rawValue)|\(name.normalizedKey)"
        }
    }

    @Model
    final class Buddy {
        @Attribute(.unique) var key: String
        var name: String
        var createdAt: Date

        init(name: String, createdAt: Date = Date()) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Buddy.makeKey(from: cleaned)
            self.createdAt = createdAt
        }

        static func makeKey(from name: String) -> String {
            name.normalizedKey
        }
    }

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
}

enum PeakSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 1, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self]
    }

    @Model
    final class Spot {
        @Attribute(.unique) var key: String
        var name: String
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var createdAt: Date

        init(
            name: String,
            locationName: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Spot.makeKey(from: cleaned)
            self.locationName = locationName?.trimmedNonEmpty
            self.latitude = latitude
            self.longitude = longitude
            self.createdAt = createdAt
        }

        static func makeKey(from name: String) -> String {
            name.normalizedKey
        }
    }

    @Model
    final class Gear {
        @Attribute(.unique) var key: String
        var name: String
        var kind: GearKind
        var createdAt: Date

        init(name: String, kind: GearKind, createdAt: Date = Date()) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.createdAt = createdAt
        }

        static func makeKey(name: String, kind: GearKind) -> String {
            "\(kind.rawValue)|\(name.normalizedKey)"
        }
    }

    @Model
    final class Buddy {
        @Attribute(.unique) var key: String
        var name: String
        var createdAt: Date

        init(name: String, createdAt: Date = Date()) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Buddy.makeKey(from: cleaned)
            self.createdAt = createdAt
        }

        static func makeKey(from name: String) -> String {
            name.normalizedKey
        }
    }

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
}

enum PeakSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 2, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self]
    }
}

enum PeakMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PeakSchemaV1.self, PeakSchemaV2.self, PeakSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: PeakSchemaV1.self, toVersion: PeakSchemaV2.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV2.self, toVersion: PeakSchemaV3.self)
        ]
    }
}
