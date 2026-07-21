//
//  Synthetic surf-route fixtures for the WaveAnalyzer suite.
//
//  Ported verbatim from the standalone validation package. CI never touches
//  HealthKit or a real device, so every analyzer test runs against routes
//  scripted here: the generator integrates a surfer's *true* trajectory exactly
//  and applies GPS error only to the emitted coordinate, which is how real fix
//  error behaves (it does not accumulate into the path).
//

import Foundation
@testable import Peak

// MARK: - Deterministic randomness

/// xorshift64* PRNG.
///
/// The analyzer must be deterministic, so every bit of randomness in the test
/// fixtures is explicitly seeded here. Foundation's `random` APIs are avoided
/// entirely: a test that fails one run in fifty is worse than no test.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        // Zero is a fixed point of xorshift, so map it away.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    /// Uniform in [0, 1).
    mutating func nextUniform() -> Double {
        Double(nextUInt64() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Standard normal via Box–Muller.
    mutating func nextGaussian() -> Double {
        // Guard the log against exactly 0.
        let u1 = max(nextUniform(), 1e-12)
        let u2 = nextUniform()
        return (-2 * Foundation.log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - Scripted session

/// One scripted stretch of surfer behaviour.
enum RoutePhase {
    /// Sitting on the board waiting: essentially stationary, slow random drift.
    case sit(seconds: Double)
    /// Paddling at a steady speed on a steady heading.
    case paddle(seconds: Double, speedMetersPerSecond: Double, headingDegrees: Double)
    /// Riding a wave: trapezoidal speed profile peaking at `peakSpeed`.
    case ride(seconds: Double, peakSpeedMetersPerSecond: Double, headingDegrees: Double)
    /// Time passes and the surfer moves, but the watch produces no fixes.
    /// Models submersion — a wipeout, a duck dive, an arm underwater.
    case dropout(seconds: Double, speedMetersPerSecond: Double, headingDegrees: Double)
}

struct GeneratorOptions {
    /// Nominal fix cadence. Apple Watch workouts are ~1 Hz.
    var sampleIntervalSeconds: Double = 1.0
    /// Standard deviation of the per-fix position error, metres.
    var positionNoiseSigmaMeters: Double = 0
    /// Emit a device speed value (as a real watch does) or leave it nil so the
    /// analyzer must derive speed geometrically.
    var providesDeviceSpeed: Bool = true
    /// Noise added to the device speed value, m/s.
    var deviceSpeedNoiseSigma: Double = 0
    /// Emit a device course value or leave it nil.
    var providesCourse: Bool = true
    /// Noise added to the device course value, degrees.
    var courseNoiseSigmaDegrees: Double = 0
    /// Reported horizontal accuracy for normal fixes.
    var horizontalAccuracyMeters: Double = 5
    /// Every Nth emitted fix gets `badAccuracyMeters` instead. nil disables.
    var badAccuracyEveryNSamples: Int?
    var badAccuracyMeters: Double = 65
    var seed: UInt64 = 0xC0FFEE

    init() {}
}

enum RouteGenerator {
    /// Metres per degree of latitude — flat-Earth conversion, exact enough over
    /// the few hundred metres a surf session spans.
    private static let metersPerDegreeLatitude = 111_320.0

    /// Renders a scripted session into route samples.
    ///
    /// The surfer's *true* position is integrated exactly; noise is applied only
    /// to the emitted coordinate, which is how GPS error actually works (the
    /// error does not accumulate into the trajectory).
    static func generate(
        phases: [RoutePhase],
        options: GeneratorOptions = GeneratorOptions(),
        startDate: Date = Date(timeIntervalSinceReferenceDate: 700_000_000),
        originLatitude: Double = 21.2761,      // Waikiki, roughly
        originLongitude: Double = -157.8267
    ) -> [RouteSample] {
        var rng = SeededRandom(seed: options.seed)
        var samples: [RouteSample] = []

        var east = 0.0          // metres from origin
        var north = 0.0
        var elapsed = 0.0
        var emitted = 0

        let interval = max(0.05, options.sampleIntervalSeconds)
        let lonScale = metersPerDegreeLatitude * cos(originLatitude * .pi / 180)

        /// Advances the true position and, unless suppressed, emits a fix.
        func step(speed: Double, heading: Double, emit: Bool, courseIsMeaningful: Bool) {
            let radians = heading * .pi / 180
            east += speed * sin(radians) * interval
            north += speed * cos(radians) * interval
            elapsed += interval
            guard emit else { return }

            let noiseEast = options.positionNoiseSigmaMeters > 0
                ? rng.nextGaussian() * options.positionNoiseSigmaMeters : 0
            let noiseNorth = options.positionNoiseSigmaMeters > 0
                ? rng.nextGaussian() * options.positionNoiseSigmaMeters : 0

            let latitude = originLatitude + (north + noiseNorth) / metersPerDegreeLatitude
            let longitude = originLongitude + (east + noiseEast) / lonScale

            var deviceSpeed: Double?
            if options.providesDeviceSpeed {
                let noisy = speed + (options.deviceSpeedNoiseSigma > 0
                    ? rng.nextGaussian() * options.deviceSpeedNoiseSigma : 0)
                deviceSpeed = max(0, noisy)
            }

            var course: Double?
            if options.providesCourse && courseIsMeaningful {
                let noisy = heading + (options.courseNoiseSigmaDegrees > 0
                    ? rng.nextGaussian() * options.courseNoiseSigmaDegrees : 0)
                course = (noisy.truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360)
            }

            var accuracy = options.horizontalAccuracyMeters
            if let every = options.badAccuracyEveryNSamples, every > 0, emitted % every == every - 1 {
                accuracy = options.badAccuracyMeters
            }

            samples.append(RouteSample(
                timestamp: startDate.addingTimeInterval(elapsed),
                latitude: latitude,
                longitude: longitude,
                speedMetersPerSecond: deviceSpeed,
                horizontalAccuracyMeters: accuracy,
                courseDegrees: course
            ))
            emitted += 1
        }

        for phase in phases {
            switch phase {
            case .sit(let seconds):
                for _ in 0..<stepCount(seconds, interval) {
                    // Drift: near-zero speed on a heading that wanders, which is
                    // what a board bobbing on a swell looks like to a GPS.
                    let drift = 0.05 + rng.nextUniform() * 0.15
                    let heading = rng.nextUniform() * 360
                    step(speed: drift, heading: heading, emit: true, courseIsMeaningful: false)
                }

            case .paddle(let seconds, let speed, let heading):
                for _ in 0..<stepCount(seconds, interval) {
                    step(speed: speed, heading: heading, emit: true, courseIsMeaningful: true)
                }

            case .ride(let seconds, let peak, let heading):
                let count = stepCount(seconds, interval)
                for i in 0..<count {
                    let t = Double(i) * interval
                    step(
                        speed: rideSpeed(at: t, duration: seconds, peak: peak),
                        heading: heading,
                        emit: true,
                        courseIsMeaningful: true
                    )
                }

            case .dropout(let seconds, let speed, let heading):
                for _ in 0..<stepCount(seconds, interval) {
                    step(speed: speed, heading: heading, emit: false, courseIsMeaningful: true)
                }
            }
        }

        return samples
    }

    private static func stepCount(_ seconds: Double, _ interval: Double) -> Int {
        max(0, Int((max(0, seconds) / interval).rounded()))
    }

    /// Trapezoidal ride profile: a fast drop-in, a sustained plateau, then a
    /// decay as the wave closes out. Real GPS traces of rides look like this.
    private static func rideSpeed(at t: Double, duration: Double, peak: Double) -> Double {
        let rampUp = min(1.0, duration * 0.15)
        let rampDown = min(1.5, duration * 0.25)
        let plateauEnd = max(rampUp, duration - rampDown)

        if t < rampUp, rampUp > 0 {
            return peak * (0.55 + 0.45 * (t / rampUp))
        }
        if t >= plateauEnd, duration > plateauEnd {
            let progress = min(1, (t - plateauEnd) / max(0.001, duration - plateauEnd))
            return peak * (1.0 - 0.6 * progress)
        }
        return peak
    }
}

// MARK: - Fixture helpers

extension RouteGenerator {
    /// Injects a one-sample speed spike, as a partially-obstructed fix produces.
    static func injectingSpeedSpike(
        _ samples: [RouteSample],
        at index: Int,
        speedMetersPerSecond: Double
    ) -> [RouteSample] {
        guard samples.indices.contains(index) else { return samples }
        var copy = samples
        copy[index].speedMetersPerSecond = speedMetersPerSecond
        return copy
    }

    /// Displaces a single fix, as a multipath reflection off a wave face does.
    static func injectingPositionSpike(
        _ samples: [RouteSample],
        at index: Int,
        offsetMeters: Double,
        headingDegrees: Double = 0
    ) -> [RouteSample] {
        guard samples.indices.contains(index) else { return samples }
        var copy = samples
        let radians = headingDegrees * .pi / 180
        let lonScale = metersPerDegreeLatitude * cos(copy[index].latitude * .pi / 180)
        copy[index].latitude += offsetMeters * cos(radians) / metersPerDegreeLatitude
        copy[index].longitude += offsetMeters * sin(radians) / lonScale
        return copy
    }
}
