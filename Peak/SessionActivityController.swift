import ActivityKit
import Foundation
import WidgetKit

/// Starts and stops the "session in progress" Live Activity, and keeps the
/// App-Group state that backs it in step.
///
/// Every ActivityKit call is gated behind `TestingDefaults.isUITest`: the
/// simulator has no Lock Screen or Dynamic Island for the UI suite to drive, so
/// under test the state moves exactly as it does in production while the
/// activity chrome is simply never requested. Shared with the widget extension
/// (the Control Center button starts sessions in-process), hence `nonisolated`
/// throughout — the two targets don't share a default actor isolation setting.
nonisolated enum SessionActivityController {
    /// Starts a session at `state` and, when the platform allows it, raises the
    /// matching Live Activity. Replaces any session already in progress.
    static func start(_ state: ActiveSessionState, defaults: UserDefaults = ActiveSessionStore.sharedDefaults) {
        ActiveSessionStore.saveActive(state, to: defaults)
        requestActivity(for: state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ends the in-progress session, parks it as a pending log for the editor,
    /// and dismisses the Live Activity. Returns the ended session, or nil when
    /// nothing was running.
    @discardableResult
    static func end(
        at endDate: Date = Date(),
        defaults: UserDefaults = ActiveSessionStore.sharedDefaults
    ) -> EndedSessionRecord? {
        let record = ActiveSessionStore.endActive(at: endDate, in: defaults)
        dismissActivities()
        WidgetCenter.shared.reloadAllTimelines()
        return record
    }

    /// Abandons the in-progress session without queuing it for logging.
    static func discard(defaults: UserDefaults = ActiveSessionStore.sharedDefaults) {
        ActiveSessionStore.clearActive(in: defaults)
        dismissActivities()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - ActivityKit

    private static var isActivityKitAvailable: Bool {
        !TestingDefaults.isUITest && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private static func requestActivity(for state: ActiveSessionState) {
        guard isActivityKitAvailable else { return }
        dismissActivities()

        let attributes = PeakSessionActivityAttributes(spotName: state.spotName)
        let content = ActivityContent(
            state: PeakSessionActivityAttributes.ContentState(startDate: state.startDate),
            staleDate: nil
        )
        // A rejected request (activities disabled mid-flight, budget exhausted)
        // must not break starting a session — the App-Group state is the source
        // of truth and the in-app hero still shows the timer.
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    private static func dismissActivities() {
        guard !TestingDefaults.isUITest else { return }
        for activity in Activity<PeakSessionActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
