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
    @State private var didDelete = false
    @State private var selectedMedia: SessionMedia?
    @State private var showSurfReportSection = true
    @State private var showGearSection = false
    @State private var showBuddiesSection = false
    @State private var showMediaSection = false
    @State private var showNotesSection = false
    @State private var healthStats: SessionHealthStats?
    @State private var shareContent: SessionShareContent?
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                GlassContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        heroCard

                        healthCard

                        if !surfReportRows.isEmpty {
                            detailDisclosureSection("Surf report", isExpanded: $showSurfReportSection) {
                                ForEach(surfReportRows.indices, id: \.self) { index in
                                    let row = surfReportRows[index]
                                    detailRow(title: row.title, value: row.value)
                                }
                            }
                        }

                        if !session.gear.isEmpty {
                            detailDisclosureSection("Gear", isExpanded: $showGearSection) {
                                ForEach(session.gear.sorted(by: { $0.name < $1.name }), id: \.persistentModelID) { gear in
                                    detailRow(title: gear.kind.label, value: gear.name)
                                }
                            }
                        }

                        if !session.buddies.isEmpty {
                            detailDisclosureSection("Buddies", isExpanded: $showBuddiesSection) {
                                ForEach(session.buddies.sorted(by: { $0.name < $1.name }), id: \.persistentModelID) { buddy in
                                    detailRow(title: "Buddy", value: buddy.name)
                                }
                            }
                        }

                        if !session.media.isEmpty {
                            detailDisclosureSection("Media", isExpanded: $showMediaSection) {
                                mediaSection
                            }
                        }

                        if !session.notes.isEmpty {
                            detailDisclosureSection("Notes", isExpanded: $showNotesSection) {
                                Text(session.notes)
                                    .font(.body)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Session", systemImage: "trash")
                                .foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle(prominent: false)
                    }
                    .padding()
                    .readableContentWidth()
                }
            }
        }
        .navigationTitle("Session")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareToolbarButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .task {
            await loadHealthStats()
            await prepareShareContent()
        }
        .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Capture + remove the Health workout BEFORE deleting the model:
                // the stable key is derived from `session.createdAt`, read
                // synchronously inside deleteWorkout(for:). No-op when Health
                // sync is off/unauthorized.
                HealthKitService.shared.deleteWorkout(for: session)
                SessionMediaStore.deleteStoredMedia(for: session.media)
                modelContext.delete(session)
                didDelete = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: didDelete)
        .sheet(isPresented: $showEdit) {
            SessionEditorView(mode: .edit(session))
        }
        .sheet(item: $selectedMedia) { media in
            SessionMediaViewer(media: media)
        }
    }

    // MARK: - Apple Health

    /// Compact avg/max HR + active-energy card. Shown only when Health sync is
    /// enabled AND real data came back. `fetchStats` returns nil when disabled,
    /// unavailable, denied, or empty, so this stays silent — it never implies a
    /// permission was refused.
    @ViewBuilder
    private var healthCard: some View {
        if healthSyncEnabled, let stats = healthStats, !stats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.surfGreen)
                    Text("APPLE HEALTH")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                }

                HStack(alignment: .top, spacing: 12) {
                    if let average = stats.averageHeartRate {
                        healthMetric(title: "Avg HR", value: "\(Int(average.rounded()))", unit: "bpm")
                    }
                    if let maximum = stats.maxHeartRate {
                        healthMetric(title: "Max HR", value: "\(Int(maximum.rounded()))", unit: "bpm")
                    }
                    if let energy = stats.activeEnergyKilocalories {
                        healthMetric(title: "Active", value: "\(Int(energy.rounded()))", unit: "cal")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("session.detail.healthCard")
        }
    }

    private func healthMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var shareToolbarButton: some View {
        if let shareContent {
            ShareLink(
                item: shareContent,
                preview: SharePreview(shareContent.caption, image: Image(uiImage: shareContent.image))
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share session")
            .accessibilityIdentifier("session.detail.share")
        } else {
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("Share session")
            .accessibilityIdentifier("session.detail.share")
        }
    }

    private func loadHealthStats() async {
        guard healthSyncEnabled else { return }
        healthStats = await HealthKitService.shared.fetchStats(for: session)
    }

    private func prepareShareContent() async {
        shareContent = await SessionShareCardRenderer.makeContent(for: session)
    }

    private var conditionsSummaryCount: Int { surfReportRows.count }

    @ViewBuilder
    private func detailDisclosureSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 8)
        } label: {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Spacing.l)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        // Honor Reduce Motion: strip the disclosure's expand/collapse animation,
        // matching the session editor's behavior.
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    if session.rating > 0 {
                        heroRatingStars(session.rating)
                    }
                }

                Text(session.spot?.name ?? "Unknown spot")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.media.isEmpty {
                heroMediaStrip
            }

            heroWaveHeightView

            heroTags

            if conditionsSummaryCount > 0 {
                heroTag("\(conditionsSummaryCount) condition details", icon: "chart.bar.fill")
            }

            if !session.notes.isEmpty {
                Text(session.notes)
                    .lineLimit(2)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    /// Wave height resolved for the glanceable hero block: (primary, optional secondary).
    /// Category + measured -> "Shoulder high" / "3.9 ft"; category only -> just the label;
    /// measured only -> the measurement as primary; neither -> nil (block hidden).
    private var heroWaveHeight: (primary: String, secondary: String?)? {
        let category = session.waveHeight?.label
        let precise = session.waveHeightMeters.map { SurfConditionsFormatter.meters($0) }
        switch (category, precise) {
        case let (cat?, m?): return (cat, m)
        case let (cat?, nil): return (cat, nil)
        case let (nil, m?): return (m, nil)
        default: return nil
        }
    }

    @ViewBuilder
    private var heroWaveHeightView: some View {
        if let wave = heroWaveHeight {
            HStack(spacing: 10) {
                Image(systemName: "water.waves")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.surfGreen)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(wave.primary)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let secondary = wave.secondary {
                        Text(secondary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassTint, isInteractive: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wave height: \(wave.primary)" + (wave.secondary.map { ", \($0)" } ?? ""))
            .accessibilityIdentifier("session.detail.heroWaveHeight")
        }
    }

    @ViewBuilder
    private func heroTag(
        _ text: String,
        icon: String? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        let tag = HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)

        if let accessibilityIdentifier {
            tag.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            tag
        }
    }

    private func heroRatingStars(_ rating: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(value <= rating ? Theme.textPrimary : Theme.textMuted.opacity(0.55))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) out of 5")
    }

    /// Media front-and-center in the header: a horizontally scrolling strip of large, tappable
    /// thumbnails. Reuses `SessionMediaThumbnailView` (off-main-thread decode + crop) so it matches
    /// the body grid styling, and opens the full-screen viewer on tap. Distinct accessibility
    /// identifiers keep it separate from the collapsible body grid below.
    private var heroMediaStrip: some View {
        let ordered = session.media.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ordered, id: \.persistentModelID) { media in
                    Button {
                        selectedMedia = media
                    } label: {
                        SessionMediaThumbnailView(
                            imageData: media.thumbnailData ?? media.photoData,
                            isVideo: media.kind == .video,
                            crop: media.cropRect
                        )
                        .frame(width: 140, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                        .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                    .accessibilityLabel(media.kind == .video ? "Video" : "Photo")
                    .accessibilityIdentifier(media.kind == .video ? "session.detail.heroMedia.video" : "session.detail.heroMedia.photo")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var heroTags: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                heroTagContent
            }

            LazyVGrid(columns: heroTagColumns, alignment: .leading, spacing: 10) {
                heroTagContent
            }
        }
    }

    private var heroTagColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 104),
                spacing: 10,
                alignment: .leading
            )
        ]
    }

    @ViewBuilder
    private var heroTagContent: some View {
        heroTag(
            SessionDurationFormatter.string(from: session.durationMinutes),
            icon: "timer",
            accessibilityIdentifier: "session.detail.heroTag.duration"
        )
        heroTag(
            session.date.formatted(.dateTime.hour().minute()),
            icon: "clock",
            accessibilityIdentifier: "session.detail.heroTag.time"
        )
        if !session.gear.isEmpty {
            heroTag(
                "\(session.gear.count) gear",
                icon: "surfboard",
                accessibilityIdentifier: "session.detail.heroTag.gear"
            )
        }
        if !session.buddies.isEmpty {
            heroTag(
                "\(session.buddies.count) buddy\(session.buddies.count == 1 ? "" : "s")",
                icon: "person.2.fill",
                accessibilityIdentifier: "session.detail.heroTag.buddy"
            )
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        DetailInfoRow(title: title, value: value)
    }

    private var surfReportRows: [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = []

        if let waveHeightMeters = session.waveHeightMeters {
            rows.append((title: "Wave height", value: SurfConditionsFormatter.meters(waveHeightMeters)))
        }

        if let swellWaveHeightMeters = session.swellWaveHeightMeters {
            rows.append((title: "Swell height", value: SurfConditionsFormatter.meters(swellWaveHeightMeters)))
        }

        if let swellWavePeriodSeconds = session.swellWavePeriodSeconds {
            rows.append((title: "Swell period", value: SurfConditionsFormatter.period(swellWavePeriodSeconds)))
        }

        if let swellWaveDirectionDegrees = session.swellWaveDirectionDegrees {
            rows.append((title: "Swell direction", value: SurfConditionsFormatter.direction(swellWaveDirectionDegrees)))
        }

        if let windWaveHeightMeters = session.windWaveHeightMeters {
            rows.append((title: "Wind wave height", value: SurfConditionsFormatter.meters(windWaveHeightMeters)))
        }

        if let windWavePeriodSeconds = session.windWavePeriodSeconds {
            rows.append((title: "Wind wave period", value: SurfConditionsFormatter.period(windWavePeriodSeconds)))
        }

        if let windWaveDirectionDegrees = session.windWaveDirectionDegrees {
            rows.append((title: "Wind wave direction", value: SurfConditionsFormatter.direction(windWaveDirectionDegrees)))
        }

        if let windSpeedKph = session.windSpeedKph {
            rows.append((title: "Wind speed", value: SurfConditionsFormatter.speed(windSpeedKph)))
        }

        if let windDirectionDegrees = session.windDirectionDegrees {
            rows.append((title: "Wind direction", value: SurfConditionsFormatter.direction(windDirectionDegrees)))
        }

        if let seaSurfaceTemperatureC = session.seaSurfaceTemperatureC {
            rows.append((title: "Water temp", value: SurfConditionsFormatter.temperature(seaSurfaceTemperatureC)))
        }

        // "Tide", not "High tide at 06:12": the source is a modelled MSL curve,
        // good for direction and rough state only. See SurfConditionsFormatter.tide.
        if let tide = SurfConditionsFormatter.tide(
            trend: session.tide,
            seaLevelMeters: session.seaLevelHeightM
        ) {
            rows.append((title: "Tide", value: tide))
        }

        if let source = session.conditionsSource {
            let sourceValue: String
            if let fetchedAt = session.conditionsFetchedAt {
                sourceValue = "\(source) - \(fetchedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
            } else {
                sourceValue = source
            }
            rows.append((title: "Source", value: sourceValue))
        }

        return rows
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(session.media.sorted(by: { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }), id: \.persistentModelID) { media in
                    Button {
                        selectedMedia = media
                    } label: {
                        SessionMediaThumbnailView(
                            imageData: media.thumbnailData ?? media.photoData,
                            isVideo: media.kind == .video,
                            crop: media.cropRect
                        )
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                        .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                    .accessibilityLabel(media.kind == .video ? "Video" : "Photo")
                    .accessibilityIdentifier(media.kind == .video ? "session.media.video" : "session.media.photo")
                }
            }
        }
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
            .task {
                guard photoImage == nil, media.kind == .photo else { return }
                let data = media.photoData ?? media.thumbnailData
                photoImage = await Task.detached(priority: .userInitiated) {
                    guard let data, let image = UIImage(data: data) else { return nil }
                    return image.preparingForDisplay() ?? image
                }.value
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
            .font(.subheadline.weight(.semibold))
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(dateLabel)
                    .font(.caption)
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
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)

            Text(message)
                .font(.subheadline)
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

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
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
        scrollView.zoomCoordinator = context.coordinator
        scrollView.currentImage = image
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

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        scrollView.currentImage = image
        context.coordinator.update(image: image, in: scrollView)
    }

    final class ZoomingScrollView: UIScrollView {
        var currentImage: UIImage?
        weak var zoomCoordinator: Coordinator?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let currentImage, let zoomCoordinator else { return }
            zoomCoordinator.update(image: currentImage, in: self)
        }
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
