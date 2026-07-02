import Foundation
import HealthKit
import SwiftData

// MARK: - Pure logic (unit-testable without HKHealthStore)

/// HealthKit-free logic for the Apple Health integration: stable session keys,
/// session time windows, workout/session overlap matching, and workout->draft
/// mapping. Kept free of HealthKit types so it is unit-testable without
/// entitlements or an HKHealthStore.
enum HealthKitLogic {
    /// Metadata key written on every workout Peak saves, so our own workouts can
    /// be found again (update/delete) and excluded from import suggestions.
    static let sessionKeyMetadataKey = "com.designprism.peak.sessionKey"

    /// Window length assumed for sessions without a logged duration. Used only
    /// for read-side heuristics (stats window + overlap matching), never to
    /// fabricate a workout duration.
    static let assumedDurationMinutes = 60

    /// Stable identifier for a session, derived from `createdAt` (which never
    /// changes across edits) at millisecond precision.
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
    static let shared = HealthKitService()

    /// AppStorage/UserDefaults key for the Settings toggle.
    static let healthSyncEnabledKey = "healthSyncEnabled"

    static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let healthStore = HKHealthStore()

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
            HKQuantityType(.activeEnergyBurned)
        ]
        try await healthStore.requestAuthorization(toShare: share, read: read)
    }

    // MARK: Write hooks (fire-and-forget, safe as one-line call sites)

    /// Writes (or rewrites) the Health workout for a session. Call after a
    /// session is created or edited. No-op when the feature is off, Health is
    /// unavailable/denied, or the session has no logged duration.
    func saveOrUpdateWorkout(for session: SurfSession) {
        guard canWrite, let values = workoutValues(for: session) else { return }
        Task {
            try? await self.replaceWorkout(sessionKey: values.key, interval: values.interval)
        }
    }

    /// Deletes the Health workout for a session. IMPORTANT: call BEFORE
    /// `modelContext.delete(session)` — the stable key is derived from
    /// `session.createdAt`, which is read synchronously here.
    func deleteWorkout(for session: SurfSession) {
        deleteWorkout(sessionKey: HealthKitLogic.sessionKey(forSessionCreatedAt: session.createdAt))
    }

    /// Delete by pre-captured session key (for callers that must delete the
    /// model object first).
    func deleteWorkout(sessionKey key: String) {
        guard canWrite else { return }
        Task {
            try? await self.deletePeakWorkouts(sessionKey: key)
        }
    }

    // MARK: Write primitives (awaitable)

    /// Saves the workout for a session, replacing any previous Peak workout
    /// with the same session key. Returns false when skipped (disabled,
    /// unauthorized, or no duration).
    @discardableResult
    func saveWorkout(for session: SurfSession) async throws -> Bool {
        guard canWrite, let values = workoutValues(for: session) else { return false }
        try await replaceWorkout(sessionKey: values.key, interval: values.interval)
        return true
    }

    /// Delete-then-resave; same behavior as `saveWorkout(for:)` because saves
    /// are always replace-by-key (keeps the operation idempotent).
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
                    try await replaceWorkout(sessionKey: values.key, interval: values.interval)
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

    // MARK: Internals

    /// Write inputs for a session; nil when the session has no logged duration
    /// (we never fabricate a workout length).
    private func workoutValues(for session: SurfSession) -> (key: String, interval: DateInterval)? {
        guard let duration = session.durationMinutes, duration > 0 else { return nil }
        return (
            key: HealthKitLogic.sessionKey(forSessionCreatedAt: session.createdAt),
            interval: HealthKitLogic.sessionWindow(date: session.date, durationMinutes: duration)
        )
    }

    /// Delete any previous Peak workout carrying this session key, then write a
    /// fresh HKWorkoutBuilder workout spanning the interval.
    private func replaceWorkout(sessionKey key: String, interval: DateInterval) async throws {
        try await deletePeakWorkouts(sessionKey: key)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .surfingSports
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: interval.start)
        try await builder.addMetadata([HealthKitLogic.sessionKeyMetadataKey: key])
        try await builder.endCollection(at: interval.end)
        _ = try await builder.finishWorkout()
    }

    private func deletePeakWorkouts(sessionKey key: String) async throws {
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
        let workouts = try await descriptor.result(for: healthStore)
        guard !workouts.isEmpty else { return }
        try await healthStore.delete(workouts)
    }
}
