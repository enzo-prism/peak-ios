import Foundation
import SwiftData

/// How the persistent store was opened at launch.
enum StoreLoadOutcome: Equatable {
    /// Opened the on-disk store normally (or the in-memory UI-test store).
    case normal
    /// The on-disk store couldn't be opened; the old files were archived to
    /// `archivedPath` and a fresh empty store was created in their place.
    case recoveredFresh(archivedPath: String)
    /// Even a fresh on-disk store failed; running against an in-memory store
    /// whose contents will not persist across launches.
    case inMemoryFallback
}

/// The container plus how it was obtained.
struct StoreLoadResult {
    let container: ModelContainer
    let outcome: StoreLoadOutcome
}

/// Crash-proof store opener. Replaces PeakApp's `fatalError` with a tiered
/// recovery path: normal on-disk → archive the corrupt store + retry fresh →
/// in-memory fallback. Only a total failure to build even an in-memory
/// container is treated as unrecoverable.
enum PeakDataStore {
    private static let storeFileName = "default.store"

    static func load(isUITest: Bool) -> StoreLoadResult {
        let schema = Schema(versionedSchema: PeakSchemaV10.self)

        // UI tests always run against a fresh in-memory store (seeded by PeakApp).
        if isUITest {
            if let container = try? makeContainer(schema: schema, inMemory: true) {
                return StoreLoadResult(container: container, outcome: .normal)
            }
            return StoreLoadResult(container: makeInMemoryOrCrash(schema: schema), outcome: .inMemoryFallback)
        }

        // Tier 1: normal on-disk store.
        do {
            let container = try makeContainer(schema: schema, inMemory: false)
            return StoreLoadResult(container: container, outcome: .normal)
        } catch {
            // Tier 2: archive the unreadable store files, then retry a fresh on-disk store.
            let archivedPath = (try? archiveDefaultStore())?.path ?? "unknown"
            if let container = try? makeContainer(schema: schema, inMemory: false) {
                return StoreLoadResult(
                    container: container,
                    outcome: .recoveredFresh(archivedPath: archivedPath)
                )
            }

            // Tier 3: in-memory fallback (data won't persist, but the app runs).
            return StoreLoadResult(
                container: makeInMemoryOrCrash(schema: schema),
                outcome: .inMemoryFallback
            )
        }
    }

    // MARK: - Container construction

    private static func makeContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: PeakMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Last resort. A plain in-memory container with no migration plan should
    /// never fail; if it does the process is truly unrecoverable.
    private static func makeInMemoryOrCrash(schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Peak could not open any data store, even in memory: \(error)")
        }
    }

    // MARK: - Corrupt-store archival

    /// Moves the default on-disk store (and its sidecar/external-storage files)
    /// out of Application Support into a timestamped "Archived Store …" folder.
    /// Returns the archive directory. Nothing is deleted — the user's bytes are
    /// preserved for later recovery.
    @discardableResult
    nonisolated static func archiveDefaultStore(now: Date = Date()) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try relocateStoreFiles(in: appSupport, storeName: storeFileName, now: now)
    }

    /// Pure, testable file-relocation helper: moves `<storeName>` plus its
    /// `-wal`/`-shm` sidecars and the `.<base>_SUPPORT` external-storage folder
    /// from `directory` into a fresh "Archived Store <stamp>" subfolder, which
    /// it returns. Missing files are skipped.
    @discardableResult
    nonisolated static func relocateStoreFiles(
        in directory: URL,
        storeName: String = "default.store",
        now: Date = Date()
    ) throws -> URL {
        let fm = FileManager.default
        let stamp = ExportDateFormatter.fileSafeString(from: now)
        let archiveDir = directory.appendingPathComponent("Archived Store \(stamp)", isDirectory: true)
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)

        let baseName = (storeName as NSString).deletingPathExtension
        let candidates = [
            storeName,
            "\(storeName)-wal",
            "\(storeName)-shm",
            ".\(baseName)_SUPPORT"
        ]

        for name in candidates {
            let source = directory.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = archiveDir.appendingPathComponent(name)
            try? fm.moveItem(at: source, to: destination)
        }

        return archiveDir
    }
}
