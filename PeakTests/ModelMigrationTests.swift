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
        let schema = Schema(versionedSchema: PeakSchemaV10.self)
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
        let schema = Schema(versionedSchema: PeakSchemaV10.self)
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

    /// Real on-disk V8 -> V9 round-trip. Writes a session and a spot at the frozen 1.7.0 shape, then
    /// reopens the same store at HEAD and proves the three new tide columns arrive as `nil` without
    /// disturbing anything already stored. An in-memory store would start fresh at HEAD and never
    /// run the stage, so this has to touch the disk.
    func testV8ToV9MigrationAddsTideFieldsAsNil() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peak-migration-v9-\(UUID().uuidString)")
            .appendingPathExtension("store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let sessionDate = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let schema = Schema(versionedSchema: PeakSchemaV8.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
            let context = ModelContext(container)
            let spot = PeakSchemaV8.Spot(name: "Frozen Point", latitude: 33.5, longitude: -117.8)
            context.insert(spot)
            context.insert(PeakSchemaV8.SurfSession(
                date: sessionDate,
                spot: spot,
                rating: 4,
                swellWaveHeightMeters: 1.2,
                seaSurfaceTemperatureC: 17.5
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: PeakSchemaV10.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(container)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertNil(session.seaLevelHeightM)
        XCTAssertNil(session.tideTrend)
        XCTAssertNil(session.tide)
        // Pre-existing columns survive untouched.
        XCTAssertEqual(session.date, sessionDate)
        XCTAssertEqual(session.rating, 4)
        XCTAssertEqual(session.swellWaveHeightMeters ?? 0, 1.2, accuracy: 0.0001)
        XCTAssertEqual(session.seaSurfaceTemperatureC ?? 0, 17.5, accuracy: 0.0001)

        let spots = try context.fetch(FetchDescriptor<Spot>())
        let spot = try XCTUnwrap(spots.first)
        XCTAssertNil(spot.tideStationId)
        XCTAssertEqual(spot.name, "Frozen Point")

        // The new columns are writable after the migration, not merely present.
        session.tide = .falling
        session.seaLevelHeightM = -0.4
        spot.tideStationId = "9410230"
        try context.save()
        XCTAssertEqual(session.tideTrend, "falling")
    }

    /// Real on-disk V9 -> V10 round-trip. Writes a session at the frozen 1.8.0 shape, then reopens the
    /// same store at HEAD and proves the seven new wave-stat columns arrive as `nil` without disturbing
    /// anything already stored (including the 2.8 tide columns, which are the closest thing to a
    /// regression target here). Mirrors `testV8ToV9MigrationAddsTideFieldsAsNil`; like it, this has to
    /// touch the disk, because an in-memory store starts fresh at HEAD and never runs the stage.
    func testV9ToV10MigrationAddsWaveStatFieldsAsNil() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peak-migration-v10-\(UUID().uuidString)")
            .appendingPathExtension("store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let sessionDate = Date(timeIntervalSince1970: 1_710_000_000)

        do {
            let schema = Schema(versionedSchema: PeakSchemaV9.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
            let context = ModelContext(container)
            let spot = PeakSchemaV9.Spot(name: "Frozen Reef", latitude: 21.27, longitude: -157.82, tideStationId: "1612340")
            context.insert(spot)
            context.insert(PeakSchemaV9.SurfSession(
                date: sessionDate,
                spot: spot,
                rating: 5,
                durationMinutes: 90,
                swellWavePeriodSeconds: 13.5,
                seaLevelHeightM: 0.8,
                tideTrend: "rising"
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: PeakSchemaV10.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(container)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertNil(session.waveCount)
        XCTAssertNil(session.topSpeedKph)
        XCTAssertNil(session.longestRideSeconds)
        XCTAssertNil(session.longestRideMeters)
        XCTAssertNil(session.paddleDistanceMeters)
        XCTAssertNil(session.waveStatsSource)
        XCTAssertNil(session.waveStats)
        XCTAssertNil(session.linkedWorkoutID)
        XCTAssertFalse(session.hasWaveStats)

        // Everything the 2.8 stage wrote survives the 3.0 stage untouched.
        XCTAssertEqual(session.date, sessionDate)
        XCTAssertEqual(session.rating, 5)
        XCTAssertEqual(session.durationMinutes, 90)
        XCTAssertEqual(session.swellWavePeriodSeconds ?? 0, 13.5, accuracy: 0.0001)
        XCTAssertEqual(session.seaLevelHeightM ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(session.tide, .rising)

        let spots = try context.fetch(FetchDescriptor<Spot>())
        let spot = try XCTUnwrap(spots.first)
        XCTAssertEqual(spot.tideStationId, "1612340")
        XCTAssertEqual(spot.name, "Frozen Reef")

        // The new columns are writable after the migration, not merely present.
        session.waveCount = 12
        session.topSpeedKph = 27.4
        session.longestRideSeconds = 18
        session.longestRideMeters = 84
        session.paddleDistanceMeters = 1_450
        session.waveStats = .auto
        session.linkedWorkoutID = "8B2A1C4D-0000-4000-8000-000000000000"
        try context.save()
        XCTAssertEqual(session.waveStatsSource, "auto")
        XCTAssertTrue(session.hasWaveStats)
    }

    /// Guards the "HEAD schema references the live models" convention. `PeakSchemaV10` is HEAD and its
    /// `models` are the live `@Model` classes, so editing a model field silently redefines the shipped
    /// 1.9.0 schema — and a store already at 1.9.0 then fails to open and is shunted to the recovery
    /// archive. This test pins HEAD's shape. When it fails: FREEZE the current HEAD as an inline
    /// `PeakSchemaVn` snapshot, add a new live-referencing HEAD carrying the real field delta plus a
    /// `.lightweight` stage, point `PeakDataStore` at the new HEAD, then update `expected` below.
    /// (SwiftData rejects two identical-shape schemas in one plan — "duplicate version checksums" — so
    /// the freeze is only valid alongside a genuine shape change, which is exactly when this fires.)
    func testHeadSchemaShapeIsPinned() throws {
        let schema = Schema(versionedSchema: PeakSchemaV10.self)
        var actual: [String: [String]] = [:]
        for entity in schema.entities {
            actual[entity.name] = (entity.attributes.map(\.name) + entity.relationships.map(\.name)).sorted()
        }

        let expected: [String: [String]] = [
            "Spot": ["createdAt", "key", "latitude", "locationName", "longitude", "name", "tideStationId"],
            "Gear": ["brand", "createdAt", "isArchived", "key", "kind", "model", "name", "notes", "photoData", "size", "volumeLiters"],
            "Buddy": ["createdAt", "key", "name"],
            "SessionMedia": ["createdAt", "cropHeight", "cropOriginX", "cropOriginY", "cropWidth", "kind", "photoData", "sortIndex", "thumbnailData", "videoFileName"],
            "SurfSession": ["buddies", "conditionsFetchedAt", "conditionsLatitude", "conditionsLongitude", "conditionsSource", "createdAt", "date", "durationMinutes", "gear", "linkedWorkoutID", "longestRideMeters", "longestRideSeconds", "media", "notes", "paddleDistanceMeters", "rating", "seaLevelHeightM", "seaSurfaceTemperatureC", "spot", "swellWaveDirectionDegrees", "swellWaveHeightMeters", "swellWavePeriodSeconds", "tideTrend", "topSpeedKph", "updatedAt", "waveCount", "waveHeight", "waveHeightMeters", "waveStatsSource", "windCondition", "windDirectionDegrees", "windSpeedKph", "windWaveDirectionDegrees", "windWaveHeightMeters", "windWavePeriodSeconds"],
        ]

        XCTAssertEqual(
            actual,
            expected,
            "HEAD (PeakSchemaV10) model shape changed. Freeze it as a versioned snapshot + add a new HEAD/stage before changing model fields, then update `expected`."
        )
    }

    /// The frozen 1.8.0 snapshot must stay frozen. If a later change accidentally edits `PeakSchemaV9`
    /// instead of adding a new HEAD, every store already migrated to 1.8.0 sees a shape that no longer
    /// matches its recorded checksum. Note this is the *frozen* shape: it deliberately carries the tide
    /// columns but none of the 3.0 wave-stat ones.
    func testFrozenV9SnapshotShapeIsPinned() throws {
        let schema = Schema(versionedSchema: PeakSchemaV9.self)
        var actual: [String: [String]] = [:]
        for entity in schema.entities {
            actual[entity.name] = (entity.attributes.map(\.name) + entity.relationships.map(\.name)).sorted()
        }

        let expected: [String: [String]] = [
            "Spot": ["createdAt", "key", "latitude", "locationName", "longitude", "name", "tideStationId"],
            "Gear": ["brand", "createdAt", "isArchived", "key", "kind", "model", "name", "notes", "photoData", "size", "volumeLiters"],
            "Buddy": ["createdAt", "key", "name"],
            "SessionMedia": ["createdAt", "cropHeight", "cropOriginX", "cropOriginY", "cropWidth", "kind", "photoData", "sortIndex", "thumbnailData", "videoFileName"],
            "SurfSession": ["buddies", "conditionsFetchedAt", "conditionsLatitude", "conditionsLongitude", "conditionsSource", "createdAt", "date", "durationMinutes", "gear", "media", "notes", "rating", "seaLevelHeightM", "seaSurfaceTemperatureC", "spot", "swellWaveDirectionDegrees", "swellWaveHeightMeters", "swellWavePeriodSeconds", "tideTrend", "updatedAt", "waveHeight", "waveHeightMeters", "windCondition", "windDirectionDegrees", "windSpeedKph", "windWaveDirectionDegrees", "windWaveHeightMeters", "windWavePeriodSeconds"],
        ]

        XCTAssertEqual(actual, expected, "The frozen PeakSchemaV9 snapshot changed. It must never change again.")
    }

    /// The frozen 1.7.0 snapshot must stay frozen. If a later change accidentally edits `PeakSchemaV8`
    /// instead of adding a new HEAD, every store already migrated to 1.7.0 sees a shape that no longer
    /// matches its recorded checksum.
    func testFrozenV8SnapshotShapeIsPinned() throws {
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

        XCTAssertEqual(actual, expected, "The frozen PeakSchemaV8 snapshot changed. It must never change again.")
    }
}
