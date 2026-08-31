import SwiftUI
import SwiftData

struct ContentView: View {
    @Bindable private var quickLog = QuickLogCoordinator.shared
    @Bindable private var navigation = PeakNavigationCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Prefetch spots only: the widget snapshot and Spotlight entities read
    /// `session.spot`. Media blobs are unused here and must not be pulled in
    /// (Apple: prefetch relationships you will read, not every relationship).
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot]))
    private var sessions: [SurfSession]
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                        spots: spots
                    )
                }
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

            if showsSidebarTabs {
                Tab(value: PeakTab.search, role: .search) {
                    SearchHistoryTab(isSelected: navigation.selectedTab == .search)
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
        }
        .modifier(SidebarAdaptableTabStyle(
            enabled: showsSidebarTabs
        ))
    }

    /// Extra library/search tabs belong to the iPad sidebar. Keeping them out
    /// of compact tab bars prevents iOS from replacing Peak's fifth tab with
    /// the system overflow screen.
    private var showsSidebarTabs: Bool {
        horizontalSizeClass == .regular && !TestingDefaults.isUITest
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
    /// `updatedAt`); also counts spots/gear so new library rows refresh widgets.
    private var sessionsStamp: Int {
        var hasher = Hasher()
        hasher.combine(SessionQueryStamp.make(sessions))
        hasher.combine(spots.count)
        hasher.combine(gear.count)
        return hasher.finalize()
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}

/// iOS 18 Search tab reuses History. `@Query` on an unused Tab sibling still
/// fetches the whole logbook (History prefetches media), so this host only
/// instantiates History while Search is selected. Idle Search is a prompt, not
/// a second timeline. Search *intents* still land on the History tab.
private struct SearchHistoryTab: View {
    var isSelected: Bool

    var body: some View {
        if isSelected {
            HistoryView(isDedicatedSearchTab: true)
        }
    }
}

/// iPad regular width uses the sidebar-adaptable tab style. Compact (iPhone)
/// and UI tests keep the classic tab bar so existing XCUI tab taps still work.
private struct SidebarAdaptableTabStyle: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), enabled {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
