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
    /// Set when a just-ended session should open the editor prefilled. Consumed
    /// by `ContentView` when it builds the sheet.
    var pendingLog: EndedSessionRecord?

    func requestNewSession() {
        pendingLog = nil
        showNewSession = true
    }

    /// Opens the editor prefilled from a session the surfer just ended.
    func requestLog(for record: EndedSessionRecord) {
        pendingLog = record
        showNewSession = true
    }

    /// Picks up a session ended outside the app — via the Live Activity's End
    /// button or an End Session shortcut — the next time Peak is frontmost.
    func drainPendingLogFromStore() {
        guard !showNewSession, let record = ActiveSessionStore.takePendingLog() else { return }
        requestLog(for: record)
    }
}

struct LogSessionIntent: AppIntent {
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
