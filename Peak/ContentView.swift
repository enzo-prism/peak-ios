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
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackground(Color.clear, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .font(.custom("Avenir Next", size: 16, relativeTo: .body))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
