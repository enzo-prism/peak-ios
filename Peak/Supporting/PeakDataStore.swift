import Foundation
import OSLog
import SwiftData

/// Centralized SwiftData container creation with graceful recovery.
///
/// A failed migration or a corrupt store must never crash the app on launch. Instead we:
/// 1. Try the normal on-disk store (running the migration plan).
/// 2. If that fails, move the existing store aside (so the user's data is preserved for support)
///    and start fresh.
/// 3. If even that fails, fall back to an in-memory store so the app still launches.
///
/// `shared` is the single process-wide container. The app uses it for normal runs, and App Intents
/// reuse it so foreground intents write to the same store the UI reads from.
enum PeakDataStore {
    enum LoadState: Equatable {
        case healthy
        case recoveredFromCorruption(backupName: String)
        case inMemoryFallback
    }

    struct Result {
        let container: ModelContainer
        let state: LoadState
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.designprism.peak", category: "DataStore")

    /// Process-wide container for normal (on-disk) runs. Shared with App Intents.
    static let shared: Result = makeContainer()

    static func makeContainer(inMemory: Bool = false) -> Result {
        let schema = Schema(versionedSchema: PeakSchemaV7.self)

        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration]) {
                return Result(container: container, state: .inMemoryFallback)
            }
            // In-memory creation should never fail; if it somehow does there is nothing left to try.
            return Result(container: try! ModelContainer(for: schema, configurations: [configuration]), state: .inMemoryFallback)
        }

        let configuration = ModelConfiguration(schema: schema)

        // 1. Normal load (with migration).
        do {
            let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
            return Result(container: container, state: .healthy)
        } catch {
            logger.error("Store load failed; attempting recovery: \(String(describing: error))")
        }

        // 2. Archive the existing store and start fresh.
        let backupName = archiveExistingStore()
        do {
            let container = try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
            return Result(container: container, state: .recoveredFromCorruption(backupName: backupName ?? "backup"))
        } catch {
            logger.error("Fresh store load failed; falling back to in-memory: \(String(describing: error))")
        }

        // 3. In-memory fallback so the app still launches (changes won't persist).
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [memoryConfiguration]) {
            return Result(container: container, state: .inMemoryFallback)
        }

        fatalError("Unable to initialize any SwiftData store")
    }

    /// Location of SwiftData's default on-disk store.
    private static var defaultStoreURL: URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        return appSupport.appendingPathComponent("default.store")
    }

    /// Moves the existing store (and its `-wal`/`-shm` sidecars) aside so a fresh one can be created.
    /// Returns the backup file name when something was preserved.
    @discardableResult
    private static func archiveExistingStore() -> String? {
        guard let storeURL = defaultStoreURL else { return nil }
        let fileManager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = ".corrupt-\(stamp)"
        var movedAny = false

        for sidecar in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + sidecar)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: storeURL.path + sidecar + suffix)
            do {
                try fileManager.moveItem(at: source, to: destination)
                movedAny = true
            } catch {
                // If it can't be moved, remove it so a fresh store can be created.
                try? fileManager.removeItem(at: source)
            }
        }

        return movedAny ? "\(storeURL.lastPathComponent)\(suffix)" : nil
    }
}
