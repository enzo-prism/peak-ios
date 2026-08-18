import SwiftUI
import SwiftData

struct LogView: View {
    @Query(SurfSession.sortedByDateDescending(limit: 3, prefetch: [\.spot, \.gear, \.buddies, \.media]))
    private var sessions: [SurfSession]
    /// The memory layer needs the whole history — an anniversary lives years
    /// back, well outside the three-session recents window above.
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.media]))
    private var allSessions: [SurfSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// New-session presentation goes through the shared coordinator so the app
    /// has exactly one presenter (`ContentView`); a second local sheet here
    /// could race a system-initiated request (Live Activity / Control Center)
    /// and silently drop its prefilled draft.
    private var quickLog: QuickLogCoordinator { .shared }
    @State private var showContent = false
    /// Mirrors the App-Group record so the hero can swap between "start" and a
    /// live timer. Re-read on appear and whenever the surfer starts/ends.
    @State private var activeSession: ActiveSessionState?
    @State private var cachedMemory: OnThisDayMemory?
    @State private var cachedRecapYear: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroCard

                        // Above the memory layer: "when today?" is a question with
                        // a deadline, and "on this day in 2023" is not.
                        BestWindowTodayCard(sessions: allSessions)

                        UnloggedWorkoutCard(sessions: allSessions)
                            .padding(.horizontal)

                        if let cachedMemory {
                            NavigationLink {
                                SessionDetailView(session: cachedMemory.session)
                            } label: {
                                OnThisDayCard(memory: cachedMemory)
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .padding(.horizontal)
                        }

                        if let cachedRecapYear {
                            NavigationLink {
                                YearInReviewView(initialYear: cachedRecapYear)
                            } label: {
                                YearInReviewPromptCard(year: cachedRecapYear)
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .padding(.horizontal)
                        }

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
                                        .accessibilityAddTraits(.isHeader)
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
                        quickLog.requestNewSession()
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
        }
        // Light impact when the primary "Log Session" action opens the editor,
        // matching the save/delete haptics elsewhere in the app.
        .sensoryFeedback(trigger: quickLog.showNewSession) { _, isPresented in
            isPresented ? .impact : nil
        }
        .onAppear {
            showContent = true
            activeSession = ActiveSessionStore.loadActive()
            refreshMemories()
        }
        .onChange(of: allSessions) { _, _ in
            refreshMemories()
        }
    }

    /// December only: the recap is a year-end ritual, and a "your 2026 in
    /// review" card in March would be reviewing a year that isn't over.
    private func refreshMemories() {
        cachedMemory = OnThisDayProvider.memories(sessions: allSessions, limit: 1).first

        let now = Date()
        let calendar = Calendar.current
        if calendar.component(.month, from: now) == 12 {
            let year = calendar.component(.year, from: now)
            cachedRecapYear = YearInReviewCalculator.availableYears(sessions: allSessions).contains(year)
                ? year
                : nil
        } else {
            cachedRecapYear = nil
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
                    quickLog.requestNewSession()
                } label: {
                    Label("Log Session", systemImage: "plus")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
                .accessibilityIdentifier("log.hero.cta")
                .peakTip(LogSessionTip())

                sessionTimerControl
            }
            .padding(Theme.Spacing.xl)
            .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassTint, isInteractive: true)
            .padding(.horizontal)
            .accessibilityIdentifier("log.hero.card")
        }
    }

    /// Start/end control for a session logged as it happens. Starting parks the
    /// state in the App Group (and raises the Live Activity); ending hands the
    /// record to `QuickLogCoordinator`, which opens the editor prefilled.
    @ViewBuilder
    private var sessionTimerControl: some View {
        if let activeSession {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activeSession.spotName ?? "Session in progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        elapsedLabel(since: activeSession.startDate)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    endSession()
                } label: {
                    Label("End Session", systemImage: "stop.fill")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
                .accessibilityIdentifier("log.hero.end")
            }
        } else {
            Button {
                startSession()
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
            .accessibilityIdentifier("log.hero.start")
        }
    }

    /// A live counter in the app, a stable string under UI test — a ticking
    /// label would make every layout assertion on this screen a race.
    @ViewBuilder
    private func elapsedLabel(since startDate: Date) -> some View {
        if TestingDefaults.isUITest {
            Text("In progress")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        } else {
            Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Session running")
        }
    }

    /// Starts at the most recent session's spot — the recents-first default the
    /// rest of the app uses. The spot is still editable when the log opens.
    private func startSession() {
        let lastSpot = sessions.first?.spot
        let state = ActiveSessionState(
            spotKey: lastSpot?.key,
            spotName: lastSpot?.name,
            startDate: Date()
        )
        SessionActivityController.start(state)
        activeSession = state
    }

    private func endSession() {
        let record = SessionActivityController.end()
        activeSession = nil
        if let record {
            QuickLogCoordinator.shared.requestLog(for: record)
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
