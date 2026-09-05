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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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

enum PeakSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 3, 0)
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
        var durationMinutes: Int?
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
            durationMinutes: Int? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.rating = max(0, min(5, rating))
            self.durationMinutes = durationMinutes
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

enum PeakSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 4, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.createdAt = createdAt
        }
    }

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
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
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
            self.media = media
            self.rating = max(0, min(5, rating))
            self.durationMinutes = durationMinutes
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

enum PeakSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 5, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.createdAt = createdAt
        }
    }

    @Model
    final class SurfSession {
        var date: Date
        var spot: Spot?
        var notes: String
        var rating: Int
        var durationMinutes: Int?
        var windCondition: WindCondition?
        var waveHeight: WaveHeight?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify) var gear: [Gear]
        @Relationship(deleteRule: .nullify) var buddies: [Buddy]
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
            rating: Int = 0,
            durationMinutes: Int? = nil,
            windCondition: WindCondition? = nil,
            waveHeight: WaveHeight? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.media = media
            self.rating = max(0, min(5, rating))
            self.durationMinutes = durationMinutes
            self.windCondition = windCondition
            self.waveHeight = waveHeight
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

// PeakSchemaV7 (1.6.0) is now frozen: it holds inline snapshots of the model shapes exactly as
// they shipped at 1.6.0, so the V7 -> V8 migration diff is computed against the real old shape.
// PeakSchemaV8 (the new HEAD) references the live models, which carry the new media fields.
enum PeakSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 6, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.createdAt = createdAt
        }
    }

    @Model
    final class SurfSession {
        var date: Date
        var spot: Spot?
        var notes: String
        var rating: Int
        var durationMinutes: Int?
        var windCondition: WindCondition?
        var waveHeight: WaveHeight?
        var windSpeedKph: Double?
        var windDirectionDegrees: Double?
        var waveHeightMeters: Double?
        var swellWaveHeightMeters: Double?
        var swellWavePeriodSeconds: Double?
        var swellWaveDirectionDegrees: Double?
        var windWaveHeightMeters: Double?
        var windWavePeriodSeconds: Double?
        var windWaveDirectionDegrees: Double?
        var seaSurfaceTemperatureC: Double?
        var conditionsSource: String?
        var conditionsFetchedAt: Date?
        var conditionsLatitude: Double?
        var conditionsLongitude: Double?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify) var gear: [Gear]
        @Relationship(deleteRule: .nullify) var buddies: [Buddy]
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
            rating: Int = 0,
            durationMinutes: Int? = nil,
            windCondition: WindCondition? = nil,
            waveHeight: WaveHeight? = nil,
            windSpeedKph: Double? = nil,
            windDirectionDegrees: Double? = nil,
            waveHeightMeters: Double? = nil,
            swellWaveHeightMeters: Double? = nil,
            swellWavePeriodSeconds: Double? = nil,
            swellWaveDirectionDegrees: Double? = nil,
            windWaveHeightMeters: Double? = nil,
            windWavePeriodSeconds: Double? = nil,
            windWaveDirectionDegrees: Double? = nil,
            seaSurfaceTemperatureC: Double? = nil,
            conditionsSource: String? = nil,
            conditionsFetchedAt: Date? = nil,
            conditionsLatitude: Double? = nil,
            conditionsLongitude: Double? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.media = media
            self.rating = rating
            self.durationMinutes = durationMinutes
            self.windCondition = windCondition
            self.waveHeight = waveHeight
            self.windSpeedKph = windSpeedKph
            self.windDirectionDegrees = windDirectionDegrees
            self.waveHeightMeters = waveHeightMeters
            self.swellWaveHeightMeters = swellWaveHeightMeters
            self.swellWavePeriodSeconds = swellWavePeriodSeconds
            self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
            self.windWaveHeightMeters = windWaveHeightMeters
            self.windWavePeriodSeconds = windWavePeriodSeconds
            self.windWaveDirectionDegrees = windWaveDirectionDegrees
            self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
            self.conditionsSource = conditionsSource
            self.conditionsFetchedAt = conditionsFetchedAt
            self.conditionsLatitude = conditionsLatitude
            self.conditionsLongitude = conditionsLongitude
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

// PeakSchemaV8 (1.7.0) is now frozen: it holds inline snapshots of the model shapes exactly as
// they shipped at 1.7.0, so the V8 -> V9 migration diff is computed against the real old shape
// instead of against whatever the live classes happen to look like today.
//
// SwiftData rejects two `VersionedSchema`s whose entities hash to the same shape ("Duplicate
// version checksums detected"), so this freeze is only ever valid in the same change as a real
// field delta — which V9 below carries (session tide fields + `Spot.tideStationId`).
enum PeakSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 7, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var sortIndex: Int = 0
        var cropOriginX: Double = 0
        var cropOriginY: Double = 0
        var cropWidth: Double = 1
        var cropHeight: Double = 1
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            sortIndex: Int = 0,
            cropOriginX: Double = 0,
            cropOriginY: Double = 0,
            cropWidth: Double = 1,
            cropHeight: Double = 1,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.sortIndex = sortIndex
            self.cropOriginX = cropOriginX
            self.cropOriginY = cropOriginY
            self.cropWidth = cropWidth
            self.cropHeight = cropHeight
            self.createdAt = createdAt
        }
    }

    @Model
    final class SurfSession {
        var date: Date
        var spot: Spot?
        var notes: String
        var rating: Int
        var durationMinutes: Int?
        var windCondition: WindCondition?
        var waveHeight: WaveHeight?
        var windSpeedKph: Double?
        var windDirectionDegrees: Double?
        var waveHeightMeters: Double?
        var swellWaveHeightMeters: Double?
        var swellWavePeriodSeconds: Double?
        var swellWaveDirectionDegrees: Double?
        var windWaveHeightMeters: Double?
        var windWavePeriodSeconds: Double?
        var windWaveDirectionDegrees: Double?
        var seaSurfaceTemperatureC: Double?
        var conditionsSource: String?
        var conditionsFetchedAt: Date?
        var conditionsLatitude: Double?
        var conditionsLongitude: Double?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify) var gear: [Gear]
        @Relationship(deleteRule: .nullify) var buddies: [Buddy]
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
            rating: Int = 0,
            durationMinutes: Int? = nil,
            windCondition: WindCondition? = nil,
            waveHeight: WaveHeight? = nil,
            windSpeedKph: Double? = nil,
            windDirectionDegrees: Double? = nil,
            waveHeightMeters: Double? = nil,
            swellWaveHeightMeters: Double? = nil,
            swellWavePeriodSeconds: Double? = nil,
            swellWaveDirectionDegrees: Double? = nil,
            windWaveHeightMeters: Double? = nil,
            windWavePeriodSeconds: Double? = nil,
            windWaveDirectionDegrees: Double? = nil,
            seaSurfaceTemperatureC: Double? = nil,
            conditionsSource: String? = nil,
            conditionsFetchedAt: Date? = nil,
            conditionsLatitude: Double? = nil,
            conditionsLongitude: Double? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.media = media
            self.rating = rating
            self.durationMinutes = durationMinutes
            self.windCondition = windCondition
            self.waveHeight = waveHeight
            self.windSpeedKph = windSpeedKph
            self.windDirectionDegrees = windDirectionDegrees
            self.waveHeightMeters = waveHeightMeters
            self.swellWaveHeightMeters = swellWaveHeightMeters
            self.swellWavePeriodSeconds = swellWavePeriodSeconds
            self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
            self.windWaveHeightMeters = windWaveHeightMeters
            self.windWavePeriodSeconds = windWavePeriodSeconds
            self.windWaveDirectionDegrees = windWaveDirectionDegrees
            self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
            self.conditionsSource = conditionsSource
            self.conditionsFetchedAt = conditionsFetchedAt
            self.conditionsLatitude = conditionsLatitude
            self.conditionsLongitude = conditionsLongitude
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

// PeakSchemaV9 (1.8.0) is now frozen: it holds inline snapshots of the model shapes exactly as
// they shipped at 1.8.0 (the 2.8 tide delta), so the V9 -> V10 migration diff is computed against
// the real old shape instead of against whatever the live classes happen to look like today.
//
// SwiftData rejects two `VersionedSchema`s whose entities hash to the same shape ("Duplicate
// version checksums detected"), so this freeze is only ever valid in the same change as a real
// field delta — which V10 below carries (the 3.0 wave-stat fields).
enum PeakSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 8, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
    }

    @Model
    final class Spot {
        @Attribute(.unique) var key: String
        var name: String
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var tideStationId: String?
        var createdAt: Date

        init(
            name: String,
            locationName: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            tideStationId: String? = nil,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Spot.makeKey(from: cleaned)
            self.locationName = locationName?.trimmedNonEmpty
            self.latitude = latitude
            self.longitude = longitude
            self.tideStationId = tideStationId?.trimmedNonEmpty
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var sortIndex: Int = 0
        var cropOriginX: Double = 0
        var cropOriginY: Double = 0
        var cropWidth: Double = 1
        var cropHeight: Double = 1
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            sortIndex: Int = 0,
            cropOriginX: Double = 0,
            cropOriginY: Double = 0,
            cropWidth: Double = 1,
            cropHeight: Double = 1,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.sortIndex = sortIndex
            self.cropOriginX = cropOriginX
            self.cropOriginY = cropOriginY
            self.cropWidth = cropWidth
            self.cropHeight = cropHeight
            self.createdAt = createdAt
        }
    }

    @Model
    final class SurfSession {
        var date: Date
        var spot: Spot?
        var notes: String
        var rating: Int
        var durationMinutes: Int?
        var windCondition: WindCondition?
        var waveHeight: WaveHeight?
        var windSpeedKph: Double?
        var windDirectionDegrees: Double?
        var waveHeightMeters: Double?
        var swellWaveHeightMeters: Double?
        var swellWavePeriodSeconds: Double?
        var swellWaveDirectionDegrees: Double?
        var windWaveHeightMeters: Double?
        var windWavePeriodSeconds: Double?
        var windWaveDirectionDegrees: Double?
        var seaSurfaceTemperatureC: Double?
        var seaLevelHeightM: Double?
        var tideTrend: String?
        var conditionsSource: String?
        var conditionsFetchedAt: Date?
        var conditionsLatitude: Double?
        var conditionsLongitude: Double?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify) var gear: [Gear]
        @Relationship(deleteRule: .nullify) var buddies: [Buddy]
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
            rating: Int = 0,
            durationMinutes: Int? = nil,
            windCondition: WindCondition? = nil,
            waveHeight: WaveHeight? = nil,
            windSpeedKph: Double? = nil,
            windDirectionDegrees: Double? = nil,
            waveHeightMeters: Double? = nil,
            swellWaveHeightMeters: Double? = nil,
            swellWavePeriodSeconds: Double? = nil,
            swellWaveDirectionDegrees: Double? = nil,
            windWaveHeightMeters: Double? = nil,
            windWavePeriodSeconds: Double? = nil,
            windWaveDirectionDegrees: Double? = nil,
            seaSurfaceTemperatureC: Double? = nil,
            seaLevelHeightM: Double? = nil,
            tideTrend: String? = nil,
            conditionsSource: String? = nil,
            conditionsFetchedAt: Date? = nil,
            conditionsLatitude: Double? = nil,
            conditionsLongitude: Double? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.media = media
            self.rating = rating
            self.durationMinutes = durationMinutes
            self.windCondition = windCondition
            self.waveHeight = waveHeight
            self.windSpeedKph = windSpeedKph
            self.windDirectionDegrees = windDirectionDegrees
            self.waveHeightMeters = waveHeightMeters
            self.swellWaveHeightMeters = swellWaveHeightMeters
            self.swellWavePeriodSeconds = swellWavePeriodSeconds
            self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
            self.windWaveHeightMeters = windWaveHeightMeters
            self.windWavePeriodSeconds = windWavePeriodSeconds
            self.windWaveDirectionDegrees = windWaveDirectionDegrees
            self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
            self.seaLevelHeightM = seaLevelHeightM
            self.tideTrend = tideTrend
            self.conditionsSource = conditionsSource
            self.conditionsFetchedAt = conditionsFetchedAt
            self.conditionsLatitude = conditionsLatitude
            self.conditionsLongitude = conditionsLongitude
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

/// Frozen 1.9.0 shape. These independent snapshots preserve the public 3.2
/// checksum; SurfSession includes the seven wave-stat fields introduced in 3.0.
enum PeakSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 9, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
    }

    @Model
    final class Spot {
        @Attribute(.unique) var key: String
        var name: String
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var tideStationId: String?
        var createdAt: Date

        init(
            name: String,
            locationName: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            tideStationId: String? = nil,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Spot.makeKey(from: cleaned)
            self.locationName = locationName?.trimmedNonEmpty
            self.latitude = latitude
            self.longitude = longitude
            self.tideStationId = tideStationId?.trimmedNonEmpty
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var sortIndex: Int = 0
        var cropOriginX: Double = 0
        var cropOriginY: Double = 0
        var cropWidth: Double = 1
        var cropHeight: Double = 1
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            sortIndex: Int = 0,
            cropOriginX: Double = 0,
            cropOriginY: Double = 0,
            cropWidth: Double = 1,
            cropHeight: Double = 1,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.sortIndex = sortIndex
            self.cropOriginX = cropOriginX
            self.cropOriginY = cropOriginY
            self.cropWidth = cropWidth
            self.cropHeight = cropHeight
            self.createdAt = createdAt
        }
    }

    @Model
    final class SurfSession {
        var date: Date
        var spot: Spot?
        var notes: String
        var rating: Int
        var durationMinutes: Int?
        var windCondition: WindCondition?
        var waveHeight: WaveHeight?
        var windSpeedKph: Double?
        var windDirectionDegrees: Double?
        var waveHeightMeters: Double?
        var swellWaveHeightMeters: Double?
        var swellWavePeriodSeconds: Double?
        var swellWaveDirectionDegrees: Double?
        var windWaveHeightMeters: Double?
        var windWavePeriodSeconds: Double?
        var windWaveDirectionDegrees: Double?
        var seaSurfaceTemperatureC: Double?
        var seaLevelHeightM: Double?
        var tideTrend: String?
        var conditionsSource: String?
        var conditionsFetchedAt: Date?
        var conditionsLatitude: Double?
        var conditionsLongitude: Double?
        var waveCount: Int?
        var topSpeedKph: Double?
        var longestRideSeconds: Double?
        var longestRideMeters: Double?
        var paddleDistanceMeters: Double?
        var waveStatsSource: String?
        var linkedWorkoutID: String?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify) var gear: [Gear]
        @Relationship(deleteRule: .nullify) var buddies: [Buddy]
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
            rating: Int = 0,
            durationMinutes: Int? = nil,
            windCondition: WindCondition? = nil,
            waveHeight: WaveHeight? = nil,
            windSpeedKph: Double? = nil,
            windDirectionDegrees: Double? = nil,
            waveHeightMeters: Double? = nil,
            swellWaveHeightMeters: Double? = nil,
            swellWavePeriodSeconds: Double? = nil,
            swellWaveDirectionDegrees: Double? = nil,
            windWaveHeightMeters: Double? = nil,
            windWavePeriodSeconds: Double? = nil,
            windWaveDirectionDegrees: Double? = nil,
            seaSurfaceTemperatureC: Double? = nil,
            seaLevelHeightM: Double? = nil,
            tideTrend: String? = nil,
            conditionsSource: String? = nil,
            conditionsFetchedAt: Date? = nil,
            conditionsLatitude: Double? = nil,
            conditionsLongitude: Double? = nil,
            waveCount: Int? = nil,
            topSpeedKph: Double? = nil,
            longestRideSeconds: Double? = nil,
            longestRideMeters: Double? = nil,
            paddleDistanceMeters: Double? = nil,
            waveStatsSource: String? = nil,
            linkedWorkoutID: String? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.media = media
            self.rating = rating
            self.durationMinutes = durationMinutes
            self.windCondition = windCondition
            self.waveHeight = waveHeight
            self.windSpeedKph = windSpeedKph
            self.windDirectionDegrees = windDirectionDegrees
            self.waveHeightMeters = waveHeightMeters
            self.swellWaveHeightMeters = swellWaveHeightMeters
            self.swellWavePeriodSeconds = swellWavePeriodSeconds
            self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
            self.windWaveHeightMeters = windWaveHeightMeters
            self.windWavePeriodSeconds = windWavePeriodSeconds
            self.windWaveDirectionDegrees = windWaveDirectionDegrees
            self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
            self.seaLevelHeightM = seaLevelHeightM
            self.tideTrend = tideTrend
            self.conditionsSource = conditionsSource
            self.conditionsFetchedAt = conditionsFetchedAt
            self.conditionsLatitude = conditionsLatitude
            self.conditionsLongitude = conditionsLongitude
            self.waveCount = waveCount
            self.topSpeedKph = topSpeedKph
            self.longestRideSeconds = longestRideSeconds
            self.longestRideMeters = longestRideMeters
            self.paddleDistanceMeters = paddleDistanceMeters
            self.waveStatsSource = waveStatsSource
            self.linkedWorkoutID = linkedWorkoutID
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

/// Frozen 1.10.0 shape, including explicit many-to-many inverses.
enum PeakSchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 10, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
    }

    @Model
    final class Spot {
        @Attribute(.unique) var key: String
        var name: String
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var tideStationId: String?
        var createdAt: Date

        init(
            name: String,
            locationName: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            tideStationId: String? = nil,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.key = Spot.makeKey(from: cleaned)
            self.locationName = locationName?.trimmedNonEmpty
            self.latitude = latitude
            self.longitude = longitude
            self.tideStationId = tideStationId?.trimmedNonEmpty
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
        var brand: String?
        var model: String?
        var size: String?
        var volumeLiters: Double?
        var notes: String?
        @Attribute(.externalStorage) var photoData: Data?
        var isArchived: Bool = false
        var createdAt: Date
        @Relationship(deleteRule: .nullify) var sessions: [SurfSession] = []

        init(
            name: String,
            kind: GearKind,
            brand: String? = nil,
            model: String? = nil,
            size: String? = nil,
            volumeLiters: Double? = nil,
            notes: String? = nil,
            photoData: Data? = nil,
            isArchived: Bool = false,
            createdAt: Date = Date()
        ) {
            let cleaned = name.trimmedNonEmpty ?? "Unknown"
            self.name = cleaned
            self.kind = kind
            self.key = Gear.makeKey(name: cleaned, kind: kind)
            self.brand = brand?.trimmedNonEmpty
            self.model = model?.trimmedNonEmpty
            self.size = size?.trimmedNonEmpty
            self.volumeLiters = volumeLiters
            self.notes = notes?.trimmedNonEmpty
            self.photoData = photoData
            self.isArchived = isArchived
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
        @Relationship(deleteRule: .nullify) var sessions: [SurfSession] = []

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
    final class SessionMedia {
        var kind: SessionMediaKind
        @Attribute(.externalStorage) var photoData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var videoFileName: String?
        var sortIndex: Int = 0
        var cropOriginX: Double = 0
        var cropOriginY: Double = 0
        var cropWidth: Double = 1
        var cropHeight: Double = 1
        var createdAt: Date

        init(
            kind: SessionMediaKind,
            photoData: Data? = nil,
            thumbnailData: Data? = nil,
            videoFileName: String? = nil,
            sortIndex: Int = 0,
            cropOriginX: Double = 0,
            cropOriginY: Double = 0,
            cropWidth: Double = 1,
            cropHeight: Double = 1,
            createdAt: Date = Date()
        ) {
            self.kind = kind
            self.photoData = photoData
            self.thumbnailData = thumbnailData
            self.videoFileName = videoFileName
            self.sortIndex = sortIndex
            self.cropOriginX = cropOriginX
            self.cropOriginY = cropOriginY
            self.cropWidth = cropWidth
            self.cropHeight = cropHeight
            self.createdAt = createdAt
        }
    }

    @Model
    final class SurfSession {
        var date: Date
        var spot: Spot?
        var notes: String
        var rating: Int
        var durationMinutes: Int?
        var windCondition: WindCondition?
        var waveHeight: WaveHeight?
        var windSpeedKph: Double?
        var windDirectionDegrees: Double?
        var waveHeightMeters: Double?
        var swellWaveHeightMeters: Double?
        var swellWavePeriodSeconds: Double?
        var swellWaveDirectionDegrees: Double?
        var windWaveHeightMeters: Double?
        var windWavePeriodSeconds: Double?
        var windWaveDirectionDegrees: Double?
        var seaSurfaceTemperatureC: Double?
        var seaLevelHeightM: Double?
        var tideTrend: String?
        var conditionsSource: String?
        var conditionsFetchedAt: Date?
        var conditionsLatitude: Double?
        var conditionsLongitude: Double?
        var waveCount: Int?
        var topSpeedKph: Double?
        var longestRideSeconds: Double?
        var longestRideMeters: Double?
        var paddleDistanceMeters: Double?
        var waveStatsSource: String?
        var linkedWorkoutID: String?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify, inverse: \Gear.sessions) var gear: [Gear]
        @Relationship(deleteRule: .nullify, inverse: \Buddy.sessions) var buddies: [Buddy]
        @Relationship(deleteRule: .cascade) var media: [SessionMedia]

        init(
            date: Date,
            spot: Spot?,
            gear: [Gear] = [],
            buddies: [Buddy] = [],
            media: [SessionMedia] = [],
            rating: Int = 0,
            durationMinutes: Int? = nil,
            windCondition: WindCondition? = nil,
            waveHeight: WaveHeight? = nil,
            windSpeedKph: Double? = nil,
            windDirectionDegrees: Double? = nil,
            waveHeightMeters: Double? = nil,
            swellWaveHeightMeters: Double? = nil,
            swellWavePeriodSeconds: Double? = nil,
            swellWaveDirectionDegrees: Double? = nil,
            windWaveHeightMeters: Double? = nil,
            windWavePeriodSeconds: Double? = nil,
            windWaveDirectionDegrees: Double? = nil,
            seaSurfaceTemperatureC: Double? = nil,
            seaLevelHeightM: Double? = nil,
            tideTrend: String? = nil,
            conditionsSource: String? = nil,
            conditionsFetchedAt: Date? = nil,
            conditionsLatitude: Double? = nil,
            conditionsLongitude: Double? = nil,
            waveCount: Int? = nil,
            topSpeedKph: Double? = nil,
            longestRideSeconds: Double? = nil,
            longestRideMeters: Double? = nil,
            paddleDistanceMeters: Double? = nil,
            waveStatsSource: String? = nil,
            linkedWorkoutID: String? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.date = date
            self.spot = spot
            self.gear = gear
            self.buddies = buddies
            self.media = media
            self.rating = rating
            self.durationMinutes = durationMinutes
            self.windCondition = windCondition
            self.waveHeight = waveHeight
            self.windSpeedKph = windSpeedKph
            self.windDirectionDegrees = windDirectionDegrees
            self.waveHeightMeters = waveHeightMeters
            self.swellWaveHeightMeters = swellWaveHeightMeters
            self.swellWavePeriodSeconds = swellWavePeriodSeconds
            self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
            self.windWaveHeightMeters = windWaveHeightMeters
            self.windWavePeriodSeconds = windWavePeriodSeconds
            self.windWaveDirectionDegrees = windWaveDirectionDegrees
            self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
            self.seaLevelHeightM = seaLevelHeightM
            self.tideTrend = tideTrend
            self.conditionsSource = conditionsSource
            self.conditionsFetchedAt = conditionsFetchedAt
            self.conditionsLatitude = conditionsLatitude
            self.conditionsLongitude = conditionsLongitude
            self.waveCount = waveCount
            self.topSpeedKph = topSpeedKph
            self.longestRideSeconds = longestRideSeconds
            self.longestRideMeters = longestRideMeters
            self.paddleDistanceMeters = paddleDistanceMeters
            self.waveStatsSource = waveStatsSource
            self.linkedWorkoutID = linkedWorkoutID
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}


/// HEAD: adds portable session identity.
enum PeakSchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 11, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self]
    }
}

private struct V10RelationshipSnapshot {
    let gearKeys: [String]
    let buddyKeys: [String]
}

/// `MigrationStage.custom` runs its two closures synchronously but against
/// different model contexts. This lock-protected bridge carries only immutable
/// relationship keys between them and is cleared as soon as the stage finishes.
private final class V10RelationshipMigrationBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [Data: V10RelationshipSnapshot] = [:]

    func replace(with value: [Data: V10RelationshipSnapshot]) {
        lock.lock()
        snapshots = value
        lock.unlock()
    }

    func take() -> [Data: V10RelationshipSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        let value = snapshots
        snapshots = [:]
        return value
    }
}

enum PeakMigrationPlan: SchemaMigrationPlan {
    private static let v10RelationshipBridge = V10RelationshipMigrationBridge()

    static var schemas: [any VersionedSchema.Type] {
        [
            PeakSchemaV1.self,
            PeakSchemaV2.self,
            PeakSchemaV3.self,
            PeakSchemaV4.self,
            PeakSchemaV5.self,
            PeakSchemaV6.self,
            PeakSchemaV7.self,
            PeakSchemaV8.self,
            PeakSchemaV9.self,
            PeakSchemaV10.self,
            PeakSchemaV11.self,
            PeakSchemaV12.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: PeakSchemaV1.self, toVersion: PeakSchemaV2.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV2.self, toVersion: PeakSchemaV3.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV3.self, toVersion: PeakSchemaV4.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV4.self, toVersion: PeakSchemaV5.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV5.self, toVersion: PeakSchemaV6.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV6.self, toVersion: PeakSchemaV7.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV7.self, toVersion: PeakSchemaV8.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV8.self, toVersion: PeakSchemaV9.self),
            MigrationStage.lightweight(fromVersion: PeakSchemaV9.self, toVersion: PeakSchemaV10.self),
            MigrationStage.custom(
                fromVersion: PeakSchemaV10.self,
                toVersion: PeakSchemaV11.self,
                willMigrate: { context in
                    let sessions = try context.fetch(FetchDescriptor<PeakSchemaV10.SurfSession>())
                    let snapshots = Dictionary(uniqueKeysWithValues: try sessions.map { session in
                        (
                            try migrationKey(for: session.persistentModelID),
                            V10RelationshipSnapshot(
                                gearKeys: session.gear.map(\.key),
                                buddyKeys: session.buddies.map(\.key)
                            )
                        )
                    })
                    v10RelationshipBridge.replace(with: snapshots)
                },
                didMigrate: { context in
                    let snapshots = v10RelationshipBridge.take()
                    let gearByKey = Dictionary(uniqueKeysWithValues:
                        try context.fetch(FetchDescriptor<PeakSchemaV11.Gear>()).map { ($0.key, $0) }
                    )
                    let buddiesByKey = Dictionary(uniqueKeysWithValues:
                        try context.fetch(FetchDescriptor<PeakSchemaV11.Buddy>()).map { ($0.key, $0) }
                    )
                    let sessions = try context.fetch(FetchDescriptor<PeakSchemaV11.SurfSession>())
                    for session in sessions {
                        guard let snapshot = snapshots[try migrationKey(for: session.persistentModelID)] else { continue }
                        session.gear = snapshot.gearKeys.compactMap { gearByKey[$0] }
                        session.buddies = snapshot.buddyKeys.compactMap { buddiesByKey[$0] }
                    }
                    try context.save()
                }
            ),
            MigrationStage.custom(
                fromVersion: PeakSchemaV11.self,
                toVersion: PeakSchemaV12.self,
                willMigrate: nil,
                didMigrate: { context in
                    for session in try context.fetch(FetchDescriptor<SurfSession>()) {
                        if session.sessionID == nil { session.sessionID = UUID() }
                    }
                    try context.save()
                }
            )
        ]
    }

    private static func migrationKey(for identifier: PersistentIdentifier) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(identifier)
    }
}
