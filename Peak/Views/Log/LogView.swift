import SwiftUI
import SwiftData

struct LogView: View {
    @Query(SurfSession.sortedByDateDescending(limit: 3, prefetch: [\.spot, \.gear, \.buddies, \.media]))
    private var sessions: [SurfSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showNewSession = false
    @State private var showContent = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroCard

                        if sessions.isEmpty {
                            EmptyStateView(
                                title: "Start your log",
                                message: "Add a session in seconds and build your surf history.",
                                systemImage: "wave.3.right"
                            )
                        } else {
                            GlassContainer(spacing: 12) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Recent sessions")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .accessibilityIdentifier("log.recent.title")
                                    ForEach(sessions) { session in
                                        NavigationLink {
                                            SessionDetailView(session: session)
                                        } label: {
                                            SessionRowView(session: session, showsMediaPreviews: true)
                                                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        }
                                        .buttonStyle(PressFeedbackButtonStyle())
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    .readableContentWidth()
                    .opacity(showContent || reduceMotion ? 1 : 0)
                    .offset(y: showContent || reduceMotion ? 0 : 12)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: showContent)
                }
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewSession = true
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            SessionEditorView(mode: .new)
        }
        // Light impact when the primary "Log Session" action opens the editor,
        // matching the save/delete haptics elsewhere in the app.
        .sensoryFeedback(trigger: showNewSession) { _, isPresented in
            isPresented ? .impact : nil
        }
        .onAppear {
            showContent = true
        }
    }

    private var heroCard: some View {
        GlassContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    logoBadge
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Peak")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("log.hero.title")
                        Text("Surf Log")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("Log a session in seconds. Date, spot, gear, buddies, and quick notes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("log.hero.subtitle")

                Button {
                    showNewSession = true
                } label: {
                    Label("Log Session", systemImage: "plus")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
                .accessibilityIdentifier("log.hero.cta")
            }
            .padding(Theme.Spacing.xl)
            .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassTint, isInteractive: true)
            .padding(.horizontal)
            .accessibilityIdentifier("log.hero.card")
        }
    }

    // The mark ships in two forms — a foam mark for dark tiles and an ink mark
    // (LogoMarkLight) for light tiles — so the badge stays legible and on-brand
    // in both color schemes instead of a fixed near-black tile on white paper.
    private var logoBadge: some View {
        Image(colorScheme == .dark ? "LogoMark" : "LogoMarkLight")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.04) : Color(white: 0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.glassStroke, lineWidth: 1)
                    )
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    LogView()
        .modelContainer(PreviewData.container)
}
