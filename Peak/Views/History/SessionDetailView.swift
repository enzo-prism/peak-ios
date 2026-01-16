import AVKit
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

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if media.kind == .video {
                    if let url = media.videoFileName.map(SessionMediaStore.videoURL(for:)) {
                        VideoPlayer(player: player)
                            .onAppear {
                                player = AVPlayer(url: url)
                                player?.play()
                            }
                            .onDisappear {
                                player?.pause()
                            }
                    } else {
                        Text("Video unavailable.")
                            .foregroundStyle(Theme.textMuted)
                    }
                } else if let data = media.photoData, let image = UIImage(data: data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                    }
                } else {
                    Text("Photo unavailable.")
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .navigationTitle("Media")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SessionDetailView(session: SurfSession(date: Date(), spot: Spot(name: "Trestles"), rating: 4, notes: "Fun peaks."))
        .modelContainer(PreviewData.container)
}
