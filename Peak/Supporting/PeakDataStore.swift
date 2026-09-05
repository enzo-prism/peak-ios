import Foundation
import SwiftData

/// Details retained for recovery, without exposing filesystem paths in the UI.
nonisolated struct StoreRecoveryIssue: Error, Equatable, Codable, Sendable {
    let archivedPath: String?
    let details: String
}

/// How the persistent store was opened at launch.
enum StoreLoadOutcome: Equatable {
    case normal
    case recoveredFresh(archivedPath: String)
    /// Changes made in this container cannot survive closing the app.
    case inMemoryFallback(recovery: StoreRecoveryIssue)
}

struct StoreLoadResult {
    let container: ModelContainer
    let outcome: StoreLoadOutcome
}

/// Never retries an on-disk store after unsuccessful preservation. A durable
/// marker also prevents reopening a partly removed store on the next launch.
enum PeakDataStore {
    private static let storeFileName = "default.store"
    nonisolated static let recoveryMarkerName = "Peak Store Recovery.json"
    nonisolated static let recoveryRecordName = "Peak Preserved Library.json"
    static let headSchema: any VersionedSchema.Type = PeakSchemaV12.self

    static func load(isUITest: Bool) -> StoreLoadResult {
        let schema = Schema(versionedSchema: headSchema)
        if isUITest {
            return StoreLoadResult(container: makeInMemoryOrCrash(schema: schema), outcome: .normal)
        }
        return loadPersistent(
            open: { try makeContainer(schema: schema, inMemory: false) },
            fallback: { makeInMemoryOrCrash(schema: schema) },
            recover: { try archiveDefaultStore() },
            pending: { try pendingRecovery(in: applicationSupport()) },
            preservedArchive: { try preservedArchive(in: applicationSupport()) }
        )
    }

    /// Dependency seam for failure-path tests; production and tests use the same
    /// ordering, including checking an interrupted recovery before opening disk.
    static func loadPersistent(
        open: () throws -> ModelContainer,
        fallback: () -> ModelContainer,
        recover: () throws -> URL,
        pending: () throws -> StoreRecoveryIssue?,
        preservedArchive: () throws -> String? = { nil }
    ) -> StoreLoadResult {
        func temporary(_ issue: StoreRecoveryIssue) -> StoreLoadResult {
            StoreLoadResult(container: fallback(), outcome: .inMemoryFallback(recovery: issue))
        }
        let previousArchive: String?
        do {
            if let issue = try pending() { return temporary(issue) }
            previousArchive = try preservedArchive()
        } catch {
            return temporary(StoreRecoveryIssue(archivedPath: nil, details: "Could not check previous recovery: \(error.localizedDescription)"))
        }
        do {
            let container = try open()
            return StoreLoadResult(container: container, outcome: previousArchive.map { .recoveredFresh(archivedPath: $0) } ?? .normal)
        } catch {
            let originalError = error.localizedDescription
            let archive: URL
            do {
                archive = try recover()
            } catch {
                let issue = error as? StoreRecoveryIssue
                return temporary(StoreRecoveryIssue(
                    archivedPath: issue?.archivedPath,
                    details: "Library could not open: \(originalError). Preservation failed: \(issue?.details ?? error.localizedDescription)"
                ))
            }
            do {
                return StoreLoadResult(container: try open(), outcome: .recoveredFresh(archivedPath: archive.path))
            } catch {
                return temporary(StoreRecoveryIssue(archivedPath: archive.path, details: "Old library preserved; fresh library could not open: \(error.localizedDescription)"))
            }
        }
    }

    private static func makeContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration])
    }

    private static func makeInMemoryOrCrash(schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Peak could not open any data store, even in memory: \(error)")
        }
    }

    nonisolated private static func applicationSupport() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// A pending marker is deliberately not cleared automatically: a previous
    /// launch may have stopped between removing two related SQLite components.
    nonisolated static func pendingRecovery(in directory: URL) throws -> StoreRecoveryIssue? {
        let marker = directory.appendingPathComponent(recoveryMarkerName)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        return try JSONDecoder().decode(StoreRecoveryIssue.self, from: Data(contentsOf: marker))
    }

    /// Unlike the blocking marker, this receipt remains after a successful
    /// recovery, keeping the recovery notice and export available next launch.
    nonisolated static func preservedArchive(in directory: URL) throws -> String? {
        let receipt = directory.appendingPathComponent(recoveryRecordName)
        guard FileManager.default.fileExists(atPath: receipt.path) else { return nil }
        let issue = try JSONDecoder().decode(StoreRecoveryIssue.self, from: Data(contentsOf: receipt))
        guard let path = issue.archivedPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    /// Cold App Intents must also avoid opening an interrupted recovery store.
    nonisolated static func canOpenStore(in directory: URL) -> Bool {
        do { return try pendingRecovery(in: directory) == nil } catch { return false }
    }

    nonisolated static func canOpenDefaultStore() -> Bool {
        do { return canOpenStore(in: try applicationSupport()) } catch { return false }
    }

    @discardableResult
    nonisolated static func archiveDefaultStore(now: Date = Date()) throws -> URL {
        try relocateStoreFiles(in: applicationSupport(), storeName: storeFileName, now: now)
    }

    /// Copies every component before removing any original. If a copy, removal,
    /// or marker operation fails, the error is propagated and disk reopening is
    /// blocked. A complete archive survives even a partial removal or crash.
    @discardableResult
    nonisolated static func relocateStoreFiles(
        in directory: URL,
        storeName: String = "default.store",
        now: Date = Date(),
        copyItem: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) throws -> URL {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(recoveryMarkerName)
        if let issue = try pendingRecovery(in: directory) { throw issue }
        let stamp = ExportDateFormatter.fileSafeString(from: now)
        let archive = directory.appendingPathComponent("Archived Store \(stamp) \(UUID().uuidString)", isDirectory: true)
        let baseName = (storeName as NSString).deletingPathExtension
        let sources = [storeName, "\(storeName)-wal", "\(storeName)-shm", ".\(baseName)_SUPPORT"]
            .map { directory.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
        // No source is not proof that a library was preserved.
        guard !sources.isEmpty else {
            throw StoreRecoveryIssue(archivedPath: nil, details: "No existing library files could be found to preserve.")
        }
        var completeArchive: String?
        do {
            try fm.createDirectory(at: archive, withIntermediateDirectories: false)
            let started = StoreRecoveryIssue(archivedPath: nil, details: "Library preservation was interrupted before a complete copy was confirmed. Original files have not been removed.")
            try JSONEncoder().encode(started).write(to: marker, options: .atomic)
            for source in sources {
                try copyItem(source, archive.appendingPathComponent(source.lastPathComponent))
            }
            // Write the complete archive location BEFORE removing any source.
            completeArchive = archive.path
            let preserved = StoreRecoveryIssue(archivedPath: archive.path, details: "A complete library copy was preserved, but preparing a fresh library did not finish.")
            try JSONEncoder().encode(preserved).write(to: marker, options: .atomic)
            try JSONEncoder().encode(preserved).write(to: directory.appendingPathComponent(recoveryRecordName), options: .atomic)
            for source in sources { try removeItem(source) }
            try removeItem(marker)
            return archive
        } catch {
            throw StoreRecoveryIssue(archivedPath: completeArchive, details: "\(error.localizedDescription) Recovery files: \(archive.path)")
        }
    }

    /// Produces a system-coordinated ZIP for Save to Files/support. The original
    /// archive stays untouched; exporting is always an explicit user action.
    nonisolated static func recoveryExport(archivedPath: String) throws -> URL {
        let archive = URL(fileURLWithPath: archivedPath, isDirectory: true)
        var coordinationError: NSError?
        var exportResult: Result<URL, Error>?
        NSFileCoordinator().coordinate(readingItemAt: archive, options: .forUploading, error: &coordinationError) { zippedURL in
            exportResult = Result {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Peak Recovery \(UUID().uuidString).zip")
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        guard let exportResult else {
            throw StoreRecoveryIssue(archivedPath: archivedPath, details: "Could not prepare the recovery copy for export.")
        }
        return try exportResult.get()
    }
}
