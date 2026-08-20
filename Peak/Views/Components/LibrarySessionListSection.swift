import SwiftUI

/// Session history on spot / gear / buddy detail. Shows a short recent prefix,
/// then the rest behind a disclosure — Apple's progressive-disclosure pattern
/// so a deep logbook does not bury the metrics above.
struct LibrarySessionListSection: View {
    let title: String
    let sessions: [SurfSession]
    var previewLimit: Int = LibrarySessionPreview.limit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: title)

            if sessions.isEmpty {
                Text("No sessions yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
            } else {
                ForEach(preview) { session in
                    sessionLink(session)
                }

                if LibrarySessionPreview.remainderCount(total: sessions.count, limit: previewLimit) > 0 {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(remainder) { session in
                                sessionLink(session)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Show \(remainder.count) older")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.textPrimary)
                    .padding(Theme.Spacing.m)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
                    .transaction { transaction in
                        if reduceMotion { transaction.animation = nil }
                    }
                    .accessibilityHint("Shows older sessions at this item")
                }
            }
        }
    }

    private var preview: ArraySlice<SurfSession> {
        sessions.prefix(previewLimit)
    }

    private var remainder: ArraySlice<SurfSession> {
        sessions.dropFirst(previewLimit)
    }

    private func sessionLink(_ session: SurfSession) -> some View {
        NavigationLink {
            SessionDetailView(session: session)
        } label: {
            SessionRowView(session: session)
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }
}

enum LibrarySessionPreview {
    static let limit = 5

    static func remainderCount(total: Int, limit: Int = limit) -> Int {
        max(0, total - limit)
    }
}
