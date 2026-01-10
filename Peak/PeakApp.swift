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

    init() {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self])
        let isUITest = ProcessInfo.processInfo.environment["UITESTS"] == "1"
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITest)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize data store: \\(error)")
        }
        if isUITest {
            PreviewData.seed(context: container.mainContext)
            if ProcessInfo.processInfo.environment["UITESTS_DISABLE_ANIMATIONS"] == "1" {
                UIView.setAnimationsEnabled(false)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
