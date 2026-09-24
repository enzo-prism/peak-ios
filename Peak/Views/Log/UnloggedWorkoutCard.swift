import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Log-tab card for the most recent Apple Watch surf that Peak has not logged.
/// Hidden unless Health sync is on, and never talks to HealthKit under UI tests.
struct UnloggedWorkoutCard: View {
    let sessions: [SurfSession]

    @Query(sort: \Spot.name) private var spots: [Spot]
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false

    @State private var workout: HealthKitLogic.WorkoutSummary?
    @State private var isLogging = false
    @State private var refreshTask: Task<Void, Never>?

    private var isVisible: Bool {
        healthSyncEnabled && !TestingDefaults.isUITest
    }

    var body: some View {
        Group {
            if isVisible, let workout {
                GlassContainer(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "applewatch")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityHidden(true)
                            Text("Watch surf ready to log")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                        }

                        Text(workout.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        HStack(spacing: 6) {
                            Label(
                                SessionDurationFormatter.string(from: draft(for: workout).durationMinutes),
                                systemImage: "timer"
                            )
                            Text("·")
                            Label(workout.sourceName, systemImage: "applewatch")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                        Button {
                            Task { await log(workout) }
                        } label: {
                            HStack(spacing: 8) {
                                // Reading the route and estimating waves can take
                                // a beat on a long session; show that it's working.
                                if isLogging {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                }
                                Text("Log this surf")
                            }
                            .font(.headline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .glassButtonStyle(prominent: true)
                        .disabled(isLogging)
                        .accessibilityIdentifier("log.unloggedWorkout.log")
                    }
                    .padding(Theme.Spacing.l)
                    .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint, isInteractive: false)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("log.unloggedWorkout")
            }
        }
        .onAppear { refresh() }
        .onChange(of: sessions) { _, _ in refresh() }
        .onChange(of: healthSyncEnabled) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .peakUnloggedWorkoutsMayHaveChanged)) { _ in
            refresh()
        }
    }

    private func draft(for workout: HealthKitLogic.WorkoutSummary) -> HealthKitLogic.SessionDraftValues {
        HealthKitLogic.draftValues(workoutStart: workout.start, workoutEnd: workout.end)
    }

    private func refresh() {
        guard isVisible else {
            workout = nil
            return
        }
        refreshTask?.cancel()
        refreshTask = Task {
            await load()
        }
    }

    private func load() async {
        guard isVisible else { return }
        do {
            let workouts = try await HealthKitService.shared.fetchUnloggedSurfWorkouts(
                existingSessions: sessions,
                since: HealthKitLogic.recentUnloggedWindowStart()
            )
            guard !Task.isCancelled else { return }
            let latest = workouts.first
            workout = latest
            if let latest {
                await UnloggedSurfNotification.postIfNeeded(
                    workout: latest,
                    spots: spots
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            workout = nil
        }
    }

    /// Opens the editor on the Watch surf — times, nearest spot and estimated
    /// wave stats filled in, gear from history — so logging it is a rating and
    /// Save rather than a blank "Unknown spot" row to fix later. The card stays
    /// until the session is actually saved (its window then overlaps).
    private func log(_ workout: HealthKitLogic.WorkoutSummary) async {
        guard !isLogging else { return }
        isLogging = true
        defer { isLogging = false }

        let samples = await HealthKitService.shared.routeSamples(forWorkoutID: workout.id)
        let stats = await UnloggedSurfImporter.stats(from: samples)
        let draft = UnloggedSurfImporter.makeDraft(workout: workout, samples: samples, stats: stats, spots: spots)
        QuickLogCoordinator.shared.requestLog(prefill: draft)
    }
}

/// Local notification for an unlogged Watch surf. Category is registered when
/// the Settings toggle turns on (and again just before posting, so a toggle
/// that was already on across launches still has the Log action).
enum UnloggedSurfNotification {
    static let categoryIdentifier = "PEAK_UNLOGGED_SURF"
    static let logActionIdentifier = "LOG"
    static let workoutIDUserInfoKey = "workoutID"
    static let lastNotifiedWorkoutIDKey = "peak.lastNotifiedUnloggedWorkoutID"

    static func registerCategory() {
        let log = UNNotificationAction(
            identifier: logActionIdentifier,
            title: "Log",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [log],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        registerCategory()
    }

    /// Observer wake: refresh the Log card, then post a local notification if
    /// the surfer opted in and Peak is not in the foreground. Must finish before
    /// `HKObserverQuery`'s completion handler runs.
    @MainActor
    static func handleObserverWake() async {
        NotificationCenter.default.post(name: .peakUnloggedWorkoutsMayHaveChanged, object: nil)
        await deliverIfNeeded()
    }

    /// Used when the surfer backgrounds Peak with an unlogged Watch surf already
    /// sitting there — the observer may not fire again.
    @MainActor
    static func considerPosting(sessions: [SurfSession], spots: [Spot]) async {
        await deliverIfNeeded(sessions: sessions, spots: spots)
    }

    @MainActor
    static func postIfNeeded(
        workout: HealthKitLogic.WorkoutSummary,
        spots: [Spot]
    ) async {
        guard shouldPost() else { return }
        let id = workout.id.uuidString
        guard UserDefaults.standard.string(forKey: lastNotifiedWorkoutIDKey) != id else { return }
        UserDefaults.standard.set(id, forKey: lastNotifiedWorkoutIDKey)

        var spotName: String?
        if spots.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
            let samples = await HealthKitService.shared.routeSamples(forWorkoutID: workout.id)
            spotName = SpotProximity.nearest(to: samples, in: spots)?.name
        }
        post(workout: workout, spotName: spotName)
    }

    @MainActor
    private static func deliverIfNeeded(
        sessions: [SurfSession]? = nil,
        spots: [Spot]? = nil
    ) async {
        guard shouldPost() else { return }
        let sessions = sessions ?? PeakIntentStore.sessions()
        let spots = spots ?? PeakIntentStore.spots()
        let workouts: [HealthKitLogic.WorkoutSummary]
        do {
            workouts = try await HealthKitService.shared.fetchUnloggedSurfWorkouts(
                existingSessions: sessions,
                since: HealthKitLogic.recentUnloggedWindowStart()
            )
        } catch {
            return
        }
        guard let workout = workouts.first else { return }
        await postIfNeeded(workout: workout, spots: spots)
    }

    private static func shouldPost() -> Bool {
        guard UserDefaults.standard.bool(forKey: HealthKitService.notifyUnloggedWorkoutsKey),
              UserDefaults.standard.bool(forKey: HealthKitService.healthSyncEnabledKey),
              !TestingDefaults.isUITest else { return false }
        return UIApplication.shared.applicationState != .active
    }

    static func post(workout: HealthKitLogic.WorkoutSummary, spotName: String?) {
        guard !TestingDefaults.isUITest else { return }
        registerCategory()

        let content = UNMutableNotificationContent()
        content.title = spotName?.trimmedNonEmpty ?? "Surf ready to log"
        let duration = SessionDurationFormatter.string(
            from: HealthKitLogic.draftValues(workoutStart: workout.start, workoutEnd: workout.end).durationMinutes
        )
        content.body = "\(duration) · \(workout.sourceName)"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [workoutIDUserInfoKey: workout.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "unlogged-\(workout.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Turns an unlogged Watch workout into an editor draft. Shared by the Log-tab
/// card and the notification Log action. (Settings → Import from Health is an
/// explicit bulk import and builds sessions directly via `HealthKitLogic`.)
enum UnloggedSurfImporter {
    static func stats(from samples: [RouteSample]) async -> WaveStats? {
        guard samples.count >= WaveAnalyzer.Tuning().minWaveSampleCount else { return nil }
        return await WaveAnalyzer.analyzeOffMain(samples: samples)
    }

    /// The editor draft for a Watch surf: the workout's own start and length
    /// (never anchored to "now"), the nearest pinned spot, and route-derived wave
    /// stats marked `auto`. The workout link means saving never writes a second
    /// workout back to Health.
    static func makeDraft(
        workout: HealthKitLogic.WorkoutSummary,
        samples: [RouteSample],
        stats: WaveStats?,
        spots: [Spot]
    ) -> SessionDraft {
        let values = HealthKitLogic.draftValues(workoutStart: workout.start, workoutEnd: workout.end)
        var draft = SessionDraft()
        draft.date = values.date
        draft.durationMinutes = values.durationMinutes ?? 0
        if let spot = SpotProximity.nearest(to: samples, in: spots) {
            draft.selectSpot(spot)
        }
        if let stats {
            draft.applyDerivedWaveStats(stats, workoutID: workout.id.uuidString)
        } else {
            draft.linkedWorkoutID = workout.id.uuidString
        }
        return draft
    }

    /// The notification's Log action: open the editor on that workout, if it
    /// is still unlogged. Same review-then-save path as the Log-tab card.
    @MainActor
    static func openEditorIfUnlogged(workoutID: String) async {
        guard !TestingDefaults.isUITest,
              let uuid = UUID(uuidString: workoutID),
              PeakIntentStore.container != nil else { return }

        let sessions = PeakIntentStore.sessions()
        let spots = PeakIntentStore.spots()
        guard let summary = await HealthKitService.shared.fetchSurfWorkoutSummary(id: uuid) else { return }
        let windows = sessions.map {
            HealthKitLogic.sessionWindow(date: $0.date, durationMinutes: $0.durationMinutes)
        }
        let stillUnlogged = HealthKitLogic.unloggedWorkouts(from: [summary], sessionWindows: windows)
        guard stillUnlogged.contains(where: { $0.id == uuid }) else { return }

        let samples = await HealthKitService.shared.routeSamples(forWorkoutID: uuid)
        let stats = await stats(from: samples)
        let draft = makeDraft(workout: summary, samples: samples, stats: stats, spots: spots)
        QuickLogCoordinator.shared.requestLog(prefill: draft)
    }
}

/// Tapping Log opens the editor on that workout; tapping the banner opens the Log tab.
/// Banners are suppressed while Peak is foregrounded — the card is the in-app surface.
final class PeakNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PeakNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        guard category == UnloggedSurfNotification.categoryIdentifier else { return }
        let workoutID = response.notification.request.content.userInfo[UnloggedSurfNotification.workoutIDUserInfoKey] as? String
        if response.actionIdentifier == UnloggedSurfNotification.logActionIdentifier,
           let workoutID {
            await UnloggedSurfImporter.openEditorIfUnlogged(workoutID: workoutID)
        }
        await MainActor.run {
            PeakNavigationCoordinator.shared.selectedTab = .log
        }
    }
}
