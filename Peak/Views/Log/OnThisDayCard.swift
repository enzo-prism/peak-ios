import SwiftUI

/// The memory card on the Log tab: a session from a previous year, near its
/// anniversary. Tapping it opens the session it came from.
struct OnThisDayCard: View {
    let memory: OnThisDayMemory

    private var firstMedia: SessionMedia? {
        memory.session.media
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .first
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(memory.label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(memory.session.spot?.name ?? "Unknown spot")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(dateLine)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: true)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("On this day: \(memory.label)"))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text("Opens the session"))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let media = firstMedia {
            SessionMediaThumbnailView(
                imageData: media.thumbnailData ?? media.photoData,
                isVideo: media.kind == .video,
                crop: media.cropRect
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
        } else {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 56, height: 56)
                .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
        }
    }

    private var dateLine: String {
        let date = memory.session.date.formatted(.dateTime.month(.abbreviated).day().year())
        guard memory.session.rating > 0 else { return date }
        return "\(date) · \(memory.session.rating)★"
    }

    private var accessibilityValue: String {
        let spot = memory.session.spot?.name ?? "Unknown spot"
        let date = memory.session.date.formatted(.dateTime.month(.wide).day().year())
        guard memory.session.rating > 0 else { return "\(spot), \(date)" }
        return "\(spot), \(date), rated \(memory.session.rating) out of 5"
    }
}
