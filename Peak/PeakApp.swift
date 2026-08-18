//
//  PeakApp.swift
//  Peak
//
//  Created by Enzo on 1/9/26.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct PeakApp: App {
    private let container: ModelContainer
    private let storeOutcome: StoreLoadOutcome

    init() {
        let isUITest = TestingDefaults.isUITest
        // Unit tests host Peak.app; open an in-memory store so the host does not
        // fight test-local ModelContainers (SwiftData dual-store heap corruption
        // has shown up as malloc crashes in unrelated suites on Xcode 26 CI).
        let useEphemeralStore = isUITest || TestingDefaults.isRunningTests
        let result = PeakDataStore.load(isUITest: useEphemeralStore)
        container = result.container
        storeOutcome = result.outcome
        // App Intents (Siri, Spotlight, Action button) read the logbook through
        // this container rather than opening a second one.
        PeakIntentStore.register(container)
        PeakTips.configure()

        if !isUITest {
            UNUserNotificationCenter.current().delegate = PeakNotificationDelegate.shared
        }

        if isUITest {
            // A UI-test run must never inherit an in-progress or ended-but-
            // unlogged session from an earlier run — the App Group defaults
            // outlive the in-memory store.
            ActiveSessionStore.reset()
            PreviewData.seed(context: container.mainContext, baseDate: TestingDefaults.fixedSeedDate ?? Date())
            if ProcessInfo.processInfo.environment["UITESTS_DISABLE_ANIMATIONS"] == "1" {
                UIView.setAnimationsEnabled(false)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(outcome: storeOutcome)
                .modelContainer(container)
        }
    }
}

/// Wraps `ContentView` so a one-time informational alert can surface store
/// recovery to the user without modifying `ContentView` itself.
private struct RootView: View {
    let outcome: StoreLoadOutcome

    @AppStorage(WelcomeExperience.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @State private var didEvaluateOutcome = false
    @State private var isRecoveryAlertPresented = false
    @State private var isWelcomePresented = false
    @State private var wantsFirstSession = false

    var body: some View {
        ContentView()
            // The editor request waits for `onDismiss`: asking for a sheet in the
            // same turn the cover starts dismissing loses the presentation.
            .fullScreenCover(isPresented: $isWelcomePresented, onDismiss: openEditorIfRequested) {
                WelcomeView(
                    onLogFirstSession: {
                        wantsFirstSession = true
                        finishWelcome()
                    },
                    onFinish: finishWelcome
                )
            }
            .onAppear {
                guard !didEvaluateOutcome else { return }
                didEvaluateOutcome = true
                isWelcomePresented = WelcomeExperience.shouldPresent(hasSeenWelcome: hasSeenWelcome)
                if outcome != .normal {
                    isRecoveryAlertPresented = true
                }
            }
            .alert(recoveryTitle, isPresented: $isRecoveryAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recoveryMessage)
            }
    }

    private func finishWelcome() {
        hasSeenWelcome = true
        isWelcomePresented = false
    }

    private func openEditorIfRequested() {
        guard wantsFirstSession else { return }
        wantsFirstSession = false
        QuickLogCoordinator.shared.requestNewSession()
    }

    private var recoveryTitle: String {
        switch outcome {
        case .normal:
            return ""
        case .recoveredFresh:
            return "Peak recovered your library"
        case .inMemoryFallback:
            return "Temporary library in use"
        }
    }

    private var recoveryMessage: String {
        switch outcome {
        case .normal:
            return ""
        case .recoveredFresh:
            return "Your data couldn't be opened, so a fresh library was created. The old files were preserved on your device in case they can be recovered."
        case .inMemoryFallback:
            return "Your data couldn't be opened and a temporary library is in use. Changes may not be saved — please restart Peak."
        }
    }
}
