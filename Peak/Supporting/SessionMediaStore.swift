import AVFoundation
import Foundation
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
        let resolvedThumbnail = thumbnailData ?? videoThumbnailData(from: destination)
        return StoredSessionVideo(fileName: fileName, thumbnailData: resolvedThumbnail)
    }

    static func compressedPhotoData(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.85) ?? data
    }

    static func thumbnailData(from imageData: Data, maxDimension: CGFloat = 420) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let scaled = scaledImage(image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: 0.75)
    }

    static func videoThumbnailData(from url: URL, maxDimension: CGFloat = 420) -> Data? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        let image = UIImage(cgImage: cgImage)
        let scaled = scaledImage(image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: 0.75)
    }

    static func videoURL(for fileName: String) -> URL {
        let directory = (try? mediaDirectoryURL()) ?? FileManager.default.temporaryDirectory
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

    private static func mediaDirectoryURL() throws -> URL {
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

    private static func scaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
