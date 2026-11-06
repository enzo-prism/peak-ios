import CoreLocation
import Foundation
import HealthKit

/// Records the session's GPS track into an `HKWorkoutRoute` attached to the
/// saved workout.
///
/// **This is the single most important class in the watch app**, and the least
/// obvious. `HKLiveWorkoutDataSource` collects heart rate, energy and distance
/// on its own, but it does *not* collect a route — Apple's own Workout app
/// builds one explicitly, and so must Peak. Without this, the watch would save
/// a workout with no locations, and the phone's `WaveAnalyzer` (which mines the
/// route for wave count, top speed and ride length) would have nothing to
/// analyse. The entire "watch records, phone analyses" design rests here.
///
/// GPS behaviour in surf is genuinely strange and the tuning reflects it: the
/// antenna only sees sky when the wrist clears the water, so fixes arrive in
/// bursts separated by long gaps, and many are poor. Nothing is filtered out
/// here on purpose — `WaveAnalyzer` already does accuracy filtering and gap
/// bridging with constants awaiting real-session validation, and a second, different
/// filter upstream would fight it.
@MainActor
final class WatchRouteRecorder: NSObject {
    private let locationManager = CLLocationManager()
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var isRecording = false
    private var insertionTask: Task<Void, Never>?
    private var insertionFailed = false

    /// First fix of the session, used to guess the spot in the phone's nudge.
    private(set) var firstFix: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        // `.fitness` tells CoreLocation this is a human-powered outdoor
        // activity, which is the closest match for paddling and keeps the
        // filtering appropriate for slow speeds punctuated by fast ones.
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Every fix matters: a wave lasts seconds and the wrist is only clear of
        // the water for part of it, so no distance filter.
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Begins collecting locations into a fresh route builder.
    func start(healthStore: HKHealthStore) {
        guard !isRecording else { return }
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        firstFix = nil
        insertionFailed = false
        resume()
    }

    func resume() {
        guard routeBuilder != nil, !isRecording else { return }
        isRecording = true
        // The session keeps running with the wrist down and the screen off, so
        // updates have to survive backgrounding. watchOS grants this for the
        // duration of an active workout session.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
    }

    /// Stops collecting and attaches the route to the finished workout.
    ///
    /// A nil `workout` means the workout save itself failed; the route is
    /// discarded rather than orphaned, because a route with nothing to hang off
    /// is invisible to every reader including Peak's own importer.
    func pause() {
        isRecording = false
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    func discard() {
        pause()
        insertionTask?.cancel()
        routeBuilder?.discard()
        routeBuilder = nil
    }

    @discardableResult func finish(attachingTo workout: HKWorkout?) async -> Bool {
        pause()
        await insertionTask?.value
        guard let routeBuilder else { return false }
        self.routeBuilder = nil
        guard let workout else { routeBuilder.discard(); return false }
        do {
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            return firstFix != nil && !insertionFailed
        } catch { return false }
    }

}

// MARK: - CLLocationManagerDelegate

extension WatchRouteRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard self.isRecording, let routeBuilder = self.routeBuilder else { return }
            if self.firstFix == nil, let first = locations.first {
                self.firstFix = first.coordinate
            }
            let previous = self.insertionTask
            self.insertionTask = Task { @MainActor in
                await previous?.value
                guard !Task.isCancelled else { return }
                do { try await routeBuilder.insertRouteData(locations) }
                catch { self.insertionFailed = true }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS failures are the norm in the water, not an event worth
        // surfacing. The route simply has a gap, which the analyzer expects.
    }
}
