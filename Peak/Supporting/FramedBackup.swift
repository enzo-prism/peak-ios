import CryptoKit
import Foundation

nonisolated enum BackupIntegrityError: LocalizedError {
    case incomplete, invalid, checksum, missingMedia
    var errorDescription: String? {
        switch self {
        case .incomplete: return "This backup is incomplete. Your current library was not changed."
        case .invalid: return "The backup contains invalid data or an unsupported format."
        case .checksum: return "A backup integrity check failed. Your current library was not changed."
        case .missingMedia: return "A photo or video could not be read. A complete backup was not created."
        }
    }
}

nonisolated struct FramedBackupHeader: Codable, Sendable {
    let export: PeakExport
    let mediaCount: Int
}

/// Version two is a sequence of length-delimited, SHA-256 checked frames.
/// Filenames are never trusted input. Each blob is streamed in 64 KiB chunks;
/// existing JSON/base64 backups remain readable through BackupManager.
actor FramedBackupWriter {
    nonisolated static let magic = Data("PEAKBACKUP2\n".utf8)
    private let url: URL
    private let handle: FileHandle
    private let expectedCount: Int
    private var count = 0
    private var closed = false

    init(url: URL, export: PeakExport, mediaCount: Int) throws {
        self.url = url
        expectedCount = mediaCount
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: Self.magic)
            try Self.writeFrame(try JSONEncoder().encode(FramedBackupHeader(export: export, mediaCount: mediaCount)), to: handle)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func append(_ snapshot: BackupManager.RawMediaSnapshot) throws {
        guard !closed, count < expectedCount else { throw BackupIntegrityError.invalid }
        try Task.checkCancellation()
        guard (snapshot.kind == "photo" && snapshot.photoData != nil)
                || (snapshot.kind == "video" && snapshot.videoURL != nil) else { throw BackupIntegrityError.missingMedia }
        let entry = SessionMediaBackupEntry(id: UUID().uuidString, sessionId: snapshot.sessionId,
            kind: snapshot.kind, sortIndex: snapshot.sortIndex,
            cropOriginX: snapshot.cropOriginX, cropOriginY: snapshot.cropOriginY,
            cropWidth: snapshot.cropWidth, cropHeight: snapshot.cropHeight,
            createdAt: ExportDateFormatter.string(from: snapshot.createdAt),
            photoBase64: nil, thumbnailBase64: nil, videoBase64: nil)
        try Self.writeFrame(try JSONEncoder().encode(entry), to: handle)
        try Self.writeFrame(snapshot.photoData ?? Data(), to: handle)
        try Self.writeFrame(snapshot.thumbnailData ?? Data(), to: handle)
        if let video = snapshot.videoURL {
            let input: FileHandle
            do { input = try FileHandle(forReadingFrom: video) }
            catch { throw BackupIntegrityError.missingMedia }
            defer { try? input.close() }
            let size = try input.seekToEnd()
            guard size > 0 else { throw BackupIntegrityError.missingMedia }
            try input.seek(toOffset: 0)
            try Self.writeLength(size, to: handle)
            var hash = SHA256()
            var remaining = size
            while remaining > 0 {
                try Task.checkCancellation()
                let data = try input.read(upToCount: Int(min(65_536, remaining))) ?? Data()
                guard !data.isEmpty else { throw BackupIntegrityError.missingMedia }
                hash.update(data: data)
                try handle.write(contentsOf: data)
                remaining -= UInt64(data.count)
            }
            // A video changing during export cannot yield a verified snapshot.
            guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw BackupIntegrityError.missingMedia }
            try handle.write(contentsOf: Data(hash.finalize()))
        } else { try Self.writeFrame(Data(), to: handle) }
        count += 1
    }

    func finish() throws {
        guard !closed, count == expectedCount else { throw BackupIntegrityError.incomplete }
        try handle.write(contentsOf: Data("ENDPEAK2".utf8))
        try handle.synchronize()
        try handle.close()
        closed = true
    }

    func cancel() {
        if !closed { try? handle.close(); closed = true }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func writeLength(_ length: UInt64, to handle: FileHandle) throws {
        var value = length.littleEndian
        try withUnsafeBytes(of: &value) { try handle.write(contentsOf: Data($0)) }
    }
    nonisolated private static func writeFrame(_ data: Data, to handle: FileHandle) throws {
        try writeLength(UInt64(data.count), to: handle)
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data(SHA256.hash(data: data)))
    }
}

nonisolated enum FramedBackupReader {
    struct Result: Sendable {
        let file: PeakBackupFile
        let prepared: [BackupManager.PreparedMediaEntry]
    }

    static func isFramed(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: FramedBackupWriter.magic.count) == FramedBackupWriter.magic
    }

    @concurrent static func read(url: URL, stageMedia: Bool) async throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try readExactly(FramedBackupWriter.magic.count, from: handle) == FramedBackupWriter.magic else { throw BackupIntegrityError.invalid }
        let headerData = try readFrame(from: handle, maxLength: 256 * 1024 * 1024)
        let header = try JSONDecoder().decode(FramedBackupHeader.self, from: headerData)
        guard (0...1_000_000).contains(header.mediaCount) else { throw BackupIntegrityError.invalid }
        let sessionIDs = Set(header.export.sessions.map(\.id))
        var entries: [SessionMediaBackupEntry] = []
        var prepared: [BackupManager.PreparedMediaEntry] = []
        var videos: [String] = []
        var entryIDs = Set<String>()
        do {
            for _ in 0..<header.mediaCount {
                try Task.checkCancellation()
                let metadata = try readFrame(from: handle, maxLength: 1_048_576)
                let entry = try JSONDecoder().decode(SessionMediaBackupEntry.self, from: metadata)
                guard entryIDs.insert(entry.id).inserted, sessionIDs.contains(entry.sessionId),
                      let kind = SessionMediaKind(rawValue: entry.kind), entry.sortIndex >= 0,
                      let createdAt = BackupManager.mediaDate(from: entry.createdAt) else { throw BackupIntegrityError.invalid }
                let photo = try readFrame(from: handle, maxLength: 128 * 1024 * 1024)
                let thumbnail = try readFrame(from: handle, maxLength: 32 * 1024 * 1024)
                var videoName: String?
                let videoSize = try readLength(from: handle)
                // Verify remaining file bounds before allocating or writing.
                let offset = try handle.offset()
                let fileSize = try handle.seekToEnd()
                try handle.seek(toOffset: offset)
                guard videoSize <= fileSize - min(offset, fileSize), videoSize <= 1_099_511_627_776 else { throw BackupIntegrityError.incomplete }
                var output: FileHandle?
                if videoSize > 0 && stageMedia {
                    let name = UUID().uuidString + ".mov"
                    let destination = SessionMediaStore.videoURL(for: name)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                    videos.append(name)
                    videoName = name
                    output = try FileHandle(forWritingTo: destination)
                }
                do {
                    var hash = SHA256()
                    var remaining = videoSize
                    while remaining > 0 {
                        try Task.checkCancellation()
                        let chunk = try readExactly(Int(min(65_536, remaining)), from: handle)
                        hash.update(data: chunk)
                        try output?.write(contentsOf: chunk)
                        remaining -= UInt64(chunk.count)
                    }
                    let checksum = try readExactly(32, from: handle)
                    guard checksum == Data(hash.finalize()) else { throw BackupIntegrityError.checksum }
                    try output?.close()
                } catch { try? output?.close(); throw error }
                guard kind == .photo ? (!photo.isEmpty && videoSize == 0) : (photo.isEmpty && videoSize > 0) else { throw BackupIntegrityError.missingMedia }
                entries.append(entry)
                if stageMedia {
                    prepared.append(BackupManager.PreparedMediaEntry(sessionId: entry.sessionId, kind: kind,
                        sortIndex: entry.sortIndex, cropOriginX: entry.cropOriginX, cropOriginY: entry.cropOriginY,
                        cropWidth: entry.cropWidth, cropHeight: entry.cropHeight,
                        createdAt: createdAt,
                        photoData: photo.isEmpty ? nil : photo, thumbnailData: thumbnail.isEmpty ? nil : thumbnail,
                        videoFileName: videoName))
                }
            }
            guard try readExactly(8, from: handle) == Data("ENDPEAK2".utf8),
                  (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw BackupIntegrityError.invalid }
        } catch {
            videos.forEach { SessionMediaStore.deleteVideoFile(named: $0) }
            throw error
        }
        return Result(file: PeakBackupFile(export: header.export, manifest: PeakBackupManifest(
            backupVersion: "2", exportedAt: header.export.exportedAt, media: entries)), prepared: prepared)
    }

    private static func readLength(from handle: FileHandle) throws -> UInt64 {
        let data = try readExactly(8, from: handle)
        return data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
    }
    private static func readFrame(from handle: FileHandle, maxLength: UInt64) throws -> Data {
        let length = try readLength(from: handle)
        guard length <= maxLength else { throw BackupIntegrityError.invalid }
        let data = try readExactly(Int(length), from: handle)
        let checksum = try readExactly(32, from: handle)
        guard checksum == Data(SHA256.hash(data: data)) else { throw BackupIntegrityError.checksum }
        return data
    }
    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var data = Data()
        while data.count < count {
            let part = try handle.read(upToCount: min(65_536, count - data.count)) ?? Data()
            guard !part.isEmpty else { throw BackupIntegrityError.incomplete }
            data.append(part)
        }
        return data
    }
}
