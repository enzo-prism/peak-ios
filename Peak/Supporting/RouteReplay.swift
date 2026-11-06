import Foundation

nonisolated enum RouteReplay {
    /// Break lines at missing/bad fixes, rather than drawing a fabricated path
    /// across a GPS gap. Sorting is for display only; analyzer indices stay intact.
    static func tracks(_ samples: [RouteSample], maxGap: TimeInterval = 5) -> [[RouteSample]] {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        var tracks: [[RouteSample]] = []
        var current: [RouteSample] = []
        for sample in ordered {
            let valid = sample.latitude.isFinite && sample.longitude.isFinite
                && (-90...90).contains(sample.latitude) && (-180...180).contains(sample.longitude)
                && sample.horizontalAccuracyMeters >= 0 && sample.horizontalAccuracyMeters <= 20
            let gap = current.last.map { sample.timestamp.timeIntervalSince($0.timestamp) } ?? 0
            if !valid || gap > maxGap {
                if current.count >= 2 { tracks.append(current) }
                current = []
            }
            if valid { current.append(sample) }
        }
        if current.count >= 2 { tracks.append(current) }
        return tracks
    }

    static func samples(for wave: WaveSegment, in samples: [RouteSample]) -> [RouteSample] {
        samples.filter { $0.timestamp >= wave.startTime && $0.timestamp <= wave.endTime }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
