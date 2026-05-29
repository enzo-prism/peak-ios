//
//  ContentView.swift
//  Peak
//
//  Created by Enzo on 1/9/26.
//

import SwiftUI
import SwiftData

enum AppTab: String, Hashable {
    case log, history, stats, quiver, more
}

struct ContentView: View {
    var storeState: PeakDataStore.LoadState = .healthy
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .log
    @State private var showStoreAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                LogView()
                    .tag(AppTab.log)
                    .tabItem {
                        Label("Log", image: "list-bullet")
                    }

                HistoryView()
                    .tag(AppTab.history)
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                StatsView()
                    .tag(AppTab.stats)
                    .tabItem {
                        Label("Stats", image: "figure-surfing")
                    }

                NavigationStack {
                    QuiverView()
                }
                .tag(AppTab.quiver)
                .tabItem {
                    Label("Quiver", image: "surfboard")
                }

                MoreView()
                    .tag(AppTab.more)
                    .tabItem {
                        Label("More", systemImage: "water.waves")
                    }
            }
            .tint(Theme.textPrimary)
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackground(Color.clear, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .font(.peak(16, relativeTo: .body))
        }
        .task {
            if storeState != .healthy {
                showStoreAlert = true
            }
        }
        .alert("Data Recovery", isPresented: $showStoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storeAlertMessage)
        }
    }

    private var storeAlertMessage: String {
        switch storeState {
        case .healthy:
            return ""
        case .recoveredFromCorruption(let backupName):
            return "Peak couldn't open your existing surf log, so it saved a backup (\(backupName)) and started fresh. Email support if you need help recovering it."
        case .inMemoryFallback:
            return "Peak couldn't open or create its data store, so changes made this session won't be saved. Restart your device, and reinstall if this keeps happening."
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
