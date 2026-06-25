import CoreGraphics
import UIKit

extension UIImage {
    /// Returns a copy cropped to the given **normalized** rect (0...1, origin top-left in the
    /// image's display orientation). Used to apply a preview crop to photos and to video poster
    /// frames without re-encoding the stored asset.
    ///
    /// - Full-frame (or degenerate) rects return `self` unchanged — legacy/uncropped media pays
    ///   zero cost and renders byte-identically to before.
    /// - EXIF orientation is baked to `.up` first, because `CGImage.cropping(to:)` works in raw
    ///   pixel space and ignores `imageOrientation`; without this a camera/PhotosPicker JPEG would
    ///   crop the wrong region.
    nonisolated func cropped(toNormalized rect: CGRect) -> UIImage {
        // Fast path: nothing to do for the default full frame or a degenerate rect.
        if rect.width <= 0 || rect.height <= 0 { return self }
        if rect.origin.x <= 0, rect.origin.y <= 0, rect.width >= 1, rect.height >= 1 { return self }

        let baked = orientationBaked()
        guard let cg = baked.cgImage else { return self }

        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        guard pixelWidth > 0, pixelHeight > 0 else { return self }

        let pixelRect = CGRect(
            x: rect.origin.x * pixelWidth,
            y: rect.origin.y * pixelHeight,
            width: rect.width * pixelWidth,
            height: rect.height * pixelHeight
        ).integral

        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let clamped = pixelRect.intersection(bounds)
        // Rounding can never legitimately produce an empty/null rect for a valid crop; bail to the
        // full image rather than returning nil.
        guard !clamped.isNull, !clamped.isEmpty, let cropped = cg.cropping(to: clamped) else {
            return self
        }

        return UIImage(cgImage: cropped, scale: baked.scale, orientation: .up)
    }

    /// Redraws the image with its orientation applied so the backing `CGImage` is upright (`.up`).
    /// No-op when already upright.
    nonisolated private func orientationBaked() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
