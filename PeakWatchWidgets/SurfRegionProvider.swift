import CoreLocation
import Foundation
import HealthKit

/// Works out *where* this surfer surfs, so the Smart Stack can put "Log your
/// surf" in front of them when they are standing on that sand.
///
/// The obvious source for this is the user's saved spots in SwiftData — but the
/// store lives on the phone, and sharing it with a watch widget would need the
/// App Group (`group.com.designprism.peak`), which is still unregistered in the
/// developer portal and is a hard blocker for this release.
///
/// So the answer comes from HealthKit instead, which both the watch app and this
/// extension can read without any shared container: every surf workout Peak (or
/// the native Workout app, or anything else) has ever saved carries a GPS route,
/// and the first fix of each route is a place this person surfs. No phone, no
/// App Group, no network.
///
/// Note the honest limitation: a surfer with no logged surf workouts yet gets no
/// location relevance at all. That is the correct behaviour — guessing at
/// generic "beach" POIs would surface the widget at every seaside car park in
/// the country.
enum SurfRegionProvider {
    /// How many past sessions to consider. Enough to cover a home break plus a
    /// travel spot or two without turning relevance evaluation into a long
    /// HealthKit crawl inside a widget's tight execution budget.
    static let workoutLookbackCount = 25

    /// Radius of the geofence placed on each past surf location. Matches
    /// `NearestSpotMatcher`'s matching radius so "near enough to suggest
    /// logging" and "near enough to name the spot" mean the same thing.
    static let regionRadiusMeters: Double = NearestSpotMatcher.defaultMaxDistanceMeters

    /// Distinct places, so ten sessions at one break produce one region.
    static let deduplicationRadiusMeters: Double = 1_000

    /// Cap on regions handed to the system; beyond a handful the relevance
    /// signal is diluted rather than improved.
    static let maxRegions = 8

    /// Circular regions around the start of each recent surf workout.
    ///
    /// Returns an empty array for every failure mode — unauthorized, no
    /// workouts, no routes, HealthKit unavailable. A widget with no relevance
    /// attributes simply behaves like any ordinary widget, which is a fine
    /// outcome and not worth an error path.
    static func recentSurfRegions() async -> [CLCircularRegion] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let store = HKHealthStore()

        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForWorkouts(with: .surfingSports))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: workoutLookbackCount
            )
            let workouts = try await descriptor.result(for: store)

            var coordinates: [CLLocationCoordinate2D] = []
            for workout in workouts {
                guard let coordinate = try await firstRouteCoordinate(for: workout, store: store) else {
                    continue
                }
                coordinates.append(coordinate)
            }
            return regions(from: deduplicated(coordinates))
        } catch {
            return []
        }
    }

    // MARK: - Internals

    private static func firstRouteCoordinate(
        for workout: HKWorkout,
        store: HKHealthStore
    ) async throws -> CLLocationCoordinate2D? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 1
        )
        guard let route = try await descriptor.result(for: store).first else { return nil }
        return try await firstLocation(in: route)?.coordinate
    }

    /// Pulls only the first batch out of `HKWorkoutRouteQuery` and stops.
    ///
    /// The full route can be thousands of fixes and all this needs is where the
    /// surfer paddled out, so the query is cancelled as soon as one location
    /// arrives. As in `HealthKitService`, the continuation must resume exactly
    /// once — a second resume is a crash, not a warning.
    private static func firstLocation(in route: HKWorkoutRoute) async throws -> CLLocation? {
        let store = HKHealthStore()
        let box = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { query, locations, done, error in
                if let error {
                    if box.claim() { continuation.resume(throwing: error) }
                    return
                }
                if let first = locations?.first {
                    store.stop(query)
                    if box.claim() { continuation.resume(returning: first) }
                    return
                }
                if done, box.claim() {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    /// Collapses coordinates that describe the same break.
    static func deduplicated(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var kept: [CLLocationCoordinate2D] = []
        for coordinate in coordinates {
            let isNew = kept.allSatisfy { existing in
                NearestSpotMatcher.distanceMeters(
                    fromLatitude: existing.latitude,
                    longitude: existing.longitude,
                    toLatitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ) > deduplicationRadiusMeters
            }
            if isNew { kept.append(coordinate) }
            if kept.count >= maxRegions { break }
        }
        return kept
    }

    private static func regions(from coordinates: [CLLocationCoordinate2D]) -> [CLCircularRegion] {
        coordinates.enumerated().map { index, coordinate in
            CLCircularRegion(
                center: coordinate,
                radius: regionRadiusMeters,
                identifier: "com.designprism.peak.surfRegion.\(index)"
            )
        }
    }
}

/// One-shot guard for a checked continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
