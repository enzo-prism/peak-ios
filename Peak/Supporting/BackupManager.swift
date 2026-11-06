import Foundation
import SwiftData

/// Full-data backup + restore for Peak.
///
/// New backups use checked binary frames with streamed videos. Legacy JSON /
/// base64 backups remain readable; neither format is encrypted by Peak.
enum BackupManager {
    nonisolated static let backupVersion = "1"
    nonisolated static let fileExtension = "peakbackup"
    nonisolated static let filePrefix = "Peak-Backup"

    // MARK: - Off-main snapshot

    /// A Sendable snapshot of one media row, gathered on the MainActor so the
    /// base64 encoding can run off the main actor without touching the model.
    nonisolated struct RawMediaSnapshot: Sendable {
        let sessionId: String
        let kind: String
        let sortIndex: Int
        let cropOriginX: Double
        let cropOriginY: Double
        let cropWidth: Double
        let cropHeight: Double
        let createdAt: Date
        let photoData: Data?
        let thumbnailData: Data?
        /// On-disk location of the video binary (nil for photos / missing files).
        let videoURL: URL?
    }

    // MARK: - Backup

    /// Builds a `.peakbackup` file capturing every session/spot/gear/buddy plus
    /// all media, writes it to the temporary directory, and verifies the bytes.
    /// Models are read on the main actor; file I/O and hashing run off-main.
    static func makeBackupFile(
        sessions: [SurfSession],
        spots: [Spot],
        gear: [Gear],
        buddies: [Buddy],
        now: Date = Date(),
        progress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> URL {
        let signpost = PeakSignposts.begin("Backup file")
        defer { PeakSignposts.end(signpost) }
        let export = PeakExportManager.makeExport(
            sessions: sessions,
            spots: spots,
            gear: gear,
            buddies: buddies,
            now: now
        )

        let url = backupURL(now: now)
        let total = sessions.reduce(0) { $0 + $1.media.count }
        var completed = 0
        let writer = try FramedBackupWriter(url: url, export: export, mediaCount: total)
        progress?(0, total)
        do {
            // Only one media value crosses to the writer at a time. Videos are
            // streamed from disk instead of retained/base64-expanded in memory.
            for session in sessions {
                let sessionId = SessionIntentQueries.identifier(for: session)
                for media in session.media.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                    let snapshot = RawMediaSnapshot(
                        sessionId: sessionId, kind: media.kind.rawValue, sortIndex: media.sortIndex,
                        cropOriginX: media.cropOriginX, cropOriginY: media.cropOriginY,
                        cropWidth: media.cropWidth, cropHeight: media.cropHeight, createdAt: media.createdAt,
                        photoData: media.photoData, thumbnailData: media.thumbnailData,
                        videoURL: media.videoFileName.map { SessionMediaStore.videoURL(for: $0) })
                    try await writer.append(snapshot)
                    completed += 1
                    progress?(completed, total)
                }
            }
            try await writer.finish()
            // Verify the actual bytes before offering an export, not just the
            // values we intended to write. Inspection never mutates SwiftData.
            _ = try await FramedBackupReader.read(url: url, stageMedia: false)
            try Task.checkCancellation()
            return url
        } catch {
            await writer.cancel()
            throw error
        }
    }

    /// Off-main assembly: reads video bytes, base64-encodes each entry inside an
    /// `autoreleasepool`, then serializes the whole backup document to JSON.
    @concurrent
    nonisolated static func encodeBackup(
        export: PeakExport,
        snapshots: [RawMediaSnapshot],
        exportedAt: String
    ) async throws -> Data {
        var entries: [SessionMediaBackupEntry] = []
        entries.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            let entry: SessionMediaBackupEntry = autoreleasepool {
                let videoData = snapshot.videoURL.flatMap { try? Data(contentsOf: $0) }
                return SessionMediaBackupEntry(
                    id: UUID().uuidString,
                    sessionId: snapshot.sessionId,
                    kind: snapshot.kind,
                    sortIndex: snapshot.sortIndex,
                    cropOriginX: snapshot.cropOriginX,
                    cropOriginY: snapshot.cropOriginY,
                    cropWidth: snapshot.cropWidth,
                    cropHeight: snapshot.cropHeight,
                    createdAt: ExportDateFormatter.string(from: snapshot.createdAt),
                    photoBase64: snapshot.photoData?.base64EncodedString(),
                    thumbnailBase64: snapshot.thumbnailData?.base64EncodedString(),
                    videoBase64: videoData?.base64EncodedString()
                )
            }
            entries.append(entry)
        }

        let manifest = PeakBackupManifest(
            backupVersion: backupVersion,
            exportedAt: exportedAt,
            media: entries
        )
        let file = PeakBackupFile(export: export, manifest: manifest)
        return try encodeBackupFile(file)
    }

    // MARK: - Restore

    /// A manifest entry with its base64 payloads decoded and its video already
    /// written into the media store, ready for main-actor model insertion.
    nonisolated struct PreparedMediaEntry: Sendable {
        let sessionId: String
        let kind: SessionMediaKind
        let sortIndex: Int
        let cropOriginX: Double
        let cropOriginY: Double
        let cropWidth: Double
        let cropHeight: Double
        let createdAt: Date
        let photoData: Data?
        let thumbnailData: Data?
        let videoFileName: String?
    }

    /// Restores a `.peakbackup` file into `context`.
    ///
    /// Sessions/spots/gear/buddies go through `PeakExportManager.applyImport`
    /// (which owns the merge/dedupe + `.replace` wipe semantics). Media is then
    /// reattached: each manifest entry is matched to its imported session by
    /// export identity and appended to that session's `media` relationship.
    /// Entries whose session isn't found are skipped.
    ///
    /// Decode/write new media before mutation. Commit all model changes before
    /// deleting old videos or returning success. Failure removes only staged
    /// new files and discards the private import context, preserving caller edits.
    static func restore(
        from url: URL,
        mode: ImportMode,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async throws {
        let (file, preparedMedia) = try await prepareRestore(from: url)

        do {
            _ = try PeakExportManager.validateImport(file.export, mode: mode, context: context)
            try PeakExportManager.withImportTransaction(context: context, save: save) { transaction in
                try applyRestore(file: file, preparedMedia: preparedMedia, mode: mode, context: transaction)
            }
        } catch {
            for name in preparedMedia.compactMap(\.videoFileName) {
                SessionMediaStore.deleteVideoFile(named: name)
            }
            throw error
        }
    }

    /// Off-main phase: whole-file read, JSON decode, per-entry base64 decode,
    /// and video writes. A 600 MB backup must not freeze the UI (or invite the
    /// watchdog) for the tens of seconds this takes — same reason
    /// `encodeBackup` is `@concurrent` on the way out.
    @concurrent
    nonisolated static func prepareRestore(from url: URL) async throws -> (PeakBackupFile, [PreparedMediaEntry]) {
        if try FramedBackupReader.isFramed(url) {
            let read = try await FramedBackupReader.read(url: url, stageMedia: true)
            return (read.file, read.prepared)
        }
        let data = try Data(contentsOf: url)
        let file = try decodeBackupFile(data)
        try validateLegacyMedia(file)

        var prepared: [PreparedMediaEntry] = []
        prepared.reserveCapacity(file.manifest.media.count)
        var writtenVideoFileNames: [String] = []

        do {
            for entry in file.manifest.media {
                let item: PreparedMediaEntry? = try autoreleasepool {
                    guard let kind = SessionMediaKind(rawValue: entry.kind),
                          let createdAt = mediaDate(from: entry.createdAt) else { throw BackupIntegrityError.invalid }
                    var videoFileName: String?
                    if kind == .video {
                        // A corrupt or absent video fails the entire restore
                        // before the library transaction begins.
                        guard let base64 = entry.videoBase64,
                              let videoData = Data(base64Encoded: base64) else { throw BackupIntegrityError.missingMedia }
                        let name = try writeRestoredVideo(videoData)
                        videoFileName = name
                        writtenVideoFileNames.append(name)
                    }
                    return PreparedMediaEntry(
                        sessionId: entry.sessionId,
                        kind: kind,
                        sortIndex: entry.sortIndex,
                        cropOriginX: entry.cropOriginX,
                        cropOriginY: entry.cropOriginY,
                        cropWidth: entry.cropWidth,
                        cropHeight: entry.cropHeight,
                        createdAt: createdAt,
                        photoData: entry.photoBase64.flatMap { Data(base64Encoded: $0) },
                        thumbnailData: entry.thumbnailBase64.flatMap { Data(base64Encoded: $0) },
                        videoFileName: videoFileName
                    )
                }
                if let item { prepared.append(item) }
            }
        } catch {
            for name in writtenVideoFileNames {
                SessionMediaStore.deleteVideoFile(named: name)
            }
            throw error
        }

        return (file, prepared)
    }

    /// Main-actor mutation phase, inside the import transaction.
    private static func applyRestore(
        file: PeakBackupFile,
        preparedMedia: [PreparedMediaEntry],
        mode: ImportMode,
        context: ModelContext
    ) throws {

        // Snapshot which sessions already exist (by their portable identity)
        // BEFORE the import. On a merge restore into a library that still holds
        // these sessions, media is reattached additively below — so without this we
        // would append every photo/video a second time (and orphan video files) on
        // each restore. `.replace` already wiped everything, so the set stays empty.
        let preexistingSessionKeys: Set<String>
        if mode == .merge {
            let existing = try context.fetch(FetchDescriptor<SurfSession>())
            preexistingSessionKeys = Set(existing.map { SessionIntentQueries.identifier(for: $0) })
        } else {
            preexistingSessionKeys = []
        }

        let sessionByKey = try PeakExportManager.stageImport(file.export, mode: mode, context: context)

        // Sessions that existed before this merge get their media replaced (not
        // duplicated): clear rows once before reattaching the backup copy.
        // The enclosing transaction defers original video deletion until commit.
        var clearedSessionKeys: Set<String> = []

        for entry in preparedMedia {
            guard let session = sessionByKey[entry.sessionId] else {
                // The video was pre-written but its session never landed —
                // remove the file rather than orphan it on disk.
                if let name = entry.videoFileName {
                    SessionMediaStore.deleteVideoFile(named: name)
                }
                continue
            }

            if preexistingSessionKeys.contains(SessionIntentQueries.identifier(for: session)),
               !clearedSessionKeys.contains(entry.sessionId) {
                for existingMedia in session.media {
                    context.delete(existingMedia)
                }
                session.media.removeAll()
                clearedSessionKeys.insert(entry.sessionId)
            }

            let media = SessionMedia(
                kind: entry.kind,
                photoData: entry.photoData,
                thumbnailData: entry.thumbnailData,
                videoFileName: entry.videoFileName,
                sortIndex: entry.sortIndex,
                cropOriginX: entry.cropOriginX,
                cropOriginY: entry.cropOriginY,
                cropWidth: entry.cropWidth,
                cropHeight: entry.cropHeight,
                createdAt: entry.createdAt
            )
            context.insert(media)
            session.media.append(media)
        }
    }

    /// Writes decoded video bytes into the app's SessionMedia store and returns
    /// the stored file name. Reuses `SessionMediaStore.storeVideo` (which moves
    /// the file into Application Support/SessionMedia and honors test redirection).
    nonisolated private static func writeRestoredVideo(_ data: Data) throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")
        try data.write(to: tempURL, options: [.atomic])
        let stored = try SessionMediaStore.storeVideo(from: tempURL, thumbnailData: nil)
        return stored.fileName
    }

    nonisolated struct Inspection: Sendable {
        let sessions: Int
        let spots: Int
        let gear: Int
        let buddies: Int
        let photos: Int
        let videos: Int
        let checksummed: Bool
        var summary: String {
            "Contains \(sessions) sessions, \(spots) spots, \(gear) gear items, \(buddies) buddies, \(photos) photos and \(videos) videos. "
                + (checksummed ? "All file checksums verified. " : "Legacy format: media payloads checked; no file checksums. ")
                + "Merge preserves other sessions and replaces media for matching sessions. Replace removes your current library after the import is ready."
        }
    }

    @concurrent nonisolated static func inspect(_ url: URL) async throws -> Inspection {
        let framed = try FramedBackupReader.isFramed(url)
        let file: PeakBackupFile
        if framed { file = try await FramedBackupReader.read(url: url, stageMedia: false).file }
        else {
            file = try decodeBackupFile(Data(contentsOf: url))
            try validateLegacyMedia(file)
        }
        return Inspection(sessions: file.export.sessions.count, spots: file.export.spots.count,
            gear: file.export.gear.count, buddies: file.export.buddies.count, photos: file.manifest.media.filter { $0.kind == "photo" }.count,
            videos: file.manifest.media.filter { $0.kind == "video" }.count, checksummed: framed)
    }

    nonisolated private static func validateLegacyMedia(_ file: PeakBackupFile) throws {
        guard file.manifest.backupVersion == "1" else { throw BackupIntegrityError.invalid }
        let sessionIDs = Set(file.export.sessions.map(\.id))
        var entryIDs = Set<String>()
        for entry in file.manifest.media {
            guard let kind = SessionMediaKind(rawValue: entry.kind),
                  entryIDs.insert(entry.id).inserted, sessionIDs.contains(entry.sessionId),
                  entry.sortIndex >= 0, mediaDate(from: entry.createdAt) != nil else { throw BackupIntegrityError.invalid }
            let payload = kind == .photo ? entry.photoBase64 : entry.videoBase64
            guard let payload, let data = Data(base64Encoded: payload), !data.isEmpty else { throw BackupIntegrityError.missingMedia }
            if let thumb = entry.thumbnailBase64, Data(base64Encoded: thumb) == nil { throw BackupIntegrityError.invalid }
        }
    }

    nonisolated static func mediaDate(from string: String) -> Date? {
        // Keep fractional timestamps; older archives may contain whole seconds.
        ExportDateFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Pure encode/decode (testable)

    nonisolated static func encodeBackupFile(_ file: PeakBackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    nonisolated static func decodeBackupFile(_ data: Data) throws -> PeakBackupFile {
        try JSONDecoder().decode(PeakBackupFile.self, from: data)
    }

    // MARK: - File location

    nonisolated static func backupURL(now: Date = Date()) -> URL {
        let stamp = ExportDateFormatter.fileSafeString(from: now)
        let filename = "\(filePrefix)-\(stamp)-\(UUID().uuidString).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
