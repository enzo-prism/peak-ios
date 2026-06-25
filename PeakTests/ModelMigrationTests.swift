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
}
