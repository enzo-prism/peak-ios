import CoreLocation
import MapKit
import SwiftUI

/// Transient GPS overlay for a Health-linked session. Coordinates live only in
/// memory for the lifetime of this view — they are never written to the store.
struct SessionRouteMapView: View {
    let workoutID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var samples: [RouteSample] = []
    @State private var stats: WaveStats?
    @State private var didLoad = false
    @State private var cameraPosition: MapCameraPosition = .region(SpotMapRegion.wideDefault)

    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if coordinates.count >= 2 {
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
                MapPolyline(coordinates: coordinates)
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

    private var coordinates: [CLLocationCoordinate2D] {
        samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Each detected ride, sliced from the original sample array via the
    /// segment's `startIndex`/`endIndex`. Indices are ordered in time, not
    /// necessarily numerically, so the range is always `min...max`.
    private var waveCoordinateSets: [[CLLocationCoordinate2D]] {
        guard let stats else { return [] }
        return stats.waves.compactMap { wave in
            let lower = min(wave.startIndex, wave.endIndex)
            let upper = max(wave.startIndex, wave.endIndex)
            guard samples.indices.contains(lower), samples.indices.contains(upper) else { return nil }
            let coords = samples[lower...upper].map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            return coords.count >= 2 ? coords : nil
        }
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
        samples = loaded
        if loaded.count >= 2 {
            stats = await WaveAnalyzer.analyzeOffMain(samples: loaded)
        }
        fitCamera()
        didLoad = true
    }

    private func fitCamera() {
        let region = SpotMapRegion.fittedRegion(for: coordinates) ?? SpotMapRegion.wideDefault
        var transaction = Transaction()
        if reduceMotion {
            transaction.disablesAnimations = true
        }
        withTransaction(transaction) {
            cameraPosition = .region(region)
        }
    }
}
