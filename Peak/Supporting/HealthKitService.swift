import CoreLocation
import Foundation
import HealthKit
import SwiftData
import UIKit

/// FIFO per session, including fire-and-forget hooks. Enqueue synchronously so
/// a later delete cannot be overtaken by an earlier save task starting late.
@MainActor
final class HealthWorkoutQueue {
    private var pending: [String: (id: UUID, task: Task<Void, Error>)] = [:]

    func enqueue(key: String, operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let previous = pending[key]?.task
        let id = UUID()
        let task = Task { @MainActor in
            _ = try? await previous?.value
            defer {
                if self.pending[key]?.id == id { self.pending[key] = nil }
            }
            try await operation()
        }
        pending[key] = (id, task)
        return task
    }
}

// MARK: - Pure logic (unit-testable without HKHealthStore)

/// HealthKit-free logic for the Apple Health integration: stable session keys,
/// session time windows, workout/session overlap matching, and workout->draft
/// mapping. Kept free of HealthKit types so it is unit-testable without
/// entitlements or an HKHealthStore.
enum HealthKitLogic {
    static func shouldWriteWorkout(linkedWorkoutID: String?) -> Bool {
        linkedWorkoutID?.trimmedNonEmpty == nil
    }

    /// Snapshot old objects before creating the replacement. A failed create
    /// never removes old data; deletion only sees captured old objects.
    static func replacePreservingOld<Value>(
        capture: () async throws -> [Value],
        create: () async throws -> UUID,
        identifier: (Value) -> UUID,
        delete: ([Value]) async throws -> Void
    ) async throws {
        let old = try await capture()
        let replacementID = try await create()
        let obsolete = old.filter { identifier($0) != replacementID }
        if !obsolete.isEmpty { try await delete(obsolete) }
    }

    /// Metadata key written on every workout Peak saves, so our own workouts can
    /// be found again (update/delete) and excluded from import suggestions.
    static let sessionKeyMetadataKey = "com.designprism.peak.sessionKey"

    /// Window length assumed for sessions without a logged duration. Used only
    /// for read-side heuristics (stats window + overlap matching), never to
    /// fabricate a workout duration.
    static let assumedDurationMinutes = 60

    /// New writes use persistent session identity, independent of timestamps.
    static func sessionKey(forSessionID id: UUID) -> String {
        "peak-session-\(id.uuidString.lowercased())"
    }

    struct LegacyWorkoutMatch: Equatable {
        let key: String
        let interval: DateInterval

        func matches(start: Date, end: Date) -> Bool {
            interval.start == start && interval.end == end
        }
    }

    /// A legacy key is safe only when the local store proves a single owner.
    /// Unknown duration cannot establish an exact legacy workout interval.
    static func legacyWorkoutMatch(
        createdAt: Date, date: Date, durationMinutes: Int?, matchingSessionCount: Int
    ) -> LegacyWorkoutMatch? {
        guard matchingSessionCount == 1, let durationMinutes, durationMinutes > 0 else { return nil }
        return LegacyWorkoutMatch(
            key: sessionKey(forSessionCreatedAt: createdAt),
            interval: sessionWindow(date: date, durationMinutes: durationMinutes)
        )
    }

    /// Legacy metadata format retained only for safe backward-compatible lookup.
    static func sessionKey(forSessionCreatedAt createdAt: Date) -> String {
        "peak-\(Int64((createdAt.timeIntervalSince1970 * 1000).rounded()))"
    }

    /// The session's time window. Falls back to `assumedDurationMinutes` when
    /// no duration was logged.
    static func sessionWindow(date: Date, durationMinutes: Int?) -> DateInterval {
        let minutes = max(1, durationMinutes ?? assumedDurationMinutes)
        return DateInterval(start: date, duration: TimeInterval(minutes) * 60)
    }

    /// Strict interval overlap: shared boundary instants do not count.
    static func overlaps(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        lhs.start < rhs.end && lhs.end > rhs.start
    }

    static func overlapsAny(_ interval: DateInterval, of windows: [DateInterval]) -> Bool {
        windows.contains { overlaps(interval, $0) }
    }

    /// Plain-value snapshot of an HKWorkout, so filtering and views never touch
    /// HealthKit types.
    struct WorkoutSummary: Identifiable, Equatable {
        let id: UUID
        let start: Date
        let end: Date
        let sourceName: String
        let isFromPeak: Bool

        var interval: DateInterval {
            DateInterval(start: start, end: max(start, end))
        }

        var durationMinutes: Int {
            max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
        }
    }

    /// Workouts worth offering for import: not written by Peak, and not
    /// overlapping any already-logged session window.
    static func unloggedWorkouts(
        from workouts: [WorkoutSummary],
        sessionWindows: [DateInterval]
    ) -> [WorkoutSummary] {
        workouts.filter { workout in
            !workout.isFromPeak && !overlapsAny(workout.interval, of: sessionWindows)
        }
    }

    /// Values a new SurfSession should take when created from a workout.
    struct SessionDraftValues: Equatable {
        let date: Date
        let durationMinutes: Int?
    }

    /// Maps a workout's span onto app rules: session date = workout start,
    /// duration snapped/clamped by `SurfSession.normalizedDuration`.
    static func draftValues(workoutStart: Date, workoutEnd: Date) -> SessionDraftValues {
        let rawMinutes = Int((workoutEnd.timeIntervalSince(workoutStart) / 60).rounded())
        return SessionDraftValues(
            date: workoutStart,
            durationMinutes: SurfSession.normalizedDuration(rawMinutes)
        )
    }

    /// Builds the Peak session an import should insert. Does not write back to
    /// Health — the workout already exists there (Watch / Workout app).
    static func importedSession(
        workout: WorkoutSummary,
        stats: WaveStats?,
        spot: Spot?
    ) -> SurfSession {
        let draft = draftValues(workoutStart: workout.start, workoutEnd: workout.end)
        let session = SurfSession(
            date: draft.date,
            spot: spot,
            durationMinutes: draft.durationMinutes,
            notes: "Imported from Apple Health"
        )
        if let stats {
            session.applyDerivedWaveStats(stats, workoutID: workout.id.uuidString)
        } else {
            session.linkedWorkoutID = workout.id.uuidString
        }
        return session
    }
}

extension Notification.Name {
    /// Posted when HealthKit reports a new or deleted workout. The Log-tab
    /// unlogged-workout card refreshes; it is not a user-visible notification.
    static let peakUnloggedWorkoutsMayHaveChanged = Notification.Name("peakUnloggedWorkoutsMayHaveChanged")
}

// MARK: - Fetched stats

/// Source-agnostic Health stats over a session window (Apple Watch data shows
/// up with no watch app needed).
struct SessionHealthStats: Equatable {
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?

    var isEmpty: Bool {
        averageHeartRate == nil && maxHeartRate == nil && activeEnergyKilocalories == nil
    }
}

// MARK: - Route access boundary

/// The one thing `WaveAnalyzer` surfacing needs from HealthKit: the GPS route of
/// a workout, already mapped to the analyzer's CoreLocation-free `RouteSample`.
///
/// It is a protocol purely so tests can drive the whole import/preview path from
/// synthetic fixtures. CI runs on a simulator with no entitlements and no Health
/// database, so anything that reached `HKHealthStore` in a unit test would either
/// hang or silently return nothing — neither of which is a test.
nonisolated protocol WorkoutRouteProviding: Sendable {
    /// Route fixes for a workout, in HealthKit's order. Returns an empty array —
    /// never an error — when the feature is off, unauthorized, or the workout
    /// simply has no route (an indoor session, or a watch that lost GPS).
    func routeSamples(forWorkoutID id: UUID) async -> [RouteSample]
}

/// Derives wave statistics for a workout. Kept separate from `HealthKitService`
/// so the analysis path is exercised in tests through a mock provider.
nonisolated enum WaveStatsDeriver {
    /// Fetches the route and analyzes it off the main thread.
    ///
    /// `nil` means "no usable route", which is deliberately distinct from
    /// `WaveStats.zero` ("a route, but the surfer caught nothing"). The UI shows
    /// nothing at all in the first case and an honest zero in the second.
    static func stats(
        forWorkoutID id: UUID,
        provider: any WorkoutRouteProviding,
        tuning: WaveAnalyzer.Tuning = WaveAnalyzer.Tuning()
    ) async -> WaveStats? {
        let samples = await provider.routeSamples(forWorkoutID: id)
        // Two fixes cannot describe a session; the analyzer would return `.zero`
        // and we would present an authoritative-looking "0 waves" for a workout
        // that was never actually tracked.
        guard samples.count >= WaveAnalyzer.Tuning().minWaveSampleCount else { return nil }
        return await WaveAnalyzer.analyzeOffMain(samples: samples, tuning: tuning)
    }
}

enum HealthKitServiceError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Apple Health is not available on this device."
        }
    }
}

// MARK: - Service

/// Apple Health integration. Feature-gated by the "healthSyncEnabled" user
/// default (Settings toggle, default OFF): every write and read is a quiet
/// no-op while the feature is disabled, unavailable, or unauthorized.
///
/// Writes go through HKWorkoutBuilder (the iOS 17-friendly path) and stamp
/// `HealthKitLogic.sessionKeyMetadataKey` so a session's workout can be
/// replaced or deleted later without storing a HealthKit UUID on the model.
final class HealthKitService {
    private let workoutQueue = HealthWorkoutQueue()
    static let shared = HealthKitService()

    /// AppStorage/UserDefaults key for the Settings toggle.
    static let healthSyncEnabledKey = "healthSyncEnabled"

    /// Opt-in: post a system notification when a Watch surf is ready to log.
    /// Off by default; never requested until the surfer flips this toggle.
    static let notifyUnloggedWorkoutsKey = "notifyUnloggedSurfWorkouts"

    static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let healthStore = HKHealthStore()
    private var workoutObserver: HKObserverQuery?
    nonisolated(unsafe) private var didEnableBackgroundDelivery = false

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.healthSyncEnabledKey)
    }

    /// Sharing (write) status is queryable; read status intentionally is not.
    var isWorkoutSharingDenied: Bool {
        guard Self.isHealthDataAvailable else { return false }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied
    }

    private var canWrite: Bool {
        Self.isHealthDataAvailable &&
        isEnabled &&
        healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    private var canRead: Bool {
        Self.isHealthDataAvailable && isEnabled
    }

    // MARK: Authorization

    /// Requests share access for workouts and read access for workouts, heart
    /// rate, and active energy. Succeeds even if the user denies; denial only
    /// surfaces via `isWorkoutSharingDenied` (writes) or empty reads.
    func requestAuthorization() async throws {
        guard Self.isHealthDataAvailable else {
            throw HealthKitServiceError.healthDataUnavailable
        }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            // 3.0: the GPS route behind a surf workout, which is what
            // `WaveAnalyzer` mines for wave count / top speed / ride length.
            // Route access is its own authorization type — asking for the workout
            // alone returns workouts with no locations attached.
            HKSeriesType.workoutRoute()
        ]
        try await healthStore.requestAuthorization(toShare: share, read: read)
        startObservingUnloggedWorkouts()
    }

    // MARK: Unlogged-workout observer

    /// Long-running observer so the Log-tab card (and optional notification)
    /// notice a Watch surf without the surfer opening Import from Health.
    /// Quiet no-op when Health sync is off, unavailable, or under UI tests.
    func startObservingUnloggedWorkouts() {
        guard canRead, !TestingDefaults.isUITest else {
            stopObservingUnloggedWorkouts()
            return
        }
        guard workoutObserver == nil else { return }

        let predicate = HKQuery.predicateForWorkouts(with: .surfingSports)
        let query = HKObserverQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate
        ) { _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            // Apple's contract: finish the work, *then* tell HealthKit. Calling
            // completionHandler first lets iOS suspend Peak before the local
            // notification is posted.
            Task {
                let taskID = await MainActor.run {
                    UIApplication.shared.beginBackgroundTask(withName: "PeakUnloggedSurf") {}
                }
                await UnloggedSurfNotification.handleObserverWake()
                completionHandler()
                await MainActor.run {
                    if taskID != .invalid {
                        UIApplication.shared.endBackgroundTask(taskID)
                    }
                }
            }
        }
        workoutObserver = query
        healthStore.execute(query)

        guard !didEnableBackgroundDelivery else { return }
        healthStore.enableBackgroundDelivery(
            for: HKObjectType.workoutType(),
            frequency: .immediate
        ) { [weak self] success, _ in
            if success {
                self?.didEnableBackgroundDelivery = true
            }
        }
    }

    func stopObservingUnloggedWorkouts() {
        if let workoutObserver {
            healthStore.stop(workoutObserver)
            self.workoutObserver = nil
        }
        guard didEnableBackgroundDelivery else { return }
        healthStore.disableBackgroundDelivery(for: HKObjectType.workoutType()) { [weak self] _, _ in
            self?.didEnableBackgroundDelivery = false
        }
    }

    // MARK: Write hooks (fire-and-forget, safe as one-line call sites)

    /// Writes (or rewrites) the Health workout for a session. Call after a
    /// session is created or edited. No-op when the feature is off, Health is
    /// unavailable/denied, or the session has no logged duration.
    func saveOrUpdateWorkout(
        for session: SurfSession, previousLegacy: HealthKitLogic.LegacyWorkoutMatch? = nil
    ) {
        guard canWrite, let values = workoutValues(for: session) else { return }
        _ = workoutQueue.enqueue(key: values.key) {
            guard self.canWrite else { return }
            try await self.replaceWorkout(sessionKey: values.key, interval: values.interval,
                                          legacy: previousLegacy ?? values.legacy)
        }
    }

    struct WorkoutDeletion {
        let key: String
        let legacy: HealthKitLogic.LegacyWorkoutMatch?
    }

    /// Capture before model deletion; this performs no HealthKit work.
    func workoutDeletion(for session: SurfSession) -> WorkoutDeletion? {
        guard canWrite, let id = session.sessionID else { return nil }
        return WorkoutDeletion(key: HealthKitLogic.sessionKey(forSessionID: id),
                               legacy: legacyWorkoutMatch(for: session))
    }

    /// Schedule only after the corresponding local deletion has saved.
    func deleteWorkout(_ deletion: WorkoutDeletion?) {
        guard canWrite, let deletion else { return }
        _ = workoutQueue.enqueue(key: deletion.key) {
            guard self.canWrite else { return }
            try await self.deletePeakWorkouts(sessionKey: deletion.key)
            if let legacy = deletion.legacy {
                try await self.deletePeakWorkouts(sessionKey: legacy.key, exactInterval: legacy)
            }
        }
    }

    // MARK: Write primitives (awaitable)

    /// Saves the workout for a session, replacing any previous Peak workout
    /// with the same session key. Returns false when skipped (disabled,
    /// unauthorized, or no duration).
    @discardableResult
    func saveWorkout(for session: SurfSession) async throws -> Bool {
        guard canWrite, let values = workoutValues(for: session) else { return false }
        try await workoutQueue.enqueue(key: values.key) {
            guard self.canWrite else { return }
            try await self.replaceWorkout(sessionKey: values.key, interval: values.interval, legacy: values.legacy)
        }.value
        return true
    }

    /// Replacement preserves the existing workout until the new one is saved.
    @discardableResult
    func updateWorkout(for session: SurfSession) async throws -> Bool {
        try await saveWorkout(for: session)
    }

    // MARK: Batch backfill

    struct SyncSummary: Equatable {
        var written = 0
        var skipped = 0
        var failed = 0
    }

    /// Writes workouts for every session (used by Settings > Sync Existing
    /// Sessions). Sessions without a duration are counted as skipped.
    func syncAllSessions(
        _ sessions: [SurfSession],
        progress: ((Int, Int) -> Void)? = nil
    ) async -> SyncSummary {
        var summary = SyncSummary()
        let total = sessions.count
        for (index, session) in sessions.enumerated() {
            guard canWrite else {
                summary.skipped += total - index
                break
            }
            if let values = workoutValues(for: session) {
                do {
                    try await workoutQueue.enqueue(key: values.key) {
                        guard self.canWrite else { return }
                        try await self.replaceWorkout(sessionKey: values.key, interval: values.interval, legacy: values.legacy)
                    }.value
                    summary.written += 1
                } catch {
                    summary.failed += 1
                }
            } else {
                summary.skipped += 1
            }
            progress?(index + 1, total)
        }
        return summary
    }

    // MARK: Reads

    /// Avg/max heart rate and total active energy over the session window.
    /// Quiet by design: returns nil when disabled, unavailable, denied, or
    /// there is simply no data — the caller cannot (and should not) tell the
    /// difference.
    func fetchStats(for session: SurfSession) async -> SessionHealthStats? {
        guard canRead else { return nil }
        let window = HealthKitLogic.sessionWindow(
            date: session.date,
            durationMinutes: session.durationMinutes
        )
        let samplePredicate = HKQuery.predicateForSamples(
            withStart: window.start,
            end: window.end,
            options: []
        )

        var stats = SessionHealthStats()

        do {
            let heartRateDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: samplePredicate),
                options: [.discreteAverage, .discreteMax]
            )
            if let result = try await heartRateDescriptor.result(for: healthStore) {
                let bpm = HKUnit.count().unitDivided(by: .minute())
                stats.averageHeartRate = result.averageQuantity()?.doubleValue(for: bpm)
                stats.maxHeartRate = result.maximumQuantity()?.doubleValue(for: bpm)
            }
        } catch {
            // Quiet: treat as no data.
        }

        do {
            let energyDescriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(.activeEnergyBurned), predicate: samplePredicate),
                options: [.cumulativeSum]
            )
            if let result = try await energyDescriptor.result(for: healthStore) {
                stats.activeEnergyKilocalories = result.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
        } catch {
            // Quiet: treat as no data.
        }

        return stats.isEmpty ? nil : stats
    }

    /// Surf workouts from any source that Peak did not write and that do not
    /// overlap an already-logged session — candidates for import.
    func fetchUnloggedSurfWorkouts(existingSessions: [SurfSession]) async throws -> [HealthKitLogic.WorkoutSummary] {
        guard canRead else { return [] }
        let surfPredicate = HKQuery.predicateForWorkouts(with: .surfingSports)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(surfPredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let workouts = try await descriptor.result(for: healthStore)
        let summaries = workouts.map { workout in
            HealthKitLogic.WorkoutSummary(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                sourceName: workout.sourceRevision.source.name,
                isFromPeak: workout.metadata?[HealthKitLogic.sessionKeyMetadataKey] != nil
            )
        }
        let windows = existingSessions.map {
            HealthKitLogic.sessionWindow(date: $0.date, durationMinutes: $0.durationMinutes)
        }
        return HealthKitLogic.unloggedWorkouts(from: summaries, sessionWindows: windows)
    }

    /// One workout by UUID, mapped to the same summary import uses. Nil when
    /// Health is off or the UUID is gone — the Log notification then no-ops.
    func fetchSurfWorkoutSummary(id: UUID) async -> HealthKitLogic.WorkoutSummary? {
        guard canRead else { return nil }
        guard let workout = try? await workout(withID: id) else { return nil }
        return HealthKitLogic.WorkoutSummary(
            id: workout.uuid,
            start: workout.startDate,
            end: workout.endDate,
            sourceName: workout.sourceRevision.source.name,
            isFromPeak: workout.metadata?[HealthKitLogic.sessionKeyMetadataKey] != nil
        )
    }

    // MARK: Route reads (3.0)

    /// Route fixes for one workout, mapped to `RouteSample`.
    ///
    /// Quiet by the same rule as `fetchStats`: disabled, unauthorized, no route,
    /// and "HealthKit threw" are all reported as an empty array. The caller shows
    /// no wave stats in every one of those cases, so distinguishing them would
    /// only produce an error message the user cannot act on.
    func routeSamples(forWorkoutID id: UUID) async -> [RouteSample] {
        guard canRead else { return [] }
        do {
            guard let workout = try await workout(withID: id) else { return [] }
            var samples: [RouteSample] = []
            // A workout can carry more than one route series (the watch restarts
            // one after a long GPS outage). They are concatenated; the analyzer
            // sorts by timestamp and treats the seam as an untrusted link anyway.
            for route in try await routeSeries(for: workout) {
                let locations = try await locations(in: route)
                // Mapped off-main: a long session is tens of thousands of fixes,
                // and this method is otherwise MainActor-isolated.
                samples.append(contentsOf: await Self.mapToRouteSamples(locations))
            }
            return samples
        } catch {
            return []
        }
    }

    /// `@concurrent` so the CLLocation → RouteSample conversion leaves the main
    /// actor (a plain `nonisolated` async function would inherit the caller's
    /// actor under this project's MainActor default isolation).
    @concurrent
    nonisolated private static func mapToRouteSamples(_ locations: [CLLocation]) async -> [RouteSample] {
        locations.map(RouteSample.init(location:))
    }

    private func workout(withID id: UUID) async throws -> HKWorkout? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: [],
            limit: 1
        )
        return try await descriptor.result(for: healthStore).first
    }

    private func routeSeries(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try await descriptor.result(for: healthStore)
    }

    /// Bridges `HKWorkoutRouteQuery`, which is still a multi-callback API with no
    /// async form, into a single awaited array.
    ///
    /// The handler fires repeatedly with batches until `done`, so the accumulator
    /// has to survive between calls and the continuation must be resumed exactly
    /// once — resuming twice is a hard crash, not a warning.
    private func locations(in route: HKWorkoutRoute) async throws -> [CLLocation] {
        let accumulator = RouteAccumulator()
        let store = healthStore
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let error {
                        if accumulator.finish() { continuation.resume(throwing: error) }
                        return
                    }
                    accumulator.append(locations ?? [])
                    if done, accumulator.finish() {
                        continuation.resume(returning: accumulator.collected)
                    }
                }
                // `begin` loses the race only if cancellation already claimed
                // the finish — then the query must never start and the await
                // fails as cancelled here instead.
                guard accumulator.begin(query: query, continuation: continuation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                store.execute(query)
            }
        } onCancel: {
            accumulator.cancel(store: store)
        }
    }

    // MARK: Internals

    /// Write inputs for a session; nil when the session has no logged duration
    /// (we never fabricate a workout length).
    private func workoutValues(for session: SurfSession) -> (
        key: String, interval: DateInterval, legacy: HealthKitLogic.LegacyWorkoutMatch?
    )? {
        guard !session.isDeleted, session.modelContext != nil,
              HealthKitLogic.shouldWriteWorkout(linkedWorkoutID: session.linkedWorkoutID),
              let id = session.sessionID, let duration = session.durationMinutes, duration > 0 else { return nil }
        return (
            key: HealthKitLogic.sessionKey(forSessionID: id),
            interval: HealthKitLogic.sessionWindow(date: session.date, durationMinutes: duration),
            legacy: legacyWorkoutMatch(for: session)
        )
    }

    func legacyWorkoutMatch(for session: SurfSession) -> HealthKitLogic.LegacyWorkoutMatch? {
        guard let context = session.modelContext,
              let sessions = try? context.fetch(FetchDescriptor<SurfSession>()) else { return nil }
        let key = HealthKitLogic.sessionKey(forSessionCreatedAt: session.createdAt)
        let owners = sessions.filter {
            HealthKitLogic.sessionKey(forSessionCreatedAt: $0.createdAt) == key
        }
        guard owners.count == 1, owners[0].persistentModelID == session.persistentModelID else { return nil }
        return HealthKitLogic.legacyWorkoutMatch(
            createdAt: session.createdAt, date: session.date,
            durationMinutes: session.durationMinutes, matchingSessionCount: owners.count
        )
    }

    /// Create replacement first, then remove captured prior Peak workouts.
    private func replaceWorkout(
        sessionKey key: String, interval: DateInterval, legacy: HealthKitLogic.LegacyWorkoutMatch?
    ) async throws {
        try await HealthKitLogic.replacePreservingOld(
            capture: {
                var old = try await self.peakWorkouts(sessionKey: key)
                if let legacy {
                    old += try await self.peakWorkouts(sessionKey: legacy.key, exactInterval: legacy)
                }
                return old
            },
            create: {
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .surfingSports
                configuration.locationType = .outdoor
                let builder = HKWorkoutBuilder(healthStore: self.healthStore,
                                               configuration: configuration, device: .local())
                try await builder.beginCollection(at: interval.start)
                try await builder.addMetadata([HealthKitLogic.sessionKeyMetadataKey: key])
                try await builder.endCollection(at: interval.end)
                guard let workout = try await builder.finishWorkout() else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return workout.uuid
            },
            identifier: { $0.uuid },
            delete: { try await self.healthStore.delete($0) }
        )
    }

    private func deletePeakWorkouts(
        sessionKey key: String, exactInterval: HealthKitLogic.LegacyWorkoutMatch? = nil
    ) async throws {
        let workouts = try await peakWorkouts(sessionKey: key, exactInterval: exactInterval)
        if !workouts.isEmpty { try await healthStore.delete(workouts) }
    }

    private func peakWorkouts(
        sessionKey key: String, exactInterval: HealthKitLogic.LegacyWorkoutMatch? = nil
    ) async throws -> [HKWorkout] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(
                withMetadataKey: HealthKitLogic.sessionKeyMetadataKey,
                allowedValues: [key]
            ),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        )
        let candidates = try await descriptor.result(for: healthStore)
        let workouts = candidates.filter { workout in
            guard let exactInterval else { return true }
            return workout.workoutActivityType == .surfingSports
                && exactInterval.matches(start: workout.startDate, end: workout.endDate)
        }
        return workouts
    }
}

extension HealthKitService: WorkoutRouteProviding {}

/// Mutable state shared across `HKWorkoutRouteQuery`'s repeated callbacks.
///
/// `@unchecked Sendable` with an explicit lock rather than an actor: the handler
/// is not async, so it cannot await an actor, and HealthKit gives no ordering
/// guarantee strong enough to rely on without one.
private final class RouteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CLLocation] = []
    private var isFinished = false
    private var query: HKWorkoutRouteQuery?
    private var continuation: CheckedContinuation<[CLLocation], Error>?

    var collected: [CLLocation] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ locations: [CLLocation]) {
        lock.lock(); defer { lock.unlock() }
        storage.append(contentsOf: locations)
    }

    /// Registers the in-flight query and continuation so a task cancellation
    /// can stop the one and resume the other. Returns false when the work
    /// already finished (or was cancelled) first — the caller should not
    /// execute the query in that case.
    func begin(query: HKWorkoutRouteQuery, continuation: CheckedContinuation<[CLLocation], Error>) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isFinished else { return false }
        self.query = query
        self.continuation = continuation
        return true
    }

    /// Claims the right to resume the continuation. True exactly once.
    /// Also drops the registered query/continuation so `cancel` can no
    /// longer touch them.
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isFinished else { return false }
        isFinished = true
        query = nil
        continuation = nil
        return true
    }

    /// Cancellation path: claims the single resume, stops the HealthKit query
    /// so it releases its buffers immediately, and fails the await. Without
    /// this, leaving the Import screen leaves every in-flight route query
    /// running to completion with its accumulated locations alive.
    func cancel(store: HKHealthStore) {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        let query = self.query
        let continuation = self.continuation
        self.query = nil
        self.continuation = nil
        lock.unlock()

        if let query { store.stop(query) }
        continuation?.resume(throwing: CancellationError())
    }
}

// MARK: - CoreLocation boundary

extension RouteSample {
    /// One-to-one mapping from CoreLocation.
    ///
    /// This is the *only* place CoreLocation meets the analyzer: `WaveAnalyzer`
    /// stays CoreLocation-free so its 60-plus tests run against synthetic fixtures
    /// with no simulator location, no entitlements, and no device. CoreLocation's
    /// `-1` "unknown" sentinels for speed and course are passed straight through —
    /// `RouteSample` documents them as its own contract and handles them
    /// internally, so nothing here needs to pre-clean them.
    nonisolated init(location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedMetersPerSecond: location.speed,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            courseDegrees: location.course
        )
    }
}
