import Foundation
import SwiftData
import UIKit

/// Details retained for recovery, without exposing filesystem paths in the UI.
nonisolated struct StoreRecoveryIssue: Error, Equatable, Codable, Sendable {
    let archivedPath: String?
    let details: String
    let phase: Phase?
    /// Relative to the selected store directory; survives a sandbox relocation.
    let archiveDirectory: String?

    nonisolated enum Phase: String, Codable, Sendable {
        case copying
        case removing
    }

    init(archivedPath: String?, details: String, phase: Phase? = nil, archiveDirectory: String? = nil) {
        self.archivedPath = archivedPath
        self.details = details
        self.phase = phase
        self.archiveDirectory = archiveDirectory
    }
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

/// Opens the on-disk library when it is safe, and archives only when the store
/// is genuinely unreadable. Transient failures stay in memory for this launch.
enum PeakDataStore {
    nonisolated static let recoveryMarkerName = "Peak Store Recovery.json"
    nonisolated static let recoveryRecordName = "Peak Preserved Library.json"
    static let headSchema: any VersionedSchema.Type = PeakSchemaV12.self

    static func load(isUITest: Bool) -> StoreLoadResult {
        let schema = Schema(versionedSchema: headSchema)
        if isUITest {
            return StoreLoadResult(container: makeInMemoryOrCrash(schema: schema), outcome: .normal)
        }
        let configuration = ModelConfiguration(schema: schema)
        return loadPersistent(
            configuration: configuration,
            mediaDirectory: SessionMediaStore.recoveryDirectoryURL,
            legacyArchiveDirectory: try? applicationSupport(),
            open: { try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration]) },
            fallback: { makeInMemoryOrCrash(schema: schema) }
        )
    }

    /// SwiftData's automatic configuration uses the primary App Group. Recovery
    /// must use that exact URL, while videos can live in the app's private folder.
    static func loadPersistent(
        configuration: ModelConfiguration,
        mediaDirectory: () throws -> URL,
        legacyArchiveDirectory: URL? = nil,
        open: () throws -> ModelContainer,
        fallback: () -> ModelContainer,
        isProtectedDataAvailable: @escaping () -> Bool = { PeakDataStore.protectedDataAvailable() },
        availableCapacity: @escaping (URL) -> Int64? = { PeakDataStore.volumeCapacity(for: $0) }
    ) -> StoreLoadResult {
        let directory = configuration.url.deletingLastPathComponent()
        return loadPersistent(
            open: open,
            fallback: fallback,
            recover: {
                let media = try mediaDirectory()
                return try relocateStoreFiles(
                    in: directory,
                    storeName: configuration.url.lastPathComponent,
                    mediaDirectory: media,
                    isProtectedDataAvailable: isProtectedDataAvailable,
                    availableCapacity: availableCapacity
                )
            },
            pending: { try pendingRecovery(in: directory) },
            preservedArchive: {
                if let current = try preservedArchive(in: directory) { return current }
                guard let legacyArchiveDirectory,
                      legacyArchiveDirectory.standardizedFileURL.path != directory.standardizedFileURL.path else { return nil }
                return try preservedArchive(in: legacyArchiveDirectory)
            },
            isProtectedDataAvailable: isProtectedDataAvailable,
            clearIncompleteRecovery: { try abandonIncompleteCopy(in: directory) }
        )
    }

    /// Dependency seam for failure-path tests; production and tests use the same
    /// ordering: open first, archive only for genuine corruption/incompatibility.
    static func loadPersistent(
        open: () throws -> ModelContainer,
        fallback: () -> ModelContainer,
        recover: () throws -> URL,
        pending: () throws -> StoreRecoveryIssue?,
        preservedArchive: () throws -> String? = { nil },
        isProtectedDataAvailable: () -> Bool = { true },
        clearIncompleteRecovery: () throws -> Void = { }
    ) -> StoreLoadResult {
        func temporary(_ issue: StoreRecoveryIssue) -> StoreLoadResult {
            StoreLoadResult(container: fallback(), outcome: .inMemoryFallback(recovery: issue))
        }
        func healthy(_ container: ModelContainer) -> StoreLoadResult {
            let previousArchive = try? preservedArchive()
            return StoreLoadResult(container: container, outcome: previousArchive.map { .recoveredFresh(archivedPath: $0) } ?? .normal)
        }
        func recoverAndOpen(reason: String, existing: StoreRecoveryIssue? = nil) -> StoreLoadResult {
            guard isProtectedDataAvailable() else {
                return temporary(StoreRecoveryIssue(
                    archivedPath: existing?.archivedPath,
                    details: "\(reason). Protected data is not available yet. Original files have not been changed. Peak will retry on the next launch.",
                    phase: existing?.phase,
                    archiveDirectory: existing?.archiveDirectory
                ))
            }
            let archive: URL
            do {
                archive = try recover()
            } catch {
                let issue = error as? StoreRecoveryIssue
                return temporary(StoreRecoveryIssue(
                    archivedPath: issue?.archivedPath,
                    details: "\(reason). Preservation failed: \(issue?.details ?? error.localizedDescription)",
                    phase: issue?.phase,
                    archiveDirectory: issue?.archiveDirectory
                ))
            }
            do {
                return StoreLoadResult(container: try open(), outcome: .recoveredFresh(archivedPath: archive.path))
            } catch {
                return temporary(StoreRecoveryIssue(archivedPath: archive.path, details: "Old library preserved; fresh library could not open: \(error.localizedDescription)"))
            }
        }
        func openOrHold(reason prefix: String) -> StoreLoadResult {
            do {
                return healthy(try open())
            } catch {
                let reason = "\(prefix)\(error.localizedDescription)"
                if isArchiveWorthy(error) { return recoverAndOpen(reason: reason) }
                return temporary(StoreRecoveryIssue(
                    archivedPath: nil,
                    details: "\(reason). Original files have not been changed. Peak will retry on the next launch.",
                    phase: nil
                ))
            }
        }
        do {
            if let issue = try pending() {
                if issue.phase == .copying {
                    do {
                        let container = try open()
                        try? clearIncompleteRecovery()
                        return healthy(container)
                    } catch {
                        if isArchiveWorthy(error) { return recoverAndOpen(reason: issue.details, existing: issue) }
                        return temporary(StoreRecoveryIssue(
                            archivedPath: nil,
                            details: "Library could not open: \(error.localizedDescription). Original files have not been changed. Peak will retry on the next launch.",
                            phase: .copying
                        ))
                    }
                }
                if issue.phase == .removing {
                    return recoverAndOpen(reason: issue.details, existing: issue)
                }
                return temporary(issue)
            }
        } catch {
            return temporary(StoreRecoveryIssue(archivedPath: nil, details: "Could not check previous recovery: \(error.localizedDescription)"))
        }
        // A historical receipt is advisory. Damage to it must never disable a
        // healthy current library; only a removing-phase marker can block disk access.
        return openOrHold(reason: "Library could not open: ")
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

    /// Copying leaves originals intact, so the next launch can open them. A
    /// complete archive in the removing phase is finished rather than re-copied.
    nonisolated static func pendingRecovery(in directory: URL) throws -> StoreRecoveryIssue? {
        let marker = directory.appendingPathComponent(recoveryMarkerName)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let record = try JSONDecoder().decode(StoreRecoveryIssue.self, from: Data(contentsOf: marker))
        // A relative-format record without its phase is damaged, not a legacy
        // pre-removal marker. Never infer copying from that incomplete record.
        if record.archiveDirectory != nil && record.phase == nil {
            throw CocoaError(.fileReadCorruptFile)
        }
        // The previous format wrote nil only before removing any originals.
        let phase = record.phase ?? (record.archivedPath == nil ? .copying : .removing)
        return StoreRecoveryIssue(
            archivedPath: phase == .removing ? archiveURL(for: record, in: directory)?.path : nil,
            details: record.details,
            phase: phase,
            archiveDirectory: record.archiveDirectory
        )
    }

    /// Historical archive receipts never gate access to the current library.
    nonisolated static func preservedArchive(in directory: URL) throws -> String? {
        let receipt = directory.appendingPathComponent(recoveryRecordName)
        guard let data = try? Data(contentsOf: receipt),
              let record = try? JSONDecoder().decode(StoreRecoveryIssue.self, from: data) else { return nil }
        guard record.phase != .copying,
              record.archiveDirectory == nil || record.phase == .removing else { return nil }
        return archiveURL(for: record, in: directory)?.path
    }

    /// Resolve only an archive inside the current Application Support directory.
    /// For old absolute receipts, rebase the archive's basename instead of ever
    /// following a stale sandbox path (or an arbitrary path outside this folder).
    nonisolated private static func archiveURL(for record: StoreRecoveryIssue, in directory: URL) -> URL? {
        guard let name = record.archiveDirectory ?? record.archivedPath.map({ URL(fileURLWithPath: $0).lastPathComponent }),
              name.hasPrefix("Archived Store "),
              name == (name as NSString).lastPathComponent,
              !name.contains("/"), !name.contains("\\") else { return nil }
        let archive = directory.appendingPathComponent(name, isDirectory: true)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: archive.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else { return nil }
        return archive
    }

    /// Cold App Intents may open a copying-phase library (originals are intact)
    /// but must not open a store whose originals may already have been removed.
    nonisolated static func canOpenStore(in directory: URL) -> Bool {
        do {
            guard let issue = try pendingRecovery(in: directory) else { return true }
            return issue.phase == .copying
        } catch {
            return false
        }
    }

    nonisolated static func canOpenDefaultStore() -> Bool {
        canOpenStore(in: ModelConfiguration().url.deletingLastPathComponent())
    }

    @discardableResult
    nonisolated static func archiveDefaultStore(now: Date = Date()) throws -> URL {
        let store = ModelConfiguration().url
        return try relocateStoreFiles(in: store.deletingLastPathComponent(), storeName: store.lastPathComponent,
                                     mediaDirectory: SessionMediaStore.recoveryDirectoryURL(), now: now)
    }

    /// Copies every component before removing any original. If a copy, removal,
    /// or marker operation fails, the error is propagated. A complete archive
    /// survives even a partial removal or crash and is finished on the next launch.
    @discardableResult
    nonisolated static func relocateStoreFiles(
        in directory: URL,
        storeName: String = "default.store",
        mediaDirectory: URL? = nil,
        now: Date = Date(),
        copyItem: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        isProtectedDataAvailable: () -> Bool = { PeakDataStore.protectedDataAvailable() },
        availableCapacity: (URL) -> Int64? = { PeakDataStore.volumeCapacity(for: $0) }
    ) throws -> URL {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(recoveryMarkerName)
        if let issue = try pendingRecovery(in: directory) {
            if issue.phase == .removing {
                do {
                    return try finishRemoval(
                        issue: issue,
                        in: directory,
                        storeName: storeName,
                        mediaDirectory: mediaDirectory,
                        removeItem: removeItem
                    )
                } catch {
                    throw StoreRecoveryIssue(
                        archivedPath: archiveURL(for: issue, in: directory)?.path,
                        details: error.localizedDescription,
                        phase: .removing,
                        archiveDirectory: issue.archiveDirectory
                    )
                }
            }
            guard issue.phase == .copying else { throw issue }
            // The marker proves no source removal began. Discard only our own
            // incomplete archive so retries do not compound an out-of-space error.
            if let incomplete = archiveURL(for: issue, in: directory) {
                try removeItem(incomplete)
            }
        }
        guard isProtectedDataAvailable() else {
            throw StoreRecoveryIssue(archivedPath: nil, details: "Protected data is not available yet. Original files have not been changed.")
        }
        let stamp = ExportDateFormatter.fileSafeString(from: now)
        let archive = directory.appendingPathComponent("Archived Store \(stamp) \(UUID().uuidString)", isDirectory: true)
        let sources = existingLibrarySources(in: directory, storeName: storeName, mediaDirectory: mediaDirectory)
        // No source is not proof that a library was preserved.
        guard !sources.isEmpty else {
            throw StoreRecoveryIssue(archivedPath: nil, details: "No existing library files could be found to preserve.")
        }
        let needed = sources.reduce(Int64(0)) { $0 + allocatedSize(of: $1) } + 1_048_576
        if let available = availableCapacity(directory), available < needed {
            throw StoreRecoveryIssue(archivedPath: nil, details: "Not enough free storage to preserve your library. Original files have not been changed.")
        }
        var completeArchive: String?
        do {
            try fm.createDirectory(at: archive, withIntermediateDirectories: false)
            let started = StoreRecoveryIssue(archivedPath: nil, details: "Library preservation was interrupted before a complete copy was confirmed. Original files have not been removed.", phase: .copying, archiveDirectory: archive.lastPathComponent)
            try JSONEncoder().encode(started).write(to: marker, options: .atomic)
            for source in sources {
                try copyItem(source, archive.appendingPathComponent(source.lastPathComponent))
            }
            // Write the complete archive location BEFORE removing any source.
            completeArchive = archive.path
            let preserved = StoreRecoveryIssue(archivedPath: nil, details: "A complete library copy was preserved, but preparing a fresh library did not finish.", phase: .removing, archiveDirectory: archive.lastPathComponent)
            try JSONEncoder().encode(preserved).write(to: marker, options: .atomic)
            try JSONEncoder().encode(preserved).write(to: directory.appendingPathComponent(recoveryRecordName), options: .atomic)
            try removeLiveSources(sources, in: directory, removeItem: removeItem)
            try removeItem(marker)
            return archive
        } catch {
            throw StoreRecoveryIssue(archivedPath: completeArchive, details: "\(error.localizedDescription) Recovery files: \(archive.path)", phase: completeArchive == nil ? .copying : .removing, archiveDirectory: archive.lastPathComponent)
        }
    }

    /// A copying-phase marker means originals are intact. Drop the marker and
    /// any partial archive so the next launch is a normal open.
    nonisolated static func abandonIncompleteCopy(in directory: URL) throws {
        guard let issue = try pendingRecovery(in: directory), issue.phase == .copying else { return }
        if let incomplete = archiveURL(for: issue, in: directory) {
            try? FileManager.default.removeItem(at: incomplete)
        }
        let marker = directory.appendingPathComponent(recoveryMarkerName)
        if FileManager.default.fileExists(atPath: marker.path) {
            try FileManager.default.removeItem(at: marker)
        }
    }

    /// Archive only genuine corruption or an incompatible model. Permission,
    /// data-protection, low disk, SQLITE_BUSY and migration failures must not
    /// retire a library that may still be healthy.
    nonisolated static func isArchiveWorthy(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let ns = current {
            if ns.domain == PersistentStoreFailure.sqliteDomain,
               PersistentStoreFailure.sqliteCorruptionCodes.contains(ns.code) {
                return true
            }
            if ns.domain == NSCocoaErrorDomain {
                if ns.code == CocoaError.fileReadCorruptFile.rawValue { return true }
                if PersistentStoreFailure.incompatibleModelCodes.contains(ns.code) { return true }
            }
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    nonisolated static func protectedDataAvailable() -> Bool {
        if Thread.isMainThread {
            return UIApplication.shared.isProtectedDataAvailable
        }
        return DispatchQueue.main.sync { UIApplication.shared.isProtectedDataAvailable }
    }

    nonisolated static func volumeCapacity(for url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
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

    nonisolated private static func finishRemoval(
        issue: StoreRecoveryIssue,
        in directory: URL,
        storeName: String,
        mediaDirectory: URL?,
        removeItem: (URL) throws -> Void
    ) throws -> URL {
        guard let archive = archiveURL(for: issue, in: directory) else { throw issue }
        let leftovers = existingLibrarySources(in: directory, storeName: storeName, mediaDirectory: mediaDirectory)
        try removeLiveSources(leftovers, in: directory, removeItem: removeItem)
        let marker = directory.appendingPathComponent(recoveryMarkerName)
        if FileManager.default.fileExists(atPath: marker.path) {
            try removeItem(marker)
        }
        return archive
    }

    nonisolated private static func existingLibrarySources(
        in directory: URL,
        storeName: String,
        mediaDirectory: URL?
    ) -> [URL] {
        let baseName = (storeName as NSString).deletingPathExtension
        let storeSources = [storeName, "\(storeName)-wal", "\(storeName)-shm", ".\(baseName)_SUPPORT"]
            .map { directory.appendingPathComponent($0) }
        let media = mediaDirectory ?? directory.appendingPathComponent("SessionMedia", isDirectory: true)
        return (storeSources + [media]).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated private static func removeLiveSources(
        _ sources: [URL],
        in directory: URL,
        removeItem: (URL) throws -> Void
    ) throws {
        let livePath = directory.standardizedFileURL.path
        for source in sources where source.deletingLastPathComponent().standardizedFileURL.path == livePath {
            try removeItem(source)
        }
    }

    nonisolated private static func allocatedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

private enum PersistentStoreFailure {
    static let sqliteDomain = "NSSQLiteErrorDomain"
    static let sqliteCorruptionCodes: Set<Int> = [11, 24, 26]
    static let incompatibleModelCodes: Set<Int> = [134000, 134010, 134020, 134100]
}
