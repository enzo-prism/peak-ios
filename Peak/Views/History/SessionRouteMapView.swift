import CoreLocation
import MapKit
import SwiftUI

/// Transient GPS overlay for a Health-linked session. Coordinates live only in
/// memory for the lifetime of this view — they are never written to the store.
struct SessionRouteMapView: View {
    let workoutID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayCoordinates: [CLLocationCoordinate2D] = []
    @State private var waveCoordinateSets: [[CLLocationCoordinate2D]] = []
    @State private var stats: WaveStats?
    @State private var didLoad = false
    @State private var cameraPosition: MapCameraPosition = .region(SpotMapRegion.wideDefault)

    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if displayCoordinates.count >= 2 {
                mapCard
            }
        }
        .task {
            await load()
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(position: $cameraPosition, interactionModes: []) {
                MapPolyline(coordinates: displayCoordinates)
                    .stroke(Theme.textMuted, lineWidth: 3)
                ForEach(Array(waveCoordinateSets.enumerated()), id: \.offset) { _, coords in
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.surfGreen, lineWidth: 4)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)

            Text("Estimates — tap a session field to correct")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("session.detail.routeMap")
    }

    private var accessibilityLabel: String {
        let count = stats?.waveCount ?? 0
        return "GPS route estimate, \(count) wave\(count == 1 ? "" : "s")"
    }

    private func load() async {
        guard !TestingDefaults.isUITest, let uuid = UUID(uuidString: workoutID) else {
            didLoad = true
            return
        }
        let loaded = await HealthKitService.shared.routeSamples(forWorkoutID: uuid)
        if loaded.count >= 2 {
            // Analysis stays on the full track; MapKit only sees a simplified
            // polyline so tens of thousands of GPS fixes don't hitch the detail
            // screen (Apple Maps: reduce overlay point counts).
            stats = await WaveAnalyzer.analyzeOffMain(samples: loaded)
            displayCoordinates = RouteDisplaySimplifier.coordinates(
                RouteDisplaySimplifier.simplified(samples: loaded)
            )
            waveCoordinateSets = wavePolylines(from: loaded, stats: stats)
            fitCamera()
        }
        didLoad = true
    }

    private func wavePolylines(from samples: [RouteSample], stats: WaveStats?) -> [[CLLocationCoordinate2D]] {
        guard let stats else { return [] }
        return stats.waves.compactMap { wave in
            let lower = min(wave.startIndex, wave.endIndex)
            let upper = max(wave.startIndex, wave.endIndex)
            guard samples.indices.contains(lower), samples.indices.contains(upper) else { return nil }
            let slice = Array(samples[lower...upper])
            let simplified = RouteDisplaySimplifier.simplified(
                samples: slice,
                maxPoints: 80,
                minSpacingMeters: 6
            )
            return simplified.count >= 2 ? RouteDisplaySimplifier.coordinates(simplified) : nil
        }
    }

    private func fitCamera() {
        let region = SpotMapRegion.fittedRegion(for: displayCoordinates) ?? SpotMapRegion.wideDefault
        var transaction = Transaction()
        if reduceMotion {
            transaction.disablesAnimations = true
        }
        withTransaction(transaction) {
            cameraPosition = .region(region)
        }
    }
}

/// Thins a GPS track for MapKit without changing WaveAnalyzer's input.
enum RouteDisplaySimplifier {
    static let defaultMaxPoints = 400
    static let defaultMinSpacingMeters = 10.0

    static func simplified(
        samples: [RouteSample],
        maxPoints: Int = defaultMaxPoints,
        minSpacingMeters: Double = defaultMinSpacingMeters
    ) -> [RouteSample] {
        guard samples.count > 2 else { return samples }
        let spacing = max(0, minSpacingMeters)
        var kept: [RouteSample] = [samples[0]]
        kept.reserveCapacity(min(samples.count, max(maxPoints, 2)))
        for sample in samples.dropFirst().dropLast() {
            if let last = kept.last, distanceMeters(last, sample) >= spacing {
                kept.append(sample)
            }
        }
        if let last = samples.last {
            kept.append(last)
        }
        guard kept.count > maxPoints, maxPoints >= 2 else { return kept }

        let lastIndex = kept.count - 1
        var out: [RouteSample] = []
        out.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = i == maxPoints - 1
                ? lastIndex
                : Int((Double(i) * Double(lastIndex) / Double(maxPoints - 1)).rounded())
            if let previous = out.last,
               previous.latitude == kept[idx].latitude,
               previous.longitude == kept[idx].longitude {
                continue
            }
            out.append(kept[idx])
        }
        return out
    }

    static func coordinates(_ samples: [RouteSample]) -> [CLLocationCoordinate2D] {
        samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Equirectangular metres — close enough at surf-session scale to drop
    /// duplicate GPS jitter without a haversine.
    static func distanceMeters(_ a: RouteSample, _ b: RouteSample) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let x = dLon * cos((lat1 + lat2) / 2)
        let y = dLat
        return sqrt(x * x + y * y) * 6_371_000
    }
}
