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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView {
                LogView()
                    .tabItem {
                        Label("Log", image: "list-bullet")
                    }

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                StatsView()
                    .tabItem {
                        Label("Stats", image: "figure-surfing")
                    }

                NavigationStack {
                    QuiverView()
                }
                .tabItem {
                    Label("Quiver", image: "surfboard")
                }

                MoreView()
                    .tabItem {
                        Label("More", systemImage: "water.waves")
                    }
            }
            .tint(Theme.textPrimary)
            .toolbarColorScheme(.dark, for: .tabBar)
            .tabBarMinimizeOnScroll()
            .font(.custom("Avenir Next", size: 16, relativeTo: .body))
        }
        .sheet(isPresented: $quickLog.showNewSession) {
            SessionEditorView(mode: .new)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
