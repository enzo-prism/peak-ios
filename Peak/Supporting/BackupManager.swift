import Foundation
import SwiftData

/// Full-data backup + restore for Peak.
///
/// A `.peakbackup` file is a single self-contained JSON document:
/// `{ "export": <PeakExport>, "manifest": { backup_version, exported_at, media:[…] } }`.
/// Every piece of session media (photos, thumbnails, videos) is inlined as
/// base64 so one file round-trips the entire library — no sidecars, no zip or
/// AppleArchive framework. Media base64 is encoded per-entry inside an
/// `autoreleasepool` so transient memory (raw bytes + encoder temporaries)
/// stays bounded even for large videos.
enum BackupManager {
    static let backupVersion = "1"
    static let fileExtension = "peakbackup"
    static let filePrefix = "Peak-Backup"

    // MARK: - Off-main snapshot

    /// A Sendable snapshot of one media row, gathered on the MainActor so the
    /// base64 encoding can run off the main actor without touching the model.
    struct RawMediaSnapshot: Sendable {
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
    /// all inlined media, writes it to the temporary directory, and returns the URL.
    ///
    /// The export + media snapshot are read on the MainActor (model access);
    /// base64 encoding and JSON serialization are hopped off-main.
    static func makeBackupFile(
        sessions: [SurfSession],
        spots: [Spot],
        gear: [Gear],
        buddies: [Buddy],
        now: Date = Date()
    ) async throws -> URL {
        let export = PeakExportManager.makeExport(
            sessions: sessions,
            spots: spots,
            gear: gear,
            buddies: buddies,
            now: now
        )

        var snapshots: [RawMediaSnapshot] = []
        for session in sessions {
            let sessionId = SessionIntentQueries.identifier(for: session)
            let ordered = session.media.sorted { $0.sortIndex < $1.sortIndex }
            for media in ordered {
                let videoURL = media.videoFileName.map { SessionMediaStore.videoURL(for: $0) }
                snapshots.append(
                    RawMediaSnapshot(
                        sessionId: sessionId,
                        kind: media.kind.rawValue,
                        sortIndex: media.sortIndex,
                        cropOriginX: media.cropOriginX,
                        cropOriginY: media.cropOriginY,
                        cropWidth: media.cropWidth,
                        cropHeight: media.cropHeight,
                        createdAt: media.createdAt,
                        photoData: media.photoData,
                        thumbnailData: media.thumbnailData,
                        videoURL: videoURL
                    )
                )
            }
        }

        let exportedAt = ExportDateFormatter.string(from: now)
        let data = try await encodeBackup(export: export, snapshots: snapshots, exportedAt: exportedAt)

        let url = backupURL(now: now)
        try data.write(to: url, options: [.atomic])
        return url
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
    struct PreparedMediaEntry: Sendable {
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
    /// Ordering is deliberate: every byte the backup carries is decoded and
    /// every restored video is written to disk **before** any existing row or
    /// media file is touched, so a failure (disk full, corrupt payload) can
    /// only ever leave stray fresh files behind — which the `catch` removes —
    /// never a library whose media was deleted ahead of a write that then
    /// failed. The model mutation phase itself cannot throw, and on any earlier
    /// throw `context.rollback()` discards the partial import.
    static func restore(
        from url: URL,
        mode: ImportMode,
        context: ModelContext
    ) async throws {
        let (file, preparedMedia) = try await prepareRestore(from: url)

        do {
            try applyRestore(file: file, preparedMedia: preparedMedia, mode: mode, context: context)
        } catch {
            context.rollback()
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
        let data = try Data(contentsOf: url)
        let file = try decodeBackupFile(data)

        var prepared: [PreparedMediaEntry] = []
        prepared.reserveCapacity(file.manifest.media.count)
        var writtenVideoFileNames: [String] = []

        do {
            for entry in file.manifest.media {
                let item: PreparedMediaEntry? = try autoreleasepool {
                    let kind = SessionMediaKind(rawValue: entry.kind) ?? .photo
                    var videoFileName: String?
                    if kind == .video {
                        // A corrupt or absent video payload is dropped outright:
                        // inserting a `SessionMedia(videoFileName: nil)` row
                        // would be a permanently broken tile that even
                        // `deleteStoredMedia` skips.
                        guard let base64 = entry.videoBase64,
                              let videoData = Data(base64Encoded: base64) else { return nil }
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
                        createdAt: ExportDateFormatter.date(from: entry.createdAt) ?? Date(),
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

    /// Main-actor phase: the model mutations. After `applyImport` returns, this
    /// cannot throw — see `restore` for why that matters.
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
            let existing = (try? context.fetch(FetchDescriptor<SurfSession>())) ?? []
            preexistingSessionKeys = Set(existing.map { SessionIntentQueries.identifier(for: $0) })
        } else {
            preexistingSessionKeys = []
        }

        let sessionByKey = try PeakExportManager.applyImport(file.export, mode: mode, context: context)

        // Sessions that existed before this merge get their media replaced (not
        // duplicated): clear once, deleting stored video files first, before the
        // manifest reattaches the backup's copy.
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
                SessionMediaStore.deleteStoredMedia(for: session.media)
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
        let filename = "\(filePrefix)-\(stamp).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
