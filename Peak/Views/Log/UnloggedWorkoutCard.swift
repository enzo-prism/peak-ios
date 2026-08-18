import SwiftData
import SwiftUI
import UserNotifications

/// Log-tab card for the most recent Apple Watch surf that Peak has not logged.
/// Hidden unless Health sync is on, and never talks to HealthKit under UI tests.
struct UnloggedWorkoutCard: View {
    let sessions: [SurfSession]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Spot.name) private var spots: [Spot]
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false

    @State private var workout: HealthKitLogic.WorkoutSummary?
    @State private var isLogging = false
    @State private var logFeedback = 0
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
                            Label("Log this surf", systemImage: "plus")
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
                .sensoryFeedback(.success, trigger: logFeedback)
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
                existingSessions: sessions
            )
            guard !Task.isCancelled else { return }
            let latest = workouts.first
            workout = latest
            if let latest {
                await UnloggedSurfNotification.postIfNeeded(
                    workout: latest,
                    spots: spots,
                    scenePhase: scenePhase
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            workout = nil
        }
    }

    private func log(_ workout: HealthKitLogic.WorkoutSummary) async {
        guard !isLogging else { return }
        isLogging = true
        defer { isLogging = false }

        let samples = await HealthKitService.shared.routeSamples(forWorkoutID: workout.id)
        let stats = await WaveStatsDeriver.stats(
            forWorkoutID: workout.id,
            provider: HealthKitService.shared
        )
        let spot = SpotProximity.nearest(to: samples.first, in: spots)
        let session = HealthKitLogic.importedSession(workout: workout, stats: stats, spot: spot)
        modelContext.insert(session)
        logFeedback += 1
        self.workout = nil
    }
}

/// Local notification for an unlogged Watch surf. Category is registered when
/// the Settings toggle turns on (and again just before posting, so a toggle
/// that was already on across launches still has the Log action).
enum UnloggedSurfNotification {
    static let categoryIdentifier = "PEAK_UNLOGGED_SURF"
    static let logActionIdentifier = "LOG"
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

    /// Used when HealthKit wakes Peak in the background — the Log-tab card may
    /// not be on screen yet, so ContentView calls this after the observer fires.
    @MainActor
    static func considerPosting(
        sessions: [SurfSession],
        spots: [Spot],
        scenePhase: ScenePhase
    ) async {
        guard shouldPost(scenePhase: scenePhase) else { return }
        let workouts: [HealthKitLogic.WorkoutSummary]
        do {
            workouts = try await HealthKitService.shared.fetchUnloggedSurfWorkouts(
                existingSessions: sessions
            )
        } catch {
            return
        }
        guard let workout = workouts.first else { return }
        await postIfNeeded(workout: workout, spots: spots, scenePhase: scenePhase)
    }

    @MainActor
    static func postIfNeeded(
        workout: HealthKitLogic.WorkoutSummary,
        spots: [Spot],
        scenePhase: ScenePhase
    ) async {
        guard shouldPost(scenePhase: scenePhase) else { return }
        let id = workout.id.uuidString
        guard UserDefaults.standard.string(forKey: lastNotifiedWorkoutIDKey) != id else { return }
        UserDefaults.standard.set(id, forKey: lastNotifiedWorkoutIDKey)

        var spotName: String?
        if spots.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
            let samples = await HealthKitService.shared.routeSamples(forWorkoutID: workout.id)
            spotName = SpotProximity.nearest(to: samples.first, in: spots)?.name
        }
        post(workout: workout, spotName: spotName)
    }

    private static func shouldPost(scenePhase: ScenePhase) -> Bool {
        UserDefaults.standard.bool(forKey: HealthKitService.notifyUnloggedWorkoutsKey)
            && UserDefaults.standard.bool(forKey: HealthKitService.healthSyncEnabledKey)
            && scenePhase == .background
            && !TestingDefaults.isUITest
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

        let request = UNNotificationRequest(
            identifier: "unlogged-\(workout.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Tapping the notification (or its Log action) opens Peak on the Log tab,
/// where the unlogged-workout card is the in-app surface. Banners are suppressed
/// while Peak is foregrounded — the card is already visible then.
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
        await MainActor.run {
            PeakNavigationCoordinator.shared.selectedTab = .log
        }
    }
}
