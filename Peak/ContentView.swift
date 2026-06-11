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
        .sheet(isPresented: $quickLog.showNewSession) {
            SessionEditorView(mode: .new)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
