import SwiftUI
import UIKit

/// Photos-style square (1:1) crop sheet. The user pans/pinches the image inside a fixed square
/// aperture; the visible square IS the preview. Emits a NORMALIZED crop rect (0...1) that is stored
/// as preview-framing metadata — the full image/video is never modified.
struct MediaCropView: View {
    let imageData: Data?
    let isVideo: Bool
    let initialCrop: CGRect
    let onUse: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var cropRect: CGRect
    @State private var resetToken = 0

    init(imageData: Data?, isVideo: Bool, initialCrop: CGRect, onUse: @escaping (CGRect) -> Void) {
        self.imageData = imageData
        self.isVideo = isVideo
        self.initialCrop = initialCrop
        self.onUse = onUse
        _cropRect = State(initialValue: initialCrop)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    Text(isVideo ? "Framing the preview poster" : "Frame the preview")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)

                    if let image {
                        CropScrollView(image: image, initialCrop: initialCrop, resetToken: resetToken, cropRect: $cropRect)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            .accessibilityIdentifier("media.crop.image")
                    } else {
                        ProgressView()
                            .tint(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                    }

                    Text("Drag and pinch to choose how this appears in previews.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer(minLength: 0)
                }
                .padding(.top)
            }
            .navigationTitle("Crop preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("media.crop.cancel")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Reset") {
                        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        resetToken += 1
                    }
                    .accessibilityIdentifier("media.crop.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse(cropRect)
                        dismiss()
                    }
                    .disabled(image == nil)
                    .accessibilityIdentifier("media.crop.use")
                }
            }
            .tint(Theme.textPrimary)
            .task(id: imageData) {
                image = await Self.decode(imageData)
            }
        }
    }

    private static func decode(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let raw = UIImage(data: data) else { return nil }
            return raw.preparingForDisplay() ?? raw
        }.value
    }
}

/// UIScrollView-backed square cropper. Aspect-FILL minimum zoom keeps the image covering the
/// aperture at all times, so the visible square always maps to a valid normalized rect.
private struct CropScrollView: UIViewRepresentable {
    let image: UIImage
    let initialCrop: CGRect
    let resetToken: Int
    @Binding var cropRect: CGRect

    func makeCoordinator() -> Coordinator {
        Coordinator(cropRect: $cropRect)
    }

    func makeUIView(context: Context) -> LayoutReportingScrollView {
        let scrollView = LayoutReportingScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        scrollView.contentSize = image.size

        context.coordinator.imageView = imageView
        context.coordinator.image = image
        context.coordinator.initialCrop = initialCrop
        scrollView.onLayout = { [weak coordinator = context.coordinator] sv in
            coordinator?.layoutChanged(sv)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: LayoutReportingScrollView, context: Context) {
        // A bumped resetToken means "return to default center-fill framing".
        if context.coordinator.appliedResetToken != resetToken {
            context.coordinator.appliedResetToken = resetToken
            context.coordinator.initialCrop = CGRect(x: 0, y: 0, width: 1, height: 1)
            context.coordinator.needsConfigure = true
            scrollView.setNeedsLayout()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var cropRect: CGRect
        var imageView: UIImageView?
        var image: UIImage = UIImage()
        var initialCrop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        var appliedResetToken = 0
        var needsConfigure = true
        private var configuredBoundsSize: CGSize = .zero

        init(cropRect: Binding<CGRect>) {
            _cropRect = cropRect
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Ignore the zoom events emitted while we programmatically configure; otherwise the
            // intermediate (pre-offset) state would overwrite the seeded full-frame/saved crop.
            guard !needsConfigure else { return }
            reportRect(scrollView)
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Ignore the scroll events emitted while we programmatically configure.
            guard !needsConfigure else { return }
            reportRect(scrollView)
        }

        func layoutChanged(_ scrollView: UIScrollView) {
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            if needsConfigure || size != configuredBoundsSize {
                configure(scrollView, side: min(size.width, size.height))
                configuredBoundsSize = size
                needsConfigure = false
            }
        }

        private func configure(_ scrollView: UIScrollView, side: CGFloat) {
            let imgW = image.size.width
            let imgH = image.size.height
            guard imgW > 0, imgH > 0, side > 0 else { return }

            let minZoom = max(side / imgW, side / imgH)
            scrollView.minimumZoomScale = minZoom
            scrollView.maximumZoomScale = max(minZoom * 4, minZoom)

            let crop = initialCrop
            let isFullFrame = crop.origin.x <= 0 && crop.origin.y <= 0 && crop.width >= 1 && crop.height >= 1
            let zoom: CGFloat
            if isFullFrame || crop.width <= 0 {
                zoom = minZoom
            } else {
                zoom = min(max(side / (crop.width * imgW), minZoom), scrollView.maximumZoomScale)
            }
            scrollView.zoomScale = zoom

            let contentW = imgW * zoom
            let contentH = imgH * zoom
            let maxOffsetX = max(contentW - side, 0)
            let maxOffsetY = max(contentH - side, 0)
            let offsetX: CGFloat
            let offsetY: CGFloat
            if isFullFrame || crop.width <= 0 {
                offsetX = maxOffsetX / 2
                offsetY = maxOffsetY / 2
            } else {
                offsetX = min(max(crop.origin.x * contentW, 0), maxOffsetX)
                offsetY = min(max(crop.origin.y * contentH, 0), maxOffsetY)
            }
            scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
        }

        private func reportRect(_ scrollView: UIScrollView) {
            let cs = scrollView.contentSize
            let side = min(scrollView.bounds.width, scrollView.bounds.height)
            guard cs.width > 0, cs.height > 0, side > 0 else { return }
            let offset = scrollView.contentOffset
            let rect = CGRect(
                x: min(max(offset.x / cs.width, 0), 1),
                y: min(max(offset.y / cs.height, 0), 1),
                width: min(side / cs.width, 1),
                height: min(side / cs.height, 1)
            )
            if rect != cropRect {
                cropRect = rect
            }
        }
    }
}

/// A UIScrollView that reports when its bounds-driven layout changes so the cropper can configure
/// zoom/offset once the aperture size is known.
private final class LayoutReportingScrollView: UIScrollView {
    var onLayout: ((LayoutReportingScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
