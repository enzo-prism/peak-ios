import SwiftUI
import SwiftData

struct LogView: View {
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
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
                                        .font(.custom("Avenir Next", size: 17, relativeTo: .headline).weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .accessibilityIdentifier("log.recent.title")
                                    ForEach(sessions.prefix(3)) { session in
                                        NavigationLink {
                                            SessionDetailView(session: session)
                                        } label: {
                                            SessionRowView(session: session)
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
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 12)
                    .animation(.easeOut(duration: 0.6), value: showContent)
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
                            .font(.custom("Avenir Next", size: 36, relativeTo: .largeTitle).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("log.hero.title")
                        Text("Surf Log")
                            .font(.custom("Avenir Next", size: 13, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("Log a session in seconds. Date, spot, gear, buddies, and quick notes.")
                    .font(.custom("Avenir Next", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("log.hero.subtitle")

                Button {
                    showNewSession = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Log Session")
                            .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityIdentifier("log.hero.cta")
            }
            .padding(22)
            .glassCard(cornerRadius: 28, tint: Color.black, isInteractive: true)
            .padding(.horizontal)
            .accessibilityIdentifier("log.hero.card")
        }
    }

    private var logoBadge: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    LogView()
        .modelContainer(PreviewData.container)
}
