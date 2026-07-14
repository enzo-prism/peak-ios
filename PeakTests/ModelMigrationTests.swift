import SwiftData
import XCTest

@testable import Peak

final class ModelMigrationTests: XCTestCase {
    func testContainerInitializesWithMigrationPlan() {
        let schema = Schema(versionedSchema: PeakSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        XCTAssertNoThrow(try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration]))
    }

    func testContainerInitializesAtLatestSchema() {
        let schema = Schema(versionedSchema: PeakSchemaV8.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        XCTAssertNoThrow(try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration]))
    }

    /// Real on-disk V7 -> V8 round-trip: an in-memory store starts fresh at HEAD and never runs the
    /// staged migration, so we must write a V7 store and reopen it at V8 to exercise the lightweight
    /// stage and prove the new media fields backfill to their defaults (catches frozen-copy drift).
    func testV7ToV8MigrationBackfillsMediaDefaults() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peak-migration-\(UUID().uuidString)")
            .appendingPathExtension("store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // 1. Create the store at the frozen V7 shape and insert a media row.
        do {
            let schema = Schema(versionedSchema: PeakSchemaV7.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(PeakSchemaV7.SessionMedia(kind: .photo, createdAt: Date(timeIntervalSince1970: 1_000)))
            try context.save()
        }

        // 2. Reopen the SAME store at the latest schema; the V7 -> V8 stage must run and backfill.
        let schema = Schema(versionedSchema: PeakSchemaV8.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(container)
        let media = try context.fetch(FetchDescriptor<SessionMedia>())
        XCTAssertEqual(media.count, 1)
        let item = try XCTUnwrap(media.first)
        XCTAssertEqual(item.sortIndex, 0)
        XCTAssertEqual(item.cropOriginX, 0, accuracy: 0.0001)
        XCTAssertEqual(item.cropOriginY, 0, accuracy: 0.0001)
        XCTAssertEqual(item.cropWidth, 1, accuracy: 0.0001)
        XCTAssertEqual(item.cropHeight, 1, accuracy: 0.0001)
    }

    /// Guards the "HEAD schema references the live models" convention. `PeakSchemaV8` is HEAD and its
    /// `models` are the live `@Model` classes, so editing a model field silently redefines the shipped
    /// 1.7.0 schema — and a store already at 1.7.0 then fails to open and is shunted to the recovery
    /// archive. This test pins HEAD's shape. When it fails: FREEZE the current HEAD as an inline
    /// `PeakSchemaVn` snapshot, add a new live-referencing HEAD carrying the real field delta plus a
    /// `.lightweight` stage, point `PeakDataStore` at the new HEAD, then update `expected` below.
    /// (SwiftData rejects two identical-shape schemas in one plan — "duplicate version checksums" — so
    /// the freeze is only valid alongside a genuine shape change, which is exactly when this fires.)
    func testHeadSchemaShapeIsPinned() throws {
        let schema = Schema(versionedSchema: PeakSchemaV8.self)
        var actual: [String: [String]] = [:]
        for entity in schema.entities {
            actual[entity.name] = (entity.attributes.map(\.name) + entity.relationships.map(\.name)).sorted()
        }

        let expected: [String: [String]] = [
            "Spot": ["createdAt", "key", "latitude", "locationName", "longitude", "name"],
            "Gear": ["brand", "createdAt", "isArchived", "key", "kind", "model", "name", "notes", "photoData", "size", "volumeLiters"],
            "Buddy": ["createdAt", "key", "name"],
            "SessionMedia": ["createdAt", "cropHeight", "cropOriginX", "cropOriginY", "cropWidth", "kind", "photoData", "sortIndex", "thumbnailData", "videoFileName"],
            "SurfSession": ["buddies", "conditionsFetchedAt", "conditionsLatitude", "conditionsLongitude", "conditionsSource", "createdAt", "date", "durationMinutes", "gear", "media", "notes", "rating", "seaSurfaceTemperatureC", "spot", "swellWaveDirectionDegrees", "swellWaveHeightMeters", "swellWavePeriodSeconds", "updatedAt", "waveHeight", "waveHeightMeters", "windCondition", "windDirectionDegrees", "windSpeedKph", "windWaveDirectionDegrees", "windWaveHeightMeters", "windWavePeriodSeconds"],
        ]

        XCTAssertEqual(
            actual,
            expected,
            "HEAD (PeakSchemaV8) model shape changed. Freeze it as a versioned snapshot + add a new HEAD/stage before changing model fields, then update `expected`."
        )
    }
}
