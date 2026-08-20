import AVFoundation
import Foundation
import ImageIO
import UIKit

nonisolated struct StoredSessionVideo {
    let fileName: String
    let thumbnailData: Data?
}

/// Result of compressing a picked photo and generating its grid thumbnail.
/// Produced off the main actor by `SessionMediaStore.processedPhoto(from:)`.
struct ProcessedSessionPhoto: Sendable {
    let photoData: Data
    let thumbnailData: Data?
}

enum SessionMediaStore {
    private static let mediaFolderName = "SessionMedia"

    /// `nonisolated` so a backup restore can write video files off the main
    /// actor: pure FileManager work against stateless paths.
    nonisolated static func storeVideo(from sourceURL: URL, thumbnailData: Data?) throws -> StoredSessionVideo {
        let directory = try mediaDirectoryURL()
        let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(pathExtension)"
        let destination = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        return StoredSessionVideo(fileName: fileName, thumbnailData: thumbnailData)
    }

    /// Re-encodes the picked photo capped at `maxDimension`, using ImageIO
    /// downsampling so the full-resolution bitmap is never decoded into memory.
    /// `nonisolated` so callers can run it off the main actor (the project
    /// builds with MainActor default isolation).
    nonisolated static func compressedPhotoData(from data: Data, maxDimension: CGFloat = 2048) -> Data {
        guard let image = downsampledImage(from: data, maxDimension: maxDimension) else { return data }
        return image.jpegData(compressionQuality: 0.85) ?? data
    }

    nonisolated static func thumbnailData(from imageData: Data, maxDimension: CGFloat = 420) -> Data? {
        guard let image = downsampledImage(from: imageData, maxDimension: maxDimension) else { return nil }
        return image.jpegData(compressionQuality: 0.75)
    }

    /// Compresses a picked photo and generates its thumbnail **off the main actor**.
    ///
    /// `@concurrent` is required to actually leave the caller's executor: this
    /// target builds with Approachable Concurrency (NonisolatedNonsendingByDefault),
    /// so a plain `nonisolated async` function would keep running on the MainActor
    /// caller and freeze the editor during multi-photo picks (~100-400ms each).
    @concurrent
    nonisolated static func processedPhoto(
        from data: Data,
        maxDimension: CGFloat = 2048,
        thumbnailMaxDimension: CGFloat = 420
    ) async -> ProcessedSessionPhoto {
        let photoData = compressedPhotoData(from: data, maxDimension: maxDimension)
        let thumbnail = thumbnailData(from: photoData, maxDimension: thumbnailMaxDimension)
        return ProcessedSessionPhoto(photoData: photoData, thumbnailData: thumbnail)
    }

    /// `@concurrent` so poster-frame decode + JPEG encode stay off the caller's
    /// actor (see `processedPhoto(from:)` — nonisolated async alone is not enough
    /// under NonisolatedNonsendingByDefault).
    @concurrent
    nonisolated static func videoThumbnailData(from url: URL, maxDimension: CGFloat = 420) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75)
    }

    nonisolated static func videoURL(for fileName: String) -> URL {
        let directory = resolvedMediaDirectoryURL()
        return directory.appendingPathComponent(fileName)
    }

    static func deleteStoredMedia(for media: SessionMedia) {
        guard media.kind == .video, let fileName = media.videoFileName else { return }
        deleteVideoFile(named: fileName)
    }

    static func deleteStoredMedia(for mediaItems: [SessionMedia]) {
        for item in mediaItems {
            deleteStoredMedia(for: item)
        }
    }

    static func deleteTemporaryFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func deleteAllStoredMedia() {
        guard let directory = try? mediaDirectoryURL() else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Non-private so a failed backup restore can roll back the video files it
    /// pre-wrote before any model rows referenced them.
    nonisolated static func deleteVideoFile(named fileName: String) {
        let url = videoURL(for: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func resolvedMediaDirectoryURL() -> URL {
        if TestingDefaults.isRunningTests {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(mediaFolderName, isDirectory: true)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        }

        if let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let directory = base.appendingPathComponent(mediaFolderName, isDirectory: true)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        }

        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent(mediaFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: fallback.path) {
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        }
        return fallback
    }

    nonisolated private static func mediaDirectoryURL() throws -> URL {
        if TestingDefaults.isRunningTests {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(mediaFolderName, isDirectory: true)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        }
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(mediaFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// ImageIO thumbnail at `maxDimension` so the full-resolution bitmap is
    /// never decoded into memory (WWDC: `kCGImageSourceThumbnailMaxPixelSize`).
    nonisolated static func downsampledImage(from data: Data, maxDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
