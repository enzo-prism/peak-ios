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
        if isUITest, let recoveryMode = ProcessInfo.processInfo.environment["UITESTS_STORE_RECOVERY"] {
            // Exercise recovery UI/export with a fabricated fixture, never a
            // user's library. The production loader remains entirely bypassed.
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Peak UI Recovery Fixture", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
                try Data("UI test recovery fixture only".utf8).write(to: fixture.appendingPathComponent("README.txt"))
                switch recoveryMode {
                case "fresh": storeOutcome = .recoveredFresh(archivedPath: fixture.path)
                case "temporary": storeOutcome = .inMemoryFallback(recovery: StoreRecoveryIssue(archivedPath: fixture.path, details: "UI test: preserved library"))
                case "preservationFailed": storeOutcome = .inMemoryFallback(recovery: StoreRecoveryIssue(archivedPath: nil, details: "UI test: incomplete preservation"))
                default: storeOutcome = result.outcome
                }
            } catch {
                storeOutcome = .inMemoryFallback(recovery: StoreRecoveryIssue(archivedPath: nil, details: "UI test fixture unavailable"))
            }
        } else {
            storeOutcome = result.outcome
        }
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
            RootView(outcome: storeOutcome, container: container)
                .modelContainer(container)
        }
    }
}

/// Wraps `ContentView` so a one-time informational alert can surface store
/// recovery to the user without modifying `ContentView` itself.
private struct RootView: View {
    let outcome: StoreLoadOutcome
    private let container: ModelContainer
    @State private var libraryContext: ModelContext
    @State private var libraryGeneration = UUID()
    @State private var isImportCompletePresented = false
    @State private var savedSessionWarning: String?

    @AppStorage(WelcomeExperience.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @State private var didEvaluateOutcome = false
    @State private var isRecoveryAlertPresented = false
    @State private var isWelcomePresented = false
    @State private var wantsFirstSession = false
    @State private var recoveryExportURL: URL?
    @State private var isRecoverySharePresented = false
    @State private var isPreparingRecoveryCopy = false
    @State private var isExportErrorPresented = false

    init(outcome: StoreLoadOutcome, container: ModelContainer) {
        self.outcome = outcome
        self.container = container
        _libraryContext = State(initialValue: container.mainContext)
    }

    var body: some View {
        ContentView()
            .id(libraryGeneration)
            .environment(\.modelContext, libraryContext)
            .onReceive(NotificationCenter.default.publisher(for: .peakLibraryDidImport)) { notification in
                if refreshLibrary(after: notification) {
                    isImportCompletePresented = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .peakLibraryDidChange)) { notification in
                if refreshLibrary(after: notification) {
                    savedSessionWarning = notification.userInfo?["message"] as? String
                }
            }
            .alert("Import Complete", isPresented: $isImportCompletePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your backup has been saved. Your updated library is ready.")
            }
            .alert("Session Saved", isPresented: Binding(
                get: { savedSessionWarning != nil },
                set: { if !$0 { savedSessionWarning = nil } }
            )) {
                Button("OK", role: .cancel) { savedSessionWarning = nil }
            } message: {
                Text(savedSessionWarning ?? "")
            }
            .safeAreaInset(edge: .bottom) {
                if outcome != .normal {
                    HStack {
                        Text(recoveryBanner)
                            .font(.footnote)
                        Spacer()
                        Button(isPreparingRecoveryCopy ? "Preparing…" : "Details") {
                            isRecoveryAlertPresented = true
                        }
                        .disabled(isPreparingRecoveryCopy)
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
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
                isWelcomePresented = outcome == .normal && WelcomeExperience.shouldPresent(hasSeenWelcome: hasSeenWelcome)
                if outcome != .normal {
                    isRecoveryAlertPresented = true
                }
            }
            .alert(recoveryTitle, isPresented: $isRecoveryAlertPresented) {
                if archivedPath != nil {
                    Button("Export Recovery Copy", action: prepareRecoveryExport)
                }
                Button("Close", role: .cancel) {}
            } message: {
                Text(recoveryMessage)
            }
            .sheet(isPresented: $isRecoverySharePresented, onDismiss: removeTemporaryExport) {
                if let recoveryExportURL {
                    ShareSheet(items: [recoveryExportURL])
                }
            }
            .alert("Recovery copy could not be exported", isPresented: $isExportErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your recovery files are still on this device. Free up device storage and try again. Do not delete Peak while your library needs recovery.")
            }
    }

    private func refreshLibrary(after notification: Notification) -> Bool {
        guard let changedContainer = notification.object as? ModelContainer,
              changedContainer === container else { return false }
        // Private-context commits must retire old query models and navigation
        // selections together. The shared navigation coordinator keeps the tab.
        let refreshed = ModelContext(container)
        refreshed.autosaveEnabled = true
        libraryContext = refreshed
        PeakIntentStore.register(container, context: refreshed)
        QuickLogCoordinator.shared.showNewSession = false
        libraryGeneration = UUID()
        return true
    }

    private var archivedPath: String? {
        switch outcome {
        case .normal: return nil
        case .recoveredFresh(let path): return path
        case .inMemoryFallback(let issue): return issue.archivedPath
        }
    }

    private var recoveryBanner: String {
        switch outcome {
        case .normal: return ""
        case .recoveredFresh: return "Your previous library needs recovery."
        case .inMemoryFallback: return "Temporary library. Changes will not be saved."
        }
    }

    private func prepareRecoveryExport() {
        guard let archivedPath, !isPreparingRecoveryCopy else { return }
        isPreparingRecoveryCopy = true
        Task {
            do {
                recoveryExportURL = try await Task.detached {
                    try PeakDataStore.recoveryExport(archivedPath: archivedPath)
                }.value
                isRecoverySharePresented = true
            } catch {
                isExportErrorPresented = true
            }
            isPreparingRecoveryCopy = false
        }
    }

    private func removeTemporaryExport() {
        if let recoveryExportURL { try? FileManager.default.removeItem(at: recoveryExportURL) }
        recoveryExportURL = nil
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
            return "Your previous library needs recovery"
        case .inMemoryFallback:
            return "Temporary library in use"
        }
    }

    private var recoveryMessage: String {
        switch outcome {
        case .normal:
            return ""
        case .recoveredFresh:
            return "Peak could not open your previous library. A complete copy of its files was preserved, and your current library is separate from that copy. Export the recovery copy to Files for safekeeping or to share with support. It is a recovery archive, not an importable Peak backup. Do not delete Peak before saving a copy."
        case .inMemoryFallback:
            if archivedPath != nil {
                return "Peak could not open a saved library. Changes in this temporary library will be lost when Peak closes. A complete copy of your previous library is preserved. Export it to Files for safekeeping or to share with support. It is a recovery archive, not an importable Peak backup. Do not delete Peak before saving a copy."
            }
            if case .inMemoryFallback(let issue) = outcome, issue.phase == .copying {
                return "Peak could not finish preserving your library. Your original files have not been removed. Free up device storage, then close and reopen Peak to retry. Changes in this temporary library will be lost when Peak closes. Do not delete Peak."
            }
            return "Peak could not safely prepare your saved library. Changes in this temporary library will be lost when Peak closes. Existing library files have been left on this device. Do not delete Peak. Contact Peak support for help recovering your library."
        }
    }
}
