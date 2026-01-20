import AVKit
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: SurfSession
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var selectedMedia: SessionMedia?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                GlassContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow(title: "Date", value: session.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                            detailRow(title: "Start time", value: session.date.formatted(.dateTime.hour().minute()))
                            if let durationMinutes = session.durationMinutes {
                                detailRow(title: "Duration", value: SessionDurationFormatter.string(from: durationMinutes))
                            }
                            if let windCondition = session.windCondition {
                                detailRow(title: "Wind", value: windCondition.label)
                            }
                            if let waveHeight = session.waveHeight {
                                detailRow(title: "Wave height", value: waveHeight.label)
                            }
                            detailRow(title: "Spot", value: session.spot?.name ?? "Unknown spot")
                            if session.rating > 0 {
                                detailRow(title: "Rating", value: "\(session.rating) / 5")
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: false)

                        if !session.gear.isEmpty {
                            infoCard(title: "Gear", items: session.gear.sorted(by: { $0.name < $1.name }).map { "\($0.name) (\($0.kind.label))" })
                        }

                        if !session.buddies.isEmpty {
                            infoCard(title: "Buddies", items: session.buddies.sorted(by: { $0.name < $1.name }).map { $0.name })
                        }

                        if !session.media.isEmpty {
                            mediaSection
                        }

                        if !session.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionTitle("Notes")
                                Text(session.notes)
                                    .font(.custom("Avenir Next", size: 15, relativeTo: .body))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(16)
                            .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: false)
                        }

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Session", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle(prominent: false)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Session")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                SessionMediaStore.deleteStoredMedia(for: session.media)
                modelContext.delete(session)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showEdit) {
            SessionEditorView(mode: .edit(session))
        }
        .sheet(item: $selectedMedia) { media in
            SessionMediaViewer(media: media)
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Text(value)
                .font(.custom("Avenir Next", size: 15, relativeTo: .body).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func infoCard(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: false)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
            .foregroundStyle(Theme.textMuted)
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Media")
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(session.media.sorted(by: { $0.createdAt < $1.createdAt }), id: \.persistentModelID) { media in
                    Button {
                        selectedMedia = media
                    } label: {
                        SessionMediaThumbnailView(
                            imageData: media.thumbnailData ?? media.photoData,
                            isVideo: media.kind == .video
                        )
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .glassCard(cornerRadius: 16, tint: Theme.glassDimTint, isInteractive: false)
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                    .accessibilityLabel(media.kind == .video ? "Video" : "Photo")
                    .accessibilityIdentifier(media.kind == .video ? "session.media.video" : "session.media.photo")
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: false)
    }
}

private struct SessionMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    let media: SessionMedia
    @State private var player: AVPlayer?
    @State private var photoImage: UIImage?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    Theme.background.ignoresSafeArea()

                    mediaContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    viewerHeader
                        .padding(.top, proxy.safeAreaInsets.top + 12)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if photoImage == nil, media.kind == .photo {
                    photoImage = (media.photoData ?? media.thumbnailData).flatMap(UIImage.init)
                }
            }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch media.kind {
        case .video:
            if let url = resolvedVideoURL {
                VideoPlayer(player: player)
                    .accessibilityIdentifier("media.viewer.video")
                    .accessibilityLabel("Video")
                    .aspectRatio(contentMode: .fit)
                    .onAppear {
                        startVideo(with: url)
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
                    .overlay {
                        if player == nil {
                            ProgressView()
                                .tint(Theme.textPrimary)
                        }
                    }
                    .ignoresSafeArea()
            } else {
                mediaUnavailableView(message: "Video unavailable.")
            }
        case .photo:
            if let image = photoImage {
                ZoomableImageView(
                    image: image,
                    accessibilityIdentifier: "media.viewer.photo"
                )
                .ignoresSafeArea()
            } else {
                mediaUnavailableView(message: "Photo unavailable.")
            }
        }
    }

    private var viewerHeader: some View {
        HStack(spacing: 12) {
            mediaBadge
            Spacer(minLength: 12)
            Button("Done") {
                dismiss()
            }
            .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassCapsule(tint: Theme.glassStrongTint, isInteractive: true)
            .contentShape(Capsule())
            .buttonStyle(PressFeedbackButtonStyle())
            .accessibilityIdentifier("media.viewer.done")
        }
    }

    private var mediaBadge: some View {
        let typeLabel = media.kind == .video ? "Video" : "Photo"
        let dateLabel = media.createdAt.formatted(.dateTime.month(.abbreviated).day().year())

        return HStack(spacing: 8) {
            Image(systemName: media.kind == .video ? "video" : "photo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.custom("Avenir Next", size: 13, relativeTo: .subheadline).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(dateLabel)
                    .font(.custom("Avenir Next", size: 11, relativeTo: .caption))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(typeLabel), \(dateLabel)")
        .accessibilityIdentifier("media.viewer.badge")
    }

    private var resolvedVideoURL: URL? {
        guard let fileName = media.videoFileName else { return nil }
        let url = SessionMediaStore.videoURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func startVideo(with url: URL) {
        if let currentAsset = player?.currentItem?.asset as? AVURLAsset, currentAsset.url == url {
            player?.play()
            return
        }
        let newPlayer = AVPlayer(url: url)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        newPlayer.play()
    }

    @ViewBuilder
    private func mediaUnavailableView(message: String) -> some View {
        VStack(spacing: 12) {
            SessionMediaThumbnailView(
                imageData: media.thumbnailData ?? media.photoData,
                isVideo: media.kind == .video
            )
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .glassCard(cornerRadius: 20, tint: Theme.glassDimTint, isInteractive: false)

            Text(message)
                .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Theme.textMuted)
        }
        .padding()
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let accessibilityIdentifier: String
    let onSingleTap: (() -> Void)?

    init(
        image: UIImage,
        accessibilityIdentifier: String,
        onSingleTap: (() -> Void)? = nil
    ) {
        self.image = image
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSingleTap = onSingleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.isAccessibilityElement = true
        scrollView.accessibilityIdentifier = accessibilityIdentifier
        scrollView.accessibilityLabel = "Photo"
        scrollView.accessibilityTraits = .image
        scrollView.accessibilityHint = "Pinch to zoom."

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.isAccessibilityElement = false
        scrollView.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.update(image: image, in: scrollView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        if onSingleTap != nil {
            let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
            singleTap.numberOfTapsRequired = 1
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(image: image, in: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        private let onSingleTap: (() -> Void)?
        private var lastBoundsSize: CGSize = .zero
        private var lastImageSize: CGSize = .zero

        init(onSingleTap: (() -> Void)?) {
            self.onSingleTap = onSingleTap
        }

        func update(image: UIImage, in scrollView: UIScrollView) {
            guard let imageView else { return }
            if imageView.image !== image {
                imageView.image = image
                lastImageSize = .zero
            }

            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            let needsLayout = boundsSize != lastBoundsSize || image.size != lastImageSize
            guard needsLayout else {
                centerImage(in: scrollView)
                return
            }

            lastBoundsSize = boundsSize
            lastImageSize = image.size

            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size

            let minScale = min(boundsSize.width / image.size.width, boundsSize.height / image.size.height)
            let maxScale = max(minScale * 4, 1)

            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = maxScale
            scrollView.zoomScale = minScale

            centerImage(in: scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView,
                  let imageView else { return }

            let minScale = scrollView.minimumZoomScale
            let maxScale = scrollView.maximumZoomScale

            if scrollView.zoomScale > minScale + 0.01 {
                scrollView.setZoomScale(minScale, animated: true)
                return
            }

            let targetScale = min(maxScale, max(minScale * 2.5, 1))
            let tapPoint = gesture.location(in: imageView)
            let zoomRect = zoomRect(for: scrollView, scale: targetScale, center: tapPoint)
            scrollView.zoom(to: zoomRect, animated: true)
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }

        private func zoomRect(for scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            return CGRect(origin: origin, size: size)
        }

        private func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }
            var frame = imageView.frame
            let boundsSize = scrollView.bounds.size

            frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0

            imageView.frame = frame
        }
    }
}

#Preview {
    SessionDetailView(session: SurfSession(date: Date(), spot: Spot(name: "Trestles"), rating: 4, notes: "Fun peaks."))
        .modelContainer(PreviewData.container)
}
