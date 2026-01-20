import AVFoundation
import XCTest

@testable import Peak

final class SessionMediaStoreTests: XCTestCase {
    override func tearDownWithError() throws {
        SessionMediaStore.deleteAllStoredMedia()
    }

    func testStoreVideoPersistsFileAndThumbnail() throws {
        let sourceURL = try makeTestVideoURL()
        defer {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }

        let stored = try SessionMediaStore.storeVideo(from: sourceURL, thumbnailData: nil)
        let storedURL = SessionMediaStore.videoURL(for: stored.fileName)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertNotNil(stored.thumbnailData)
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
