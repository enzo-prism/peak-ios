import CoreLocation
import Foundation
import MapKit

/// One-shot "current location" provider used to pin surf spots near the user.
///
/// - When-in-use authorization only; requested lazily on first use.
/// - Resolves to `nil` (never throws) when access is denied, restricted, or the
///   fix fails, so callers can degrade gracefully.
/// - Inert under UI tests: it never creates a `CLLocationManager`, so the
///   system location prompt can never appear in that mode.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return manager
    }()

    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    /// True when the app can read the location without showing a prompt.
    var isAuthorized: Bool {
        guard !TestingDefaults.isUITest else { return false }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    /// Resolves the user's current coordinate, asking for when-in-use
    /// permission first when it hasn't been determined yet. Returns `nil` on
    /// denial, failure, or while another request is already in flight.
    func currentLocation() async -> CLLocationCoordinate2D? {
        guard !TestingDefaults.isUITest else { return nil }
        // One request at a time; a second caller while in flight backs off.
        guard authorizationContinuation == nil, locationContinuation == nil else { return nil }

        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        guard isAuthorized else { return nil }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    // CoreLocation calls back on the manager's thread; hop to the main actor
    // before touching state (the project defaults to MainActor isolation).

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Also fires when the manager is created, while still undetermined;
            // only resume once the user has actually answered the prompt.
            guard status != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.locationContinuation?.resume(returning: coordinate)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}

/// Pure map-region defaulting shared by the spot editor and the spots map.
/// Kept free of CoreLocation/MapKit side effects so it stays unit-testable.
enum SpotMapRegion {
    /// Span used when centering on a single known point (a pin or the user).
    static let focusedSpan = MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)

    /// Wide fallback framing the US West Coast surf corridor. Never 0,0.
    static var wideDefault: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0, longitude: -118.5),
            span: MKCoordinateSpan(latitudeDelta: 45, longitudeDelta: 45)
        )
    }

    /// Editor default, in priority order: the spot's own pin, else the user's
    /// location, else a region fitted to already-pinned spots, else the wide
    /// default.
    static func defaultRegion(
        spotCoordinate: CLLocationCoordinate2D?,
        userCoordinate: CLLocationCoordinate2D?,
        pinnedSpotCoordinates: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        if let spotCoordinate {
            return MKCoordinateRegion(center: spotCoordinate, span: focusedSpan)
        }
        if let userCoordinate {
            return MKCoordinateRegion(center: userCoordinate, span: focusedSpan)
        }
        if let fitted = fittedRegion(for: pinnedSpotCoordinates) {
            return fitted
        }
        return wideDefault
    }

    /// A region containing every coordinate, padded so pins don't hug the map
    /// edge. Returns `nil` for an empty list. (No anti-meridian handling: a
    /// library spanning ±180° longitude simply produces a wide region.)
    static func fittedRegion(
        for coordinates: [CLLocationCoordinate2D],
        paddingFactor: Double = 1.4,
        minimumSpan: CLLocationDegrees = 0.5
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLatitude - minLatitude) * paddingFactor, minimumSpan), 170),
            longitudeDelta: min(max((maxLongitude - minLongitude) * paddingFactor, minimumSpan), 350)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
