import SwiftData

enum PeakSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SurfSession.self, Spot.self, Gear.self, Buddy.self]
    }
}

enum PeakMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PeakSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
