import Charts
import CoreLocation
import MapKit
import SwiftUI

/// Transient GPS overlay for a Health-linked session. Coordinates live only in
/// memory for the lifetime of this view — they are never written to the store.
struct SessionRouteMapView: View {
    let workoutID: String
    var correctEstimates: () -> Void = {}
    @State private var routeSamples: [RouteSample] = []
    @State private var routeTracks: [[CLLocationCoordinate2D]] = []
    @State private var selectedRide = 0
    @State private var scrubber = 0.0
    @State private var hiddenRides = Set<Int>()
    @State private var rideSamples: [RouteSample] = []
    @State private var rideTracks: [[RouteSample]] = []

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
            } else {
                Text("A GPS route is not available for this workout. Your saved session and editable estimates are unchanged.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
        .task {
            await load()
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                ForEach(routeTracks.indices, id: \.self) { index in
                    MapPolyline(coordinates: routeTracks[index])
                        .stroke(Theme.textMuted, lineWidth: 3)
                }
                ForEach(Array(waveCoordinateSets.enumerated()), id: \.offset) { _, coords in
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.surfGreen, lineWidth: 4)
                }
                if let sample = scrubbedSample {
                    Annotation("Selected GPS sample", coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)) {
                        Image(systemName: "circle.fill").foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)

            replayControls
            Button("Correct Saved Estimates", action: correctEstimates)
                .frame(minHeight: 44)
            Text("Estimated detections. GPS gaps are omitted. Hiding a detection changes this preview only; use Correct Saved Estimates to update your log.")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
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
            guard !Task.isCancelled else { return }
            routeSamples = loaded
            routeTracks = RouteReplay.tracks(loaded).map {
                RouteDisplaySimplifier.coordinates(RouteDisplaySimplifier.simplified(samples: $0))
            }
            displayCoordinates = RouteDisplaySimplifier.coordinates(
                RouteDisplaySimplifier.simplified(samples: loaded)
            )
            waveCoordinateSets = wavePolylines(from: loaded, stats: stats)
            prepareRide()
            fitCamera()
        }
        didLoad = true
    }

    private var selectedWave: WaveSegment? {
        guard let waves = stats?.waves, waves.indices.contains(selectedRide) else { return nil }
        return waves[selectedRide]
    }

    private func prepareRide() {
        scrubber = 0
        rideSamples = selectedWave.map { RouteReplay.samples(for: $0, in: routeSamples) } ?? []
        rideTracks = RouteReplay.tracks(rideSamples)
    }

    private var scrubbedSample: RouteSample? {
        guard !rideSamples.isEmpty else { return nil }
        return rideSamples[min(Int(scrubber.rounded()), rideSamples.count - 1)]
    }

    @ViewBuilder private var replayControls: some View {
        if let waves = stats?.waves, !waves.isEmpty {
            Picker("Estimated ride", selection: $selectedRide) {
                ForEach(waves.indices, id: \.self) { index in
                    Text("Ride \(index + 1)\(hiddenRides.contains(index) ? " · hidden" : "")").tag(index)
                }
            }
            .onChange(of: selectedRide) { _, _ in prepareRide() }
            if let wave = selectedWave {
                Text("\(Int(wave.durationSeconds.rounded())) seconds · \(SurfConditionsFormatter.meters(wave.distanceMeters)) · estimated")
                    .font(.subheadline)
                if rideSamples.count > 1 {
                    Slider(value: $scrubber, in: 0...Double(rideSamples.count - 1), step: 1) {
                        Text("Replay GPS samples")
                    }
                    .accessibilityValue(scrubbedSample?.timestamp.formatted(date: .omitted, time: .standard) ?? "")
                }
                if let sample = scrubbedSample {
                    Text("\(sample.timestamp.formatted(date: .omitted, time: .standard))\(sample.speedMetersPerSecond.flatMap { $0 >= 0 ? " · " + SurfConditionsFormatter.speed($0 * 3.6) + " GPS speed" : nil } ?? "")")
                        .font(.caption).monospacedDigit()
                }
                Chart {
                    ForEach(Array(rideTracks.enumerated()), id: \.offset) { index, track in
                        ForEach(Array(track.enumerated()), id: \.offset) { _, sample in
                            if let speed = sample.speedMetersPerSecond, speed >= 0, speed.isFinite {
                                LineMark(x: .value("Time", sample.timestamp), y: .value("GPS speed (km/h)", speed * 3.6), series: .value("Track", index))
                            }
                        }
                    }
                }
                .frame(height: 110)
                .accessibilityLabel("GPS speed during the selected estimated ride, in kilometers per hour")
                Button(hiddenRides.contains(selectedRide) ? "Restore Detection in Preview" : "Hide Detection in Preview") {
                    if hiddenRides.contains(selectedRide) { hiddenRides.remove(selectedRide) }
                    else { hiddenRides.insert(selectedRide) }
                    waveCoordinateSets = wavePolylines(from: routeSamples, stats: stats)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private func wavePolylines(from samples: [RouteSample], stats: WaveStats?) -> [[CLLocationCoordinate2D]] {
        guard let stats else { return [] }
        return stats.waves.enumerated().filter { !hiddenRides.contains($0.offset) }.flatMap { _, wave in
            RouteReplay.tracks(RouteReplay.samples(for: wave, in: samples)).map {
                RouteDisplaySimplifier.coordinates(RouteDisplaySimplifier.simplified(samples: $0, maxPoints: 80, minSpacingMeters: 6))
            }
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
