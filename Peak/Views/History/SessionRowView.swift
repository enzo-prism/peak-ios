import SwiftUI

struct SessionRowView: View {
    let session: SurfSession
    @Namespace private var chipNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.date.sessionTitle)
                        .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline).weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text(session.spot?.name ?? "Unknown spot")
                        .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.bold))
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
                        Label("\(session.gear.count)", systemImage: "wrench.and.screwdriver")
                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                    if !session.buddies.isEmpty {
                        Label("\(session.buddies.count)", systemImage: "person.2")
                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                    if !session.media.isEmpty {
                        Label("\(session.media.count)", systemImage: "photo.on.rectangle")
                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                    if !session.notes.isEmpty {
                        Label("Notes", systemImage: "note.text")
                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                            .glassUnion(id: "chips", namespace: chipNamespace)
                    }
                }
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 20, tint: Theme.glassDimTint, isInteractive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("history.row")
    }
}

private struct RatingStarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.custom("Avenir Next", size: 11, relativeTo: .caption2))
                    .foregroundStyle(value <= rating ? Theme.textPrimary : Theme.textMuted.opacity(0.4))
            }
        }
    }
}

#Preview {
    SessionRowView(session: SurfSession(date: Date(), spot: Spot(name: "Trestles"), rating: 4, notes: "Nice lefts."))
        .padding()
        .background(Theme.background)
}
