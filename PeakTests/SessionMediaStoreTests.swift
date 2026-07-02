import AVFoundation
import UIKit
import XCTest

@testable import Peak

final class SessionMediaStoreTests: XCTestCase {
    override func tearDownWithError() throws {
        SessionMediaStore.deleteAllStoredMedia()
    }

    func testCroppedFullFrameReturnsSameImage() {
        let image = Self.solidImage(width: 100, height: 60)
        let result = image.cropped(toNormalized: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(result.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(result.cgImage?.height, image.cgImage?.height)
    }

    func testCroppedHalfRectReturnsHalfPixels() {
        let image = Self.solidImage(width: 100, height: 80)
        let result = image.cropped(toNormalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(result.cgImage?.width, 50)
        XCTAssertEqual(result.cgImage?.height, 40)
    }

    func testCroppedDegenerateRectReturnsSelf() {
        let image = Self.solidImage(width: 40, height: 40)
        let result = image.cropped(toNormalized: CGRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(result.cgImage?.width, image.cgImage?.width)
    }

    private static func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// `processedPhoto(from:)` is the off-main (`@concurrent`) pipeline the session
    /// editor uses for picked photos: one call yields the capped full-size JPEG plus
    /// its grid thumbnail, matching the older sync compress-then-thumbnail pair.
    func testProcessedPhotoCompressesAndGeneratesThumbnail() async throws {
        let image = Self.solidImage(width: 3000, height: 2000)
        let sourceData = try XCTUnwrap(image.jpegData(compressionQuality: 1))

        let processed = await SessionMediaStore.processedPhoto(from: sourceData)

        let photo = try XCTUnwrap(UIImage(data: processed.photoData))
        let photoMaxDimension = max(photo.size.width * photo.scale, photo.size.height * photo.scale)
        XCTAssertLessThanOrEqual(photoMaxDimension, 2048)

        let thumbnailData = try XCTUnwrap(processed.thumbnailData)
        let thumbnail = try XCTUnwrap(UIImage(data: thumbnailData))
        let thumbnailMaxDimension = max(thumbnail.size.width * thumbnail.scale, thumbnail.size.height * thumbnail.scale)
        XCTAssertLessThanOrEqual(thumbnailMaxDimension, 420)

        // Matches what the sync single-purpose helpers would have produced.
        XCTAssertEqual(processed.photoData, SessionMediaStore.compressedPhotoData(from: sourceData))
    }

    func testProcessedPhotoPassesThroughUndecodableData() async {
        let junk = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let processed = await SessionMediaStore.processedPhoto(from: junk)

        XCTAssertEqual(processed.photoData, junk)
        XCTAssertNil(processed.thumbnailData)
    }

    func testStoreVideoPersistsFileAndThumbnail() throws {
        let sourceURL = try makeTestVideoURL()
        defer {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }

        let expectedThumbnail = Data([0x01, 0x02, 0x03])
        let stored = try SessionMediaStore.storeVideo(from: sourceURL, thumbnailData: expectedThumbnail)
        let storedURL = SessionMediaStore.videoURL(for: stored.fileName)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(stored.thumbnailData, expectedThumbnail)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    private func makeTestVideoURL() throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 2,
            AVVideoHeightKey: 2
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 2,
                kCVPixelBufferHeightKey as String: 2
            ]
        )

        guard writer.canAdd(input) else {
            throw TestError.cannotAddInput
        }
        writer.add(input)

        let buffer = try makePixelBuffer(width: 2, height: 2)

        let finished = expectation(description: "finish writing video")
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        while !input.isReadyForMoreMediaData {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard adaptor.append(buffer, withPresentationTime: .zero) else {
            throw TestError.couldNotAppendFrame
        }

        input.markAsFinished()
        writer.finishWriting {
            finished.fulfill()
        }

        wait(for: [finished], timeout: 5)
        if writer.status == .failed {
            throw writer.error ?? TestError.writerFailed
        }

        return outputURL
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw TestError.couldNotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            memset(baseAddress, 0xFF, bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }
}

private enum TestError: Error {
    case cannotAddInput
    case couldNotAppendFrame
    case couldNotCreatePixelBuffer
    case writerFailed
}
