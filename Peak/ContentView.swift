//
//  ContentView.swift
//  Peak
//
//  Created by Enzo on 1/9/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            LogView()
                .tabItem {
                    Label("Log", systemImage: "wave.3.right")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
        }
        .tint(Theme.textPrimary)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Theme.oceanDeep.opacity(0.95), for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .font(.custom("Avenir Next", size: 16, relativeTo: .body))
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
