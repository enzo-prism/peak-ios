import AVFoundation
import Foundation
import ImageIO
import UIKit

struct StoredSessionVideo {
    let fileName: String
    let thumbnailData: Data?
}

enum SessionMediaStore {
    private static let mediaFolderName = "SessionMedia"

    static func storeVideo(from sourceURL: URL, thumbnailData: Data?) throws -> StoredSessionVideo {
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
        // The thumbnail is generated once at pick time and passed in.
        return StoredSessionVideo(fileName: fileName, thumbnailData: thumbnailData)
    }

    static func compressedPhotoData(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.85) ?? data
    }

    /// Generates a downsampled thumbnail via ImageIO without fully decoding the source image,
    /// keeping peak memory low for large photos.
    static func thumbnailData(from imageData: Data?, maxDimension: CGFloat = 420) -> Data? {
        guard let imageData,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75)
    }

    static func videoThumbnailData(from url: URL, maxDimension: CGFloat = 420) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Ask the generator for a small image directly rather than scaling a full-resolution frame.
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image).jpegData(compressionQuality: 0.75)
    }

    static func videoURL(for fileName: String) -> URL {
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

    private static func deleteVideoFile(named fileName: String) {
        let url = videoURL(for: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private static func resolvedMediaDirectoryURL() -> URL {
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

    private static func mediaDirectoryURL() throws -> URL {
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
}
