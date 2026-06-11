import AppIntents
import Observation
import SwiftUI

/// Bridges App Intents into the SwiftUI shell: the intent flips an observable
/// flag and `ContentView` presents the new-session editor above whatever tab
/// is active.
@MainActor
@Observable
final class QuickLogCoordinator {
    static let shared = QuickLogCoordinator()

    var showNewSession = false

    func requestNewSession() {
        showNewSession = true
    }
}

nonisolated struct LogSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Surf Session"
    static let description = IntentDescription(
        "Opens Peak ready to log a new surf session with your quick-start defaults."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickLogCoordinator.shared.requestNewSession()
        return .result()
    }
}

nonisolated struct PeakAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSessionIntent(),
            phrases: [
                "Log a session in \(.applicationName)",
                "Log a surf session in \(.applicationName)",
                "Start a new \(.applicationName) session"
            ],
            shortTitle: "Log Session",
            systemImageName: "plus.circle"
        )
    }
}
