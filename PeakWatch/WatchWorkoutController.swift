import Foundation
import HealthKit

/// Drives one surf workout on the watch: the `HKWorkoutSession` that owns the
/// lifecycle, the `HKLiveWorkoutBuilder` that collects samples, and the
/// published values the UI renders.
///
/// Design rules that the rest of this file follows from:
///
/// 1. **The HealthKit save is the source of truth.** Everything else — the
///    mirrored Live Activity, the WatchConnectivity handoff — is a nicety. If
///    all of it fails, the surfer still ends up with a normal surf workout in
///    Health, which is exactly what Peak's existing iPhone import path already
///    knows how to mine for wave stats. That is why `end()` finishes the
///    workout *first* and only then attempts the handoff.
/// 2. **No on-watch wave detection.** The watch produces a workout with a GPS
///    route; `WaveAnalyzer` on the phone does the analysis. Duplicating it here
///    would mean two tunings to keep in step against the same ocean.
/// 3. **Water Lock is not fought.** `.surfingSports` + `.outdoor` makes watchOS
///    engage Water Lock automatically, which blanks the touch screen. Every
///    control below therefore has to be reachable *before* the surfer paddles
///    out or *after* they twist the crown to unlock — there is no clever way
///    around it, and trying would break the waterproofing contract.
@MainActor
final class WatchWorkoutController: NSObject, ObservableObject {
    static let shared = WatchWorkoutController()
    /// Lifecycle + elapsed-time accounting. Pure value type, unit-tested
    /// separately; this class only ever feeds it events.
    @Published private(set) var timeline = SurfWorkoutTimeline()
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeEnergyKilocalories: Double?
    @Published private(set) var distanceMeters: Double?
    /// Set when a start fails in a way the surfer can act on (denied
    /// permissions, Health unavailable). Deliberately not set for mirroring or
    /// handoff failures — those are invisible by design.
    @Published private(set) var startupError: String?
    /// True once the mirrored session is live on the phone. Surfaced only as a
    /// tiny glyph: it is informational, never something to block on.
    @Published private(set) var isMirroring = false
    @Published private(set) var isStarting = false
    @Published private(set) var saveStatus: WatchSaveStatus = .idle
    private var collectionEnded = false
    private var didTryRecovery = false
    private var isRecovering = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let relay = WatchConnectivityRelay()
    /// Builds the GPS route that the phone's `WaveAnalyzer` mines. Without it
    /// the saved workout has no locations and there are no wave stats at all.
    private let routeRecorder = WatchRouteRecorder()

    var state: SurfWorkoutState { timeline.state }

    // MARK: - Authorization

    /// Types the watch needs. Kept in step with the iPhone's read set so a
    /// surfer who granted access on one device is not re-prompted on the other
    /// for the same data.
    private static var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceSwimming)
        ]
    }

    private static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceSwimming)
        ]
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            startupError = "Apple Health is not available on this watch."
            return
        }
        // Location is asked for alongside Health: without it there is no route,
        // and without a route the session produces no wave stats.
        routeRecorder.requestAuthorization()
        do {
            try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        } catch {
            // A refusal is a legitimate answer, not a crash. The surfer sees the
            // real failure when they try to start and the session is rejected.
            startupError = nil
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard timeline.state == .idle, !isStarting, !isRecovering else { return }
        isStarting = true
        defer { isStarting = false }
        await requestAuthorization()
        guard !Task.isCancelled else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            startupError = "Apple Health is not available on this watch."
            return
        }

        let configuration = HKWorkoutConfiguration()
        // `.surfingSports` is what the phone's importer already filters on, and
        // what makes watchOS treat this as a water activity (Water Lock, wrist
        // -clear GPS sampling). Changing either value breaks the phone-side
        // import silently, so they are not knobs.
        configuration.activityType = .surfingSports
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            collectionEnded = false
            saveStatus = .idle
            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            routeRecorder.start(healthStore: healthStore)

            timeline.apply(.start, at: startDate)
            startupError = nil

            await startMirroring(session)
        } catch {
            startupError = "Couldn't start the workout. Check Peak's access in Health."
            session?.end()
            builder?.discardWorkout()
            _ = await routeRecorder.finish(attachingTo: nil)
            teardown()
        }
    }

    func pause() {
        guard timeline.state == .running else { return }
        session?.pause()
        routeRecorder.pause()
        timeline.apply(.pause, at: Date())
    }

    func resume() {
        guard timeline.state == .paused else { return }
        session?.resume()
        routeRecorder.resume()
        timeline.apply(.resume, at: Date())
    }

    /// Ends the session, saves the workout, then hands off to the phone.
    ///
    /// Ordering is load-bearing: the save happens before any handoff attempt, so
    /// a WatchConnectivity failure (phone off, out of range, app never
    /// installed) cannot cost the surfer the session.
    func end() async {
        guard saveStatus != .saving, timeline.isActive || saveStatus == .failed else { return }
        guard let session, let builder else {
            saveStatus = .failed
            startupError = "The workout could not be saved. You can still log its timing manually in Peak."
            return
        }
        if timeline.isActive {
            timeline.apply(.end, at: Date())
            session.end()
        }
        let endDate = timeline.endedAt ?? Date()
        saveStatus = .saving
        routeRecorder.pause()
        do {
            if !collectionEnded {
                try await builder.endCollection(at: endDate)
                collectionEnded = true
            }
            guard let workout = try await builder.finishWorkout() else { throw CocoaError(.fileWriteUnknown) }
            let routeSaved = await routeRecorder.finish(attachingTo: workout)
            saveStatus = routeSaved ? .saved : .savedWithoutRoute
            await stopMirroring(session)
            sendHandoff(endDate: endDate, workout: workout)
            startupError = nil
            teardown()
        } catch {
            // Keep the builder and route builder alive so a transient failure is
            // retryable. Never turn a failed Health save into a success screen.
            saveStatus = .failed
            startupError = "Health could not save this workout. Try again, or keep the timing for a manual log."
        }
    }

    func recoverIfNeeded(force: Bool = false) async {
        guard (!didTryRecovery || force), !isStarting, !isRecovering,
              timeline.state == .idle, HKHealthStore.isHealthDataAvailable() else { return }
        didTryRecovery = true
        isRecovering = true
        defer { isRecovering = false }
        do {
            let recovered: HKWorkoutSession? = try await withCheckedThrowingContinuation { continuation in
                healthStore.recoverActiveWorkoutSession { session, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: session) }
                }
            }
            guard let recovered, let start = recovered.startDate,
                  recovered.state == .running || recovered.state == .paused else { return }
            let builder = recovered.associatedWorkoutBuilder()
            self.session = recovered
            self.builder = builder
            recovered.delegate = self
            builder.delegate = self
            let now = Date()
            timeline = SurfWorkoutTimeline(recoveringStartDate: start, elapsed: builder.elapsedTime(at: now),
                                           paused: recovered.state == .paused, at: now)
            routeRecorder.start(healthStore: healthStore)
            if recovered.state == .paused { routeRecorder.pause() }
            await startMirroring(recovered)
        } catch {
            startupError = "Workout recovery is unavailable. Check the Workout app before starting another surf."
        }
    }

    /// Clears state so the watch is ready for the next paddle-out.
    func reset() {
        guard saveStatus != .saving else { return }
        if saveStatus == .failed { builder?.discardWorkout() }
        session?.end()
        routeRecorder.discard()
        teardown()
        saveStatus = .idle
        collectionEnded = false
        timeline = SurfWorkoutTimeline()
        heartRate = nil
        activeEnergyKilocalories = nil
        distanceMeters = nil
        isMirroring = false
    }

    private func teardown() {
        session?.delegate = nil
        builder?.delegate = nil
        session = nil
        builder = nil
    }

    // MARK: - Mirroring

    /// Hands the live session to the iPhone, where it drives the 2.7 Live
    /// Activity.
    ///
    /// Failures are swallowed on purpose. Mirroring is a display convenience;
    /// the surfer is in the water and cannot fix a phone that is in a car boot.
    /// The queued handoff in `end()` is a fallback when mirroring is unavailable.
    /// The saved HealthKit workout remains independent of either channel.
    private func startMirroring(_ session: HKWorkoutSession) async {
        do {
            try await session.startMirroringToCompanionDevice()
            isMirroring = true
        } catch {
            isMirroring = false
        }
    }

    private func stopMirroring(_ session: HKWorkoutSession) async {
        try? await session.stopMirroringToCompanionDevice()
        isMirroring = false
    }

    // MARK: - Handoff

    private func sendHandoff(endDate: Date, workout: HKWorkout?) {
        let handoff = SurfSessionHandoff(
            startDate: timeline.startedAt ?? endDate,
            endDate: endDate,
            activeDuration: timeline.elapsed(at: endDate),
            workoutUUID: workout?.uuid,
            totalDistanceMeters: distanceMeters,
            averageHeartRate: nil,
            routeStartLatitude: nil,
            routeStartLongitude: nil
        )
        relay.send(handoff)
    }

    // MARK: - Live statistics

    /// Pulls the newest value for each type the UI shows.
    ///
    /// Called from the builder delegate, which fires on a background queue, so
    /// every mutation here is already back on the main actor via the hop in the
    /// delegate method.
    fileprivate func updateStatistics(for types: Set<HKQuantityType>) {
        guard let builder else { return }

        for type in types {
            guard let statistics = builder.statistics(for: type) else { continue }
            switch type {
            case HKQuantityType(.heartRate):
                let bpm = HKUnit.count().unitDivided(by: .minute())
                heartRate = statistics.mostRecentQuantity()?.doubleValue(for: bpm)
            case HKQuantityType(.activeEnergyBurned):
                activeEnergyKilocalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityType(.distanceSwimming):
                distanceMeters = statistics.sumQuantity()?.doubleValue(for: .meter())
            default:
                continue
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutController: HKWorkoutSessionDelegate {
    /// watchOS can move the session on its own — most notably an autopause when
    /// the surfer sits on the shoulder for a while. Reflecting the real state
    /// back into the timeline keeps the elapsed clock honest instead of counting
    /// beach time as surf time.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            switch toState {
            case .paused:
                self.routeRecorder.pause()
                self.timeline.apply(.pause, at: date)
            case .running:
                self.routeRecorder.resume()
                self.timeline.apply(.resume, at: date)
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.startupError = "The workout stopped unexpectedly. Its timing is still available."
            if self.timeline.isActive { self.timeline.apply(.end, at: Date()) }
            self.routeRecorder.pause()
            self.saveStatus = .failed
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let quantityTypes = Set(collectedTypes.compactMap { $0 as? HKQuantityType })
        guard !quantityTypes.isEmpty else { return }
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.updateStatistics(for: quantityTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events (pause/resume/lap markers) are recorded into the workout by
        // HealthKit itself; nothing in the UI depends on them.
    }
}
