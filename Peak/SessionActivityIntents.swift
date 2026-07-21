import AppIntents
import Foundation

/// Intents that drive the in-progress session. Both are compiled into the app
/// *and* the widget extension: the Control Center button starts a session
/// without launching Peak, and the Live Activity's End action needs the same
/// vocabulary. Everything here reads the App Group only — no SwiftData — so the
/// extension stays small.
nonisolated struct StartSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Surf Session"
    static let description = IntentDescription(
        "Starts a surf session timer at your most recent spot. End it when you get out and Peak opens the log prefilled."
    )
    /// Runs in place: the point of the Action button and Control Center is to
    /// start the timer without waiting for the app to launch.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Already paddling — don't reset the clock out from under the surfer.
        if let existing = ActiveSessionStore.loadActive() {
            return .result(dialog: IntentDialog(stringLiteral: Self.alreadyRunningDialog(spotName: existing.spotName)))
        }

        let snapshot = PeakWidgetStore.read()
        let state = ActiveSessionState(
            spotKey: snapshot.lastSessionSpotKey,
            spotName: snapshot.lastSessionSpot,
            startDate: Date()
        )
        SessionActivityController.start(state)
        return .result(dialog: IntentDialog(stringLiteral: Self.startedDialog(spotName: state.spotName)))
    }

    static func startedDialog(spotName: String?) -> String {
        guard let spotName, !spotName.isEmpty else { return "Session started." }
        return "Session started at \(spotName)."
    }

    static func alreadyRunningDialog(spotName: String?) -> String {
        guard let spotName, !spotName.isEmpty else { return "A session is already running." }
        return "A session at \(spotName) is already running."
    }
}

/// Ends the running session and brings Peak forward so the surfer can finish
/// the log while it's fresh. Opening the app is the whole point, so this one
/// deliberately doesn't run in place.
nonisolated struct EndSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Surf Session"
    static let description = IntentDescription(
        "Ends the running surf session and opens Peak with the log prefilled."
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SessionActivityController.end()
        return .result()
    }
}
