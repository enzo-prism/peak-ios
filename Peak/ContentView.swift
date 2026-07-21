//
//  ContentView.swift
//  Peak
//
//  Created by Enzo on 1/9/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Bindable private var quickLog = QuickLogCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @Query(sort: \Spot.name) private var spots: [Spot]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            TabView {
                LogView()
                    .tabItem {
                        Label("Log", systemImage: "square.and.pencil")
                    }

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                StatsView()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar.xaxis")
                    }

                NavigationStack {
                    QuiverView()
                }
                .tabItem {
                    Label("Quiver", systemImage: "surfboard")
                }

                MoreView()
                    .tabItem {
                        Label("More", systemImage: "ellipsis.circle")
                    }
            }
            .tint(Theme.accent)
            .tabBarMinimizeOnScroll()
        }
        // Clearing on dismiss means a prefill is used exactly once: the next
        // manual "Log Session" opens blank whether the surfer saved or cancelled.
        .sheet(isPresented: $quickLog.showNewSession, onDismiss: { quickLog.pendingLog = nil }) {
            SessionEditorView(mode: .new, prefill: prefillDraft)
        }
        // Snapshot refresh points: launch, any session insert/edit/delete (the
        // @Query republishes, which also covers a backup restore), and every
        // return to the foreground so "days since" doesn't go stale on the
        // Home Screen.
        .task {
            // The UI suite can't make the system deliver a widget tap, so it
            // injects the URL and it takes the same route a real tap does.
            if let url = TestingDefaults.launchDeepLinkURL {
                handleDeepLink(url)
            }
            quickLog.drainPendingLogFromStore()
            WidgetSnapshotWriter.update(from: sessions)
        }
        .onChange(of: sessions) { _, newValue in
            WidgetSnapshotWriter.update(from: newValue)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            quickLog.drainPendingLogFromStore()
            WidgetSnapshotWriter.update(from: sessions)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard PeakDeepLink.isNewSession(url) else { return }
        quickLog.requestNewSession()
    }

    /// A session ended outside the editor opens it prefilled; everything else
    /// gets a blank draft.
    private var prefillDraft: SessionDraft? {
        guard let record = quickLog.pendingLog else { return nil }
        return ActiveSessionCalculator.makeDraft(from: record, spots: spots)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
