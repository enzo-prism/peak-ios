import SwiftUI
import SwiftData

struct ContentView: View {
    @Bindable private var quickLog = QuickLogCoordinator.shared
    @Bindable private var navigation = PeakNavigationCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            tabShell
                .tint(Theme.accent)
                .tabBarMinimizeOnScroll()
        }
        // Clearing on dismiss means a prefill is used exactly once: the next
        // manual "Log Session" opens blank whether the surfer saved or cancelled.
        .sheet(isPresented: $quickLog.showNewSession, onDismiss: { quickLog.pendingLog = nil }) {
            SessionEditorView(mode: .new, prefill: prefillDraft)
        }
        .task {
            if let url = TestingDefaults.launchDeepLinkURL {
                handleDeepLink(url)
            }
            quickLog.drainPendingLogFromStore()
            WidgetSnapshotWriter.update(from: sessions)
            SpotlightIndexer.donate(sessions: sessions, spots: spots, gear: gear)
            if healthSyncEnabled {
                HealthKitService.shared.startObservingUnloggedWorkouts()
            }
        }
        .onChange(of: sessionsStamp) {
            WidgetSnapshotWriter.update(from: sessions)
            SpotlightIndexer.donate(sessions: sessions, spots: spots, gear: gear)
        }
        .onChange(of: healthSyncEnabled) { _, isOn in
            if isOn {
                HealthKitService.shared.startObservingUnloggedWorkouts()
            } else {
                HealthKitService.shared.stopObservingUnloggedWorkouts()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                quickLog.drainPendingLogFromStore()
                WidgetSnapshotWriter.update(from: sessions)
                if healthSyncEnabled {
                    HealthKitService.shared.startObservingUnloggedWorkouts()
                }
            } else if newPhase == .background {
                Task {
                    await UnloggedSurfNotification.considerPosting(
                        sessions: sessions,
                        spots: spots,
                        scenePhase: newPhase
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .peakUnloggedWorkoutsMayHaveChanged)) { _ in
            Task {
                await UnloggedSurfNotification.considerPosting(
                    sessions: sessions,
                    spots: spots,
                    scenePhase: scenePhase
                )
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    @ViewBuilder
    private var tabShell: some View {
        if #available(iOS 18.0, *) {
            modernTabView
        } else {
            legacyTabView
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $navigation.selectedTab) {
            LogView()
                .tabItem { Label(PeakTab.log.title, systemImage: PeakTab.log.systemImage) }
                .tag(PeakTab.log)

            HistoryView()
                .tabItem { Label(PeakTab.history.title, systemImage: PeakTab.history.systemImage) }
                .tag(PeakTab.history)

            StatsView()
                .tabItem { Label(PeakTab.stats.title, systemImage: PeakTab.stats.systemImage) }
                .tag(PeakTab.stats)

            QuiverView()
                .tabItem { Label(PeakTab.quiver.title, systemImage: PeakTab.quiver.systemImage) }
                .tag(PeakTab.quiver)

            MoreView()
                .tabItem { Label(PeakTab.more.title, systemImage: PeakTab.more.systemImage) }
                .tag(PeakTab.more)
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: $navigation.selectedTab) {
            Tab(PeakTab.log.title, systemImage: PeakTab.log.systemImage, value: PeakTab.log) {
                LogView()
            }
            .customizationID("peak.log")

            Tab(PeakTab.history.title, systemImage: PeakTab.history.systemImage, value: PeakTab.history) {
                HistoryView()
            }
            .customizationID("peak.history")

            Tab(PeakTab.stats.title, systemImage: PeakTab.stats.systemImage, value: PeakTab.stats) {
                StatsView()
            }
            .customizationID("peak.stats")

            Tab(PeakTab.quiver.title, systemImage: PeakTab.quiver.systemImage, value: PeakTab.quiver) {
                QuiverView()
            }
            .customizationID("peak.quiver")

            Tab(PeakTab.more.title, systemImage: PeakTab.more.systemImage, value: PeakTab.more) {
                MoreView()
            }
            .customizationID("peak.more")

            Tab(value: PeakTab.search, role: .search) {
                HistoryView(isDedicatedSearchTab: true)
            }
            .customizationID("peak.search")

            TabSection("Library") {
                Tab(PeakTab.spots.title, systemImage: PeakTab.spots.systemImage, value: PeakTab.spots) {
                    SpotLibraryView(isLibraryTab: true)
                }
                .defaultVisibility(.hidden, for: .tabBar)
                .customizationID("peak.spots")

                Tab(PeakTab.buddies.title, systemImage: PeakTab.buddies.systemImage, value: PeakTab.buddies) {
                    NavigationStack {
                        BuddyLibraryView()
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
                .customizationID("peak.buddies")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private func handleDeepLink(_ url: URL) {
        guard let destination = PeakDeepLink.parse(url) else { return }
        navigation.handle(destination)
    }

    /// A session ended outside the editor opens it prefilled; everything else
    /// gets a blank draft.
    private var prefillDraft: SessionDraft? {
        guard let record = quickLog.pendingLog else { return nil }
        return ActiveSessionCalculator.makeDraft(from: record, spots: spots)
    }

    /// Cheap change signature covering inserts, deletes, and edits (via
    /// `updatedAt`); mirrors `HistoryView.sessionsStamp`.
    private var sessionsStamp: Int {
        var hasher = Hasher()
        for session in sessions {
            hasher.combine(session.persistentModelID)
            hasher.combine(session.updatedAt)
        }
        hasher.combine(spots.count)
        hasher.combine(gear.count)
        return hasher.finalize()
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
