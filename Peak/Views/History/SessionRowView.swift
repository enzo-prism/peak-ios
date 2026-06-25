import SwiftData
import SwiftUI

struct SessionRowView: View {
    let session: SurfSession
    /// Opt-in: the Log tab passes true to show cropped media previews. History keeps the default
    /// (false) so its rows stay pixel- and hit-area-identical.
    var showsMediaPreviews: Bool = false
    @Namespace private var chipNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.date.sessionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text(session.spot?.name ?? "Unknown spot")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if session.rating > 0 {
                    RatingStarsView(rating: session.rating)
                }
            }

            GlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !session.gear.isEmpty {
                        Label("\(session.gear.count)", systemImage: "surfboard")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                    if !session.buddies.isEmpty {
                        Label("\(session.buddies.count)", systemImage: "person.2")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                    if !session.media.isEmpty && !showsMediaPreviews {
                        Label("\(session.media.count)", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                    if !session.notes.isEmpty {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                }
            }
            .foregroundStyle(Theme.textSecondary)

            if showsMediaPreviews && !session.media.isEmpty {
                mediaPreviewStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("history.row")
    }

    private var mediaPreviewStrip: some View {
        let ordered = session.media.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
        return HStack(spacing: 6) {
            ForEach(ordered.prefix(4), id: \.persistentModelID) { media in
                SessionMediaThumbnailView(
                    imageData: media.thumbnailData ?? media.photoData,
                    isVideo: media.kind == .video,
                    crop: media.cropRect
                )
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .glassCard(cornerRadius: 10, tint: Theme.glassDimTint, isInteractive: false)
            }
            if session.media.count > 4 {
                Text("+\(session.media.count - 4)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
            }
        }
        .accessibilityIdentifier("history.row.mediaStrip")
    }
}

private struct RatingStarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(value <= rating ? Theme.textPrimary : Theme.textMuted.opacity(0.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) out of 5")
    }
}

#Preview {
    SessionRowView(session: SurfSession(date: Date(), spot: Spot(name: "Trestles"), rating: 4, notes: "Nice lefts."))
        .padding()
        .background(Theme.background)
}
