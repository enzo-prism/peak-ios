//
//  PeakApp.swift
//  Peak
//
//  Created by Enzo on 1/9/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct PeakApp: App {
    let container: ModelContainer
    private let storeState: PeakDataStore.LoadState

    init() {
        Self.configureTabBarAppearance()
        let isUITest = TestingDefaults.isUITest

        if isUITest {
            let result = PeakDataStore.makeContainer(inMemory: true)
            container = result.container
            storeState = .healthy
            PreviewData.seed(context: container.mainContext, baseDate: TestingDefaults.fixedSeedDate ?? Date())
            if ProcessInfo.processInfo.environment["UITESTS_DISABLE_ANIMATIONS"] == "1" {
                UIView.setAnimationsEnabled(false)
            }
        } else {
            // Reuse the process-wide container so App Intents write to the same store.
            container = PeakDataStore.shared.container
            storeState = PeakDataStore.shared.state
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(storeState: storeState)
                .modelContainer(container)
                .preferredColorScheme(.dark)
        }
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.clear
        appearance.shadowColor = UIColor.clear

        let normalColor = UIColor(white: 0.98, alpha: 0.8)
        let selectedColor = UIColor(white: 0.98, alpha: 1.0)

        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        appearance.inlineLayoutAppearance.normal.iconColor = normalColor
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.inlineLayoutAppearance.selected.iconColor = selectedColor
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        appearance.compactInlineLayoutAppearance.normal.iconColor = normalColor
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.compactInlineLayoutAppearance.selected.iconColor = selectedColor
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
    }
}
