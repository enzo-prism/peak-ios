import XCTest
@testable import Peak

// MARK: - Shared helpers

private let referenceStart = Date(timeIntervalSinceReferenceDate: 700_000_000)

/// Asserts the statistics contain no NaN or infinity anywhere. Every test that
/// produces stats runs this, because a single NaN leaking into a UI label is
/// the kind of bug that only shows up in the App Store reviews.
private func assertAllFinite(
    _ stats: WaveStats,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(stats.topSpeedKph.isFinite, "topSpeedKph not finite", file: file, line: line)
    XCTAssertTrue(stats.longestRideSeconds.isFinite, "longestRideSeconds not finite", file: file, line: line)
    XCTAssertTrue(stats.longestRideMeters.isFinite, "longestRideMeters not finite", file: file, line: line)
    XCTAssertTrue(stats.paddleDistanceMeters.isFinite, "paddleDistanceMeters not finite", file: file, line: line)
    XCTAssertTrue(stats.totalDistanceMeters.isFinite, "totalDistanceMeters not finite", file: file, line: line)
    XCTAssertGreaterThanOrEqual(stats.topSpeedKph, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(stats.paddleDistanceMeters, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(stats.totalDistanceMeters, 0, file: file, line: line)
    for wave in stats.waves {
        XCTAssertTrue(wave.peakSpeedMetersPerSecond.isFinite, "wave peak not finite", file: file, line: line)
        XCTAssertTrue(wave.distanceMeters.isFinite, "wave distance not finite", file: file, line: line)
        XCTAssertTrue(wave.durationSeconds.isFinite, "wave duration not finite", file: file, line: line)
        XCTAssertGreaterThanOrEqual(wave.durationSeconds, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(wave.distanceMeters, 0, file: file, line: line)
    }
}

/// Asserts the algebraic relationships that must hold for any session at all,
/// regardless of what the surfer did.
private func assertInvariants(
    _ stats: WaveStats,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertAllFinite(stats, file: file, line: line)

    XCTAssertEqual(stats.waveCount, stats.waves.count, file: file, line: line)

    let waveDistance = stats.waves.reduce(0) { $0 + $1.distanceMeters }
    XCTAssertLessThanOrEqual(
        stats.paddleDistanceMeters + waveDistance,
        stats.totalDistanceMeters + 1e-6,
        "paddle + wave distance must be a subset of total distance",
        file: file, line: line
    )

    for wave in stats.waves {
        XCTAssertLessThanOrEqual(
            wave.peakSpeedMetersPerSecond, stats.topSpeedKph / 3.6 + 1e-9,
            "top speed must dominate every segment peak",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            wave.distanceMeters, stats.totalDistanceMeters + 1e-6,
            file: file, line: line
        )
        // Note: index ordering is only guaranteed for chronologically-ordered
        // input, since start/end mean earliest/latest in *time*. Time ordering
        // is guaranteed unconditionally.
        XCTAssertLessThanOrEqual(wave.startTime, wave.endTime, file: file, line: line)
    }

    if stats.waves.isEmpty {
        XCTAssertEqual(stats.longestRideSeconds, 0, file: file, line: line)
        XCTAssertEqual(stats.longestRideMeters, 0, file: file, line: line)
    } else {
        let longest = stats.waves.map(\.durationSeconds).max() ?? 0
        XCTAssertEqual(stats.longestRideSeconds, longest, accuracy: 1e-9, file: file, line: line)
    }
}

/// A representative three-wave session used by several tests.
/// Offshore paddling heads 270°, rides head 90° toward the beach.
private let threeWaveScript: [RoutePhase] = [
    .sit(seconds: 25),
    .paddle(seconds: 45, speedMetersPerSecond: 1.4, headingDegrees: 270),
    .sit(seconds: 35),
    .paddle(seconds: 6, speedMetersPerSecond: 1.4, headingDegrees: 90),
    .ride(seconds: 9, peakSpeedMetersPerSecond: 6.0, headingDegrees: 95),
    .paddle(seconds: 40, speedMetersPerSecond: 1.3, headingDegrees: 270),
    .sit(seconds: 50),
    .paddle(seconds: 6, speedMetersPerSecond: 1.4, headingDegrees: 90),
    .ride(seconds: 13, peakSpeedMetersPerSecond: 5.4, headingDegrees: 85),
    .paddle(seconds: 45, speedMetersPerSecond: 1.3, headingDegrees: 270),
    .sit(seconds: 40),
    .paddle(seconds: 6, speedMetersPerSecond: 1.4, headingDegrees: 90),
    .ride(seconds: 6, peakSpeedMetersPerSecond: 4.6, headingDegrees: 100),
    .paddle(seconds: 30, speedMetersPerSecond: 1.3, headingDegrees: 270),
    .sit(seconds: 20)
]

// MARK: - Group 1: clean synthetic sessions

final class CleanSessionTests: XCTestCase {

    func testThreeWaveSessionCountsExactly() {
        let samples = RouteGenerator.generate(phases: threeWaveScript)
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 3)
        assertInvariants(stats)
    }

    func testSingleWaveSessionCountsExactly() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 60, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 10, peakSpeedMetersPerSecond: 5.5, headingDegrees: 90),
            .paddle(seconds: 60, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 1)
        assertInvariants(stats)
    }

    func testTopSpeedTracksFastestRide() {
        let samples = RouteGenerator.generate(phases: threeWaveScript)
        let stats = WaveAnalyzer.analyze(samples: samples)

        // Fastest scripted ride peaks at 6.0 m/s = 21.6 km/h. Smoothing shaves a
        // little off the peak, so allow a modest downward tolerance but no
        // meaningful overshoot.
        XCTAssertGreaterThan(stats.topSpeedKph, 18.0)
        XCTAssertLessThan(stats.topSpeedKph, 22.5)
    }

    func testRideDistanceMatchesScriptedPhysics() {
        // A 10 s ride whose profile averages roughly 0.85 × peak covers ~47 m at
        // 5.5 m/s peak. Anything wildly outside that band means distance is being
        // accumulated from the wrong links.
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 10, peakSpeedMetersPerSecond: 5.5, headingDegrees: 90),
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 1)
        let wave = try? XCTUnwrap(stats.waves.first)
        XCTAssertNotNil(wave)
        XCTAssertGreaterThan(stats.longestRideMeters, 30)
        XCTAssertLessThan(stats.longestRideMeters, 70)
    }

    func testPaddleDistanceIsAccumulated() {
        // 120 s of paddling at 1.4 m/s ≈ 168 m, plus a little from ride ramps.
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 120, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        XCTAssertGreaterThan(stats.paddleDistanceMeters, 150)
        XCTAssertLessThan(stats.paddleDistanceMeters, 185)
        assertInvariants(stats)
    }

    func testSittingProducesAlmostNoPaddleDistance() {
        // Drift while waiting is below the stationary floor, so it must not be
        // reported as paddling: a 10-minute wait would otherwise invent ~90 m.
        let samples = RouteGenerator.generate(phases: [.sit(seconds: 600)])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        XCTAssertLessThan(stats.paddleDistanceMeters, 10)
        assertInvariants(stats)
    }
}

// MARK: - Group 2: GPS noise

final class NoisySessionTests: XCTestCase {

    /// Realistic watch behaviour: noisy positions, but a usable device speed and
    /// course (both Doppler-derived, so far cleaner than differential position).
    func testThreeWaveSessionWithFourMetreNoise() {
        var options = GeneratorOptions()
        options.positionNoiseSigmaMeters = 4
        options.deviceSpeedNoiseSigma = 0.4
        options.courseNoiseSigmaDegrees = 12
        options.horizontalAccuracyMeters = 8

        let samples = RouteGenerator.generate(phases: threeWaveScript, options: options)
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 3, "expected exact count with device speed available")
        assertInvariants(stats)
    }

    /// A deterministic, reasonably-sized seed set. Detection under noise is a
    /// statistical question, so the tests below assert *rates* over many
    /// fixtures rather than outcomes on a handful of hand-picked seeds — which
    /// is how an algorithm ends up tuned to its own test data.
    private static let sweepSeeds: [UInt64] = (1...60).map { UInt64($0 &* 2_654_435_761) }

    /// Runs the three-wave script across every seed and returns how often the
    /// count landed exactly right, and how often it landed within one.
    private func sweepAccuracy(
        options build: (inout GeneratorOptions) -> Void
    ) -> (exact: Int, withinOne: Int, worstError: Int, total: Int) {
        var exact = 0, withinOne = 0, worst = 0
        for seed in Self.sweepSeeds {
            var options = GeneratorOptions()
            options.seed = seed
            build(&options)

            let stats = WaveAnalyzer.analyze(
                samples: RouteGenerator.generate(phases: threeWaveScript, options: options)
            )
            assertInvariants(stats)

            let error = abs(stats.waveCount - 3)
            if error == 0 { exact += 1 }
            if error <= 1 { withinOne += 1 }
            worst = max(worst, error)
        }
        return (exact, withinOne, worst, Self.sweepSeeds.count)
    }

    /// Realistic watch noise: σ = 3 m positions with a usable device speed.
    func testNoiseSweepDeviceSpeedThreeMetres() {
        let result = sweepAccuracy {
            $0.positionNoiseSigmaMeters = 3
            $0.deviceSpeedNoiseSigma = 0.5
            $0.courseNoiseSigmaDegrees = 15
            $0.horizontalAccuracyMeters = 8
        }
        XCTAssertGreaterThanOrEqual(result.withinOne, 57, "within-±1 rate regressed: \(result)")
        XCTAssertGreaterThanOrEqual(result.exact, 42, "exact-match rate regressed: \(result)")
    }

    /// Pessimistic watch noise: σ = 5 m positions *and* 0.8 m/s of speed noise,
    /// which is worse than an Apple Watch's Doppler speed actually is.
    func testNoiseSweepDeviceSpeedFiveMetres() {
        let result = sweepAccuracy {
            $0.positionNoiseSigmaMeters = 5
            $0.deviceSpeedNoiseSigma = 0.8
            $0.courseNoiseSigmaDegrees = 25
            $0.horizontalAccuracyMeters = 12
        }
        XCTAssertGreaterThanOrEqual(result.withinOne, 51, "within-±1 rate regressed: \(result)")
        XCTAssertLessThanOrEqual(result.worstError, 2, "a session was off by more than two waves")
    }

    /// The hard case: no device speed and no course at all, so every speed and
    /// heading is differentiated from noisy positions. This is where naive
    /// implementations invent waves out of jitter.
    func testNoiseSweepDerivedSpeedOnly() {
        let result = sweepAccuracy {
            $0.providesDeviceSpeed = false
            $0.providesCourse = false
            $0.positionNoiseSigmaMeters = 3
            $0.horizontalAccuracyMeters = 7
        }
        XCTAssertEqual(result.withinOne, result.total, "derived-only σ=3 must always land within one: \(result)")
        XCTAssertGreaterThanOrEqual(result.exact, 36, "exact-match rate regressed: \(result)")
    }

    func testNoiseSweepDerivedSpeedFourMetres() {
        let result = sweepAccuracy {
            $0.providesDeviceSpeed = false
            $0.providesCourse = false
            $0.positionNoiseSigmaMeters = 4
            $0.horizontalAccuracyMeters = 9
        }
        XCTAssertGreaterThanOrEqual(result.withinOne, 55, "within-±1 rate regressed: \(result)")
    }

    /// A long wait with no waves at all, using derived speed. Position noise
    /// alone must not manufacture rides — this is the phantom-wave regression,
    /// and the one that matters most: an invented wave is a visible lie in the
    /// UI, whereas a missed marginal one is only a small undercount.
    func testDerivedSpeedSittingProducesNoWaves() {
        var sessionsWithPhantoms = 0
        for seed in Self.sweepSeeds {
            var options = GeneratorOptions()
            options.providesDeviceSpeed = false
            options.providesCourse = false
            options.positionNoiseSigmaMeters = 4
            options.horizontalAccuracyMeters = 10
            options.seed = seed

            let stats = WaveAnalyzer.analyze(
                samples: RouteGenerator.generate(phases: [.sit(seconds: 900)], options: options)
            )
            assertInvariants(stats)
            if stats.waveCount > 0 { sessionsWithPhantoms += 1 }
        }
        // 15 minutes of sitting per session, 60 sessions. A couple of marginal
        // false positives at σ = 4 m with no device speed at all is the known
        // limit of the method; a regression here would show up as many.
        XCTAssertLessThanOrEqual(
            sessionsWithPhantoms, 2,
            "\(sessionsWithPhantoms)/60 sitting sessions invented a wave"
        )
    }

    /// With a device speed available — the normal case — sitting must never
    /// produce a wave at any noise level in the realistic band.
    func testDeviceSpeedSittingNeverProducesWaves() {
        for seed in Self.sweepSeeds {
            var options = GeneratorOptions()
            options.positionNoiseSigmaMeters = 5
            options.deviceSpeedNoiseSigma = 0.5
            options.horizontalAccuracyMeters = 12
            options.seed = seed

            let stats = WaveAnalyzer.analyze(
                samples: RouteGenerator.generate(phases: [.sit(seconds: 900)], options: options)
            )
            XCTAssertEqual(stats.waveCount, 0, "seed=\(seed) invented a wave while sitting")
        }
    }

    /// Low-accuracy fixes are dropped, which widens the effective sampling
    /// interval. Detection must survive that without inventing distance.
    func testPeriodicLowAccuracyFixesAreDroppedSafely() {
        var options = GeneratorOptions()
        options.positionNoiseSigmaMeters = 3
        options.badAccuracyEveryNSamples = 4
        options.badAccuracyMeters = 80

        let samples = RouteGenerator.generate(phases: threeWaveScript, options: options)
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertLessThanOrEqual(abs(stats.waveCount - 3), 1)
        assertInvariants(stats)
    }

    func testNegativeAccuracyFixesAreDropped() {
        var samples = RouteGenerator.generate(phases: threeWaveScript)
        for index in stride(from: 0, to: samples.count, by: 5) {
            samples[index].horizontalAccuracyMeters = -1   // CoreLocation "invalid"
        }
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertLessThanOrEqual(abs(stats.waveCount - 3), 1)
        assertInvariants(stats)
    }
}

// MARK: - Group 3: dropouts and gaps

final class DropoutTests: XCTestCase {

    /// The headline bug this algorithm exists to prevent: a long submersion
    /// between two fixes must not be logged as a straight-line sprint.
    func testLongDropoutDoesNotInflateDistance() {
        let withoutGap = RouteGenerator.generate(phases: [
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 8, peakSpeedMetersPerSecond: 6.0, headingDegrees: 90),
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let withGap = RouteGenerator.generate(phases: [
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 8, peakSpeedMetersPerSecond: 6.0, headingDegrees: 90),
            // Wipeout: 40 s underwater, carried 100 m by the current/whitewater.
            .dropout(seconds: 40, speedMetersPerSecond: 2.5, headingDegrees: 90),
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])

        let gapless = WaveAnalyzer.analyze(samples: withoutGap)
        let gapped = WaveAnalyzer.analyze(samples: withGap)

        // The 100 m travelled while submerged is unobserved and must not appear.
        XCTAssertEqual(gapped.totalDistanceMeters, gapless.totalDistanceMeters, accuracy: 5.0)
        XCTAssertEqual(gapped.waveCount, 1)
        assertInvariants(gapped)
    }

    /// A dropout in the *middle* of a ride terminates it. The ride must be
    /// reported at its observed length, not extended across the blackout.
    func testDropoutMidRideDoesNotProduceAbsurdRideDistance() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 6, peakSpeedMetersPerSecond: 6.0, headingDegrees: 90),
            .dropout(seconds: 25, speedMetersPerSecond: 6.0, headingDegrees: 90),
            .ride(seconds: 6, peakSpeedMetersPerSecond: 6.0, headingDegrees: 90),
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        assertInvariants(stats)
        for wave in stats.waves {
            // No ride may claim more ground than its own peak speed could have
            // covered in its own duration. This is the "40 ft logged as 350 ft"
            // guard, expressed as a physical bound.
            let bound = wave.peakSpeedMetersPerSecond * wave.durationSeconds * 1.15 + 5
            XCTAssertLessThanOrEqual(
                wave.distanceMeters, bound,
                "ride distance \(wave.distanceMeters) m exceeds what \(wave.peakSpeedMetersPerSecond) m/s allows"
            )
        }
    }

    /// Many short bursts of fixes separated by blackouts, all while sitting.
    /// Classic submerged-wrist pattern; must yield nothing.
    func testIntermittentFixesWhileSittingProduceNoPhantomWaves() {
        var phases: [RoutePhase] = []
        for _ in 0..<20 {
            phases.append(.sit(seconds: 4))
            phases.append(.dropout(seconds: 12, speedMetersPerSecond: 0.6, headingDegrees: 180))
        }
        var options = GeneratorOptions()
        options.providesDeviceSpeed = false
        options.providesCourse = false
        options.positionNoiseSigmaMeters = 4
        options.seed = 606

        let samples = RouteGenerator.generate(phases: phases, options: options)
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    /// Short gaps (within the bridge window) must NOT break a ride apart.
    func testShortGapsAreBridgedWithinARide() {
        var samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 14, peakSpeedMetersPerSecond: 6.0, headingDegrees: 90),
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        // Punch two single-sample holes out of the middle of the ride.
        let rideStart = 31
        samples.remove(at: rideStart + 6)
        samples.remove(at: rideStart + 3)

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 1, "a 2 s hole must not split one wave into two")
        assertInvariants(stats)
    }

    /// A teleport between consecutive fixes (implied speed far beyond anything
    /// physical) must be excluded from distance entirely.
    func testTeleportLinkIsExcludedFromDistance() {
        var samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 40, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let clean = WaveAnalyzer.analyze(samples: samples)

        // Shift the entire tail 500 m north: one impossible link, then normal
        // paddling again.
        for index in 20..<samples.count {
            samples[index].latitude += 500 / 111_320.0
        }
        let teleported = WaveAnalyzer.analyze(samples: samples)

        XCTAssertLessThan(
            teleported.totalDistanceMeters, clean.totalDistanceMeters + 20,
            "a 500 m teleport was counted as travel"
        )
        XCTAssertEqual(teleported.waveCount, 0)
        assertInvariants(teleported)
    }
}

// MARK: - Group 4: spikes

final class SpikeRejectionTests: XCTestCase {

    func testSingleSampleDeviceSpeedSpikeDuringPaddlingIsIgnored() {
        let base = RouteGenerator.generate(phases: [
            .paddle(seconds: 120, speedMetersPerSecond: 1.5, headingDegrees: 270)
        ])
        let samples = RouteGenerator.injectingSpeedSpike(base, at: 60, speedMetersPerSecond: 9.0)
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0, "one bad speed sample became a wave")
        assertInvariants(stats)
    }

    func testSingleSamplePositionSpikeDuringPaddlingIsIgnored() {
        for offset in [8.0, 12.0, 20.0, 35.0] {
            let base = RouteGenerator.generate(phases: [
                .paddle(seconds: 120, speedMetersPerSecond: 1.5, headingDegrees: 270)
            ])
            // No device speed: force the analyzer to differentiate the spiked
            // positions, which is the failure mode we are guarding.
            var options = GeneratorOptions()
            options.providesDeviceSpeed = false
            options.providesCourse = false
            let derived = RouteGenerator.generate(
                phases: [.paddle(seconds: 120, speedMetersPerSecond: 1.5, headingDegrees: 270)],
                options: options
            )
            _ = base

            let samples = RouteGenerator.injectingPositionSpike(
                derived, at: 60, offsetMeters: offset, headingDegrees: 30
            )
            let stats = WaveAnalyzer.analyze(samples: samples)

            XCTAssertEqual(
                stats.waveCount, 0,
                "a \(offset) m position spike became a wave"
            )
            assertInvariants(stats)
        }
    }

    /// Two consecutive bad fixes are past what a median-3 can remove, so the
    /// implausible-peak and directional gates have to catch it.
    func testDoubleSampleSpikeIsRejected() {
        var options = GeneratorOptions()
        options.providesDeviceSpeed = false
        options.providesCourse = false
        var samples = RouteGenerator.generate(
            phases: [.paddle(seconds: 120, speedMetersPerSecond: 1.5, headingDegrees: 270)],
            options: options
        )
        samples = RouteGenerator.injectingPositionSpike(samples, at: 60, offsetMeters: 18, headingDegrees: 40)
        samples = RouteGenerator.injectingPositionSpike(samples, at: 61, offsetMeters: 18, headingDegrees: 220)

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    /// An implausibly fast "ride" is a measurement fault, not an achievement.
    /// Here the *positions* themselves move at ~15.5 m/s in a dead straight
    /// line, so the segment is directionally consistent and only the
    /// plausibility ceiling can reject it.
    func testImplausiblyFastSegmentIsRejected() {
        var options = GeneratorOptions()
        options.providesDeviceSpeed = false
        options.providesCourse = false

        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 10, peakSpeedMetersPerSecond: 15.5, headingDegrees: 90),
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ], options: options)

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 0, "a 56 km/h 'ride' was accepted")
        XCTAssertLessThanOrEqual(stats.topSpeedKph, 14.0 * 3.6 + 1e-6)
        assertInvariants(stats)
    }

    /// A device speed outside the physical range is a broken measurement, not a
    /// veto on the whole segment: the analyzer falls back to the geometry, which
    /// still describes a perfectly ordinary wave.
    func testOutOfRangeDeviceSpeedFallsBackToGeometry() {
        var samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 10, peakSpeedMetersPerSecond: 6.0, headingDegrees: 90),
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        for index in 21..<30 { samples[index].speedMetersPerSecond = 30 }

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 1)
        XCTAssertLessThan(stats.topSpeedKph, 30.0, "the bogus 108 km/h reading leaked into top speed")
        assertInvariants(stats)
    }

    /// Speed spikes must never leak into the headline top-speed figure either.
    func testTopSpeedIgnoresImplausibleValues() {
        var samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 60, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        samples[30].speedMetersPerSecond = 400   // absurd
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertLessThan(stats.topSpeedKph, 20)
        assertInvariants(stats)
    }
}

// MARK: - Group 5: sessions with no waves

final class NoWaveSessionTests: XCTestCase {

    func testPureePaddlingSessionHasNoWaves() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 300, speedMetersPerSecond: 1.6, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        XCTAssertTrue(stats.waves.isEmpty)
        XCTAssertEqual(stats.longestRideSeconds, 0)
        XCTAssertEqual(stats.longestRideMeters, 0)
        XCTAssertGreaterThan(stats.paddleDistanceMeters, 400)
        assertInvariants(stats)
    }

    /// A strong paddler sprinting still sits below the wave threshold.
    func testHardPaddleSprintIsNotAWave() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 60, speedMetersPerSecond: 1.3, headingDegrees: 270),
            .paddle(seconds: 12, speedMetersPerSecond: 2.0, headingDegrees: 270),
            .paddle(seconds: 60, speedMetersPerSecond: 1.3, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    /// A burst that is fast enough but too brief is not a wave.
    func testTwoSecondBurstIsBelowMinimumDuration() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 40, speedMetersPerSecond: 1.3, headingDegrees: 270),
            .ride(seconds: 2, peakSpeedMetersPerSecond: 5.0, headingDegrees: 90),
            .paddle(seconds: 40, speedMetersPerSecond: 1.3, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    /// A brief touch of the entry threshold that then coasts along above the
    /// *exit* threshold must not qualify. Without the sustained-evidence rule
    /// the whole ride rests on one noisy sample, and the wave count grows with
    /// GPS noise instead of staying flat.
    func testBriefTouchOfEntryThresholdIsNotAWave() {
        let base = RouteGenerator.generate(phases: [
            .paddle(seconds: 60, speedMetersPerSecond: 1.8, headingDegrees: 270)
        ])
        // One sample pushed just over the entry threshold, on a plateau that
        // sits comfortably above the exit threshold.
        let samples = RouteGenerator.injectingSpeedSpike(base, at: 30, speedMetersPerSecond: 2.6)

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    /// A ride is required to contain enough fixes to be worth believing, not
    /// merely to span enough wall-clock time.
    func testTooFewFixesIsNotAWave() {
        let tuning = WaveAnalyzer.Tuning()
        let samples = RouteGenerator.generate(phases: [
            .ride(seconds: 8, peakSpeedMetersPerSecond: 6, headingDegrees: 90)
        ], options: {
            var options = GeneratorOptions()
            options.sampleIntervalSeconds = 4   // only 2 fixes across the ride
            return options
        }())

        XCTAssertLessThan(samples.count, tuning.minWaveSampleCount)
        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    func testEntireSessionSittingHasNoWaves() {
        let samples = RouteGenerator.generate(phases: [.sit(seconds: 1800)])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }
}

// MARK: - Group 6: degenerate input

final class DegenerateInputTests: XCTestCase {

    func testEmptyInput() {
        let stats = WaveAnalyzer.analyze(samples: [])
        XCTAssertEqual(stats, .zero)
        assertInvariants(stats)
    }

    func testSingleSampleInput() {
        let stats = WaveAnalyzer.analyze(samples: [
            RouteSample(timestamp: referenceStart, latitude: 21.27, longitude: -157.82,
                        speedMetersPerSecond: 5, horizontalAccuracyMeters: 5, courseDegrees: 90)
        ])
        XCTAssertEqual(stats, .zero)
        assertInvariants(stats)
    }

    func testAllFixesFailAccuracyGate() {
        var samples = RouteGenerator.generate(phases: threeWaveScript)
        for index in samples.indices { samples[index].horizontalAccuracyMeters = 250 }

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats, .zero)
        assertInvariants(stats)
    }

    func testAllFixesHaveInvalidNegativeAccuracy() {
        var samples = RouteGenerator.generate(phases: threeWaveScript)
        for index in samples.indices { samples[index].horizontalAccuracyMeters = -1 }

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats, .zero)
        assertInvariants(stats)
    }

    func testNonFiniteCoordinatesAreDiscarded() {
        var samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 40, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 10, peakSpeedMetersPerSecond: 5.5, headingDegrees: 90),
            .paddle(seconds: 40, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        samples[10].latitude = .nan
        samples[11].longitude = .infinity
        samples[12].latitude = -.infinity
        samples[13].horizontalAccuracyMeters = .nan
        samples[14].speedMetersPerSecond = .nan
        samples[15].courseDegrees = .nan

        let stats = WaveAnalyzer.analyze(samples: samples)
        assertInvariants(stats)
        XCTAssertEqual(stats.waveCount, 1)
    }

    func testAllSamplesShareOneTimestamp() {
        // Degenerate export: every fix stamped identically. Δt is zero
        // everywhere, so nothing is trusted and nothing may be reported.
        var samples = RouteGenerator.generate(phases: [
            .ride(seconds: 20, peakSpeedMetersPerSecond: 6, headingDegrees: 90)
        ])
        for index in samples.indices { samples[index].timestamp = referenceStart }

        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 0)
        XCTAssertEqual(stats.totalDistanceMeters, 0)
        assertInvariants(stats)
    }

    func testIdenticalCoordinatesProduceNoDistanceOrNaN() {
        // Zero displacement is the classic haversine NaN trap (acos/asin of a
        // value that rounds just past 1).
        let samples = (0..<50).map { index in
            RouteSample(
                timestamp: referenceStart.addingTimeInterval(Double(index)),
                latitude: 21.2761, longitude: -157.8267,
                speedMetersPerSecond: nil, horizontalAccuracyMeters: 5, courseDegrees: nil
            )
        }
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.totalDistanceMeters, 0, accuracy: 1e-9)
        XCTAssertEqual(stats.waveCount, 0)
        assertInvariants(stats)
    }

    func testOutOfOrderSamplesAreSorted() {
        let ordered = RouteGenerator.generate(phases: threeWaveScript)
        let reversed = Array(ordered.reversed())

        let a = WaveAnalyzer.analyze(samples: ordered)
        let b = WaveAnalyzer.analyze(samples: reversed)

        XCTAssertEqual(a.waveCount, b.waveCount)
        XCTAssertEqual(a.totalDistanceMeters, b.totalDistanceMeters, accuracy: 1e-6)
        XCTAssertEqual(a.topSpeedKph, b.topSpeedKph, accuracy: 1e-9)
        XCTAssertEqual(a.longestRideSeconds, b.longestRideSeconds, accuracy: 1e-9)
        assertInvariants(b)

        // Start/end are chronological, so reversing the input reverses the
        // numeric ordering of the reported indices without changing the times.
        for (forward, backward) in zip(a.waves, b.waves) {
            XCTAssertEqual(forward.startTime, backward.startTime)
            XCTAssertEqual(forward.endTime, backward.endTime)
            XCTAssertGreaterThan(backward.startIndex, backward.endIndex)
        }
    }

    func testAbsurdTuningDoesNotCrashOrEmitNaN() {
        var tuning = WaveAnalyzer.Tuning()
        tuning.maxHorizontalAccuracyMeters = .nan
        tuning.waveEnterSpeedMetersPerSecond = -5
        tuning.waveExitSpeedMetersPerSecond = 900
        tuning.medianWindowSamples = -4
        tuning.meanWindowSamples = 1000
        tuning.minWaveDurationSeconds = .infinity
        tuning.maxBridgeableGapSeconds = .nan
        tuning.minHeadingResultantLength = 12

        let samples = RouteGenerator.generate(phases: threeWaveScript)
        let stats = WaveAnalyzer.analyze(samples: samples, tuning: tuning)
        assertAllFinite(stats)
    }

    func testTwoSampleInputIsHandled() {
        let samples = [
            RouteSample(timestamp: referenceStart, latitude: 21.2761, longitude: -157.8267,
                        speedMetersPerSecond: 6, horizontalAccuracyMeters: 5, courseDegrees: 90),
            RouteSample(timestamp: referenceStart.addingTimeInterval(1), latitude: 21.2761,
                        longitude: -157.82664, speedMetersPerSecond: 6,
                        horizontalAccuracyMeters: 5, courseDegrees: 90)
        ]
        let stats = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(stats.waveCount, 0, "1 s of data cannot clear the 3 s minimum")
        assertInvariants(stats)
    }
}

// MARK: - Group 7: longest-ride selection

final class LongestRideTests: XCTestCase {

    func testLongestRideReflectsTheLongWaveNotTheShortOne() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 4, peakSpeedMetersPerSecond: 6.5, headingDegrees: 90),   // short, fast
            .paddle(seconds: 60, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 22, peakSpeedMetersPerSecond: 4.8, headingDegrees: 90),  // long, slower
            .paddle(seconds: 30, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 2)
        XCTAssertGreaterThan(stats.longestRideSeconds, 18)
        XCTAssertLessThan(stats.longestRideSeconds, 26)
        // ~22 s at an average near 4 m/s ≈ 90 m; the 4 s ride is nowhere near.
        XCTAssertGreaterThan(stats.longestRideMeters, 60)
        assertInvariants(stats)
    }

    func testLongestRideMetersBelongsToTheLongestRideByDuration() {
        let samples = RouteGenerator.generate(phases: [
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 5, peakSpeedMetersPerSecond: 7.0, headingDegrees: 90),
            .paddle(seconds: 40, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 18, peakSpeedMetersPerSecond: 5.0, headingDegrees: 90),
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])
        let stats = WaveAnalyzer.analyze(samples: samples)

        let longest = stats.waves.max { $0.durationSeconds < $1.durationSeconds }
        XCTAssertNotNil(longest)
        XCTAssertEqual(stats.longestRideSeconds, longest?.durationSeconds ?? -1, accuracy: 1e-9)
        XCTAssertEqual(stats.longestRideMeters, longest?.distanceMeters ?? -1, accuracy: 1e-9)
    }

    func testWavesAreReportedInChronologicalOrder() {
        let samples = RouteGenerator.generate(phases: threeWaveScript)
        let stats = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(stats.waveCount, 3)
        for (previous, next) in zip(stats.waves, stats.waves.dropFirst()) {
            XCTAssertLessThan(previous.endTime, next.startTime)
            XCTAssertLessThan(previous.endIndex, next.startIndex)
        }
    }

    func testWaveIndicesPointAtTheOriginalArray() {
        var samples = RouteGenerator.generate(phases: threeWaveScript)
        // Drop a scattering of fixes on accuracy so clean-indices and original
        // indices diverge; reported indices must still address the input array.
        for index in stride(from: 0, to: samples.count, by: 7) {
            samples[index].horizontalAccuracyMeters = 300
        }
        let stats = WaveAnalyzer.analyze(samples: samples)

        for wave in stats.waves {
            XCTAssertTrue(samples.indices.contains(wave.startIndex))
            XCTAssertTrue(samples.indices.contains(wave.endIndex))
            XCTAssertEqual(samples[wave.startIndex].timestamp, wave.startTime)
            XCTAssertEqual(samples[wave.endIndex].timestamp, wave.endTime)
            XCTAssertLessThanOrEqual(samples[wave.startIndex].horizontalAccuracyMeters, 20)
        }
    }
}

// MARK: - Group 8: determinism

final class DeterminismTests: XCTestCase {

    func testRepeatedAnalysisIsIdentical() {
        var options = GeneratorOptions()
        options.positionNoiseSigmaMeters = 4
        options.seed = 20260720

        let samples = RouteGenerator.generate(phases: threeWaveScript, options: options)
        let first = WaveAnalyzer.analyze(samples: samples)
        let second = WaveAnalyzer.analyze(samples: samples)
        let third = WaveAnalyzer.analyze(samples: samples)

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func testGeneratorIsReproducibleForAGivenSeed() {
        var options = GeneratorOptions()
        options.positionNoiseSigmaMeters = 5
        options.seed = 1234

        let a = RouteGenerator.generate(phases: threeWaveScript, options: options)
        let b = RouteGenerator.generate(phases: threeWaveScript, options: options)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsProduceDifferentTracks() {
        var options = GeneratorOptions()
        options.positionNoiseSigmaMeters = 5
        options.seed = 1
        let a = RouteGenerator.generate(phases: threeWaveScript, options: options)
        options.seed = 2
        let b = RouteGenerator.generate(phases: threeWaveScript, options: options)

        XCTAssertNotEqual(a, b, "fixtures must actually vary with the seed")
    }

    func testAnalysisIsIndependentOfInputOrdering() {
        var options = GeneratorOptions()
        options.positionNoiseSigmaMeters = 3
        options.seed = 4321
        let samples = RouteGenerator.generate(phases: threeWaveScript, options: options)

        // Deterministic shuffle (no Foundation randomness in tests).
        var rng = SeededRandom(seed: 99)
        var shuffled = samples
        for index in stride(from: shuffled.count - 1, to: 0, by: -1) {
            let swapIndex = Int(rng.nextUniform() * Double(index + 1)) % (index + 1)
            shuffled.swapAt(index, swapIndex)
        }

        let ordered = WaveAnalyzer.analyze(samples: samples)
        let scrambled = WaveAnalyzer.analyze(samples: shuffled)

        XCTAssertEqual(ordered.waveCount, scrambled.waveCount)
        XCTAssertEqual(ordered.totalDistanceMeters, scrambled.totalDistanceMeters, accuracy: 1e-6)
        XCTAssertEqual(ordered.longestRideSeconds, scrambled.longestRideSeconds, accuracy: 1e-9)
    }
}

// MARK: - Group 9: property-style invariants

final class InvariantTests: XCTestCase {

    /// A battery of structurally different sessions, every one of which must
    /// satisfy the algebraic invariants.
    private var sessionBattery: [(String, [RouteSample])] {
        var cases: [(String, [RouteSample])] = []

        cases.append(("three-wave clean", RouteGenerator.generate(phases: threeWaveScript)))

        var noisy = GeneratorOptions()
        noisy.positionNoiseSigmaMeters = 5
        noisy.deviceSpeedNoiseSigma = 0.8
        noisy.courseNoiseSigmaDegrees = 25
        noisy.seed = 55
        cases.append(("three-wave noisy", RouteGenerator.generate(phases: threeWaveScript, options: noisy)))

        var derived = GeneratorOptions()
        derived.providesDeviceSpeed = false
        derived.providesCourse = false
        derived.positionNoiseSigmaMeters = 4
        derived.seed = 66
        cases.append(("derived only", RouteGenerator.generate(phases: threeWaveScript, options: derived)))

        cases.append(("all sitting", RouteGenerator.generate(phases: [.sit(seconds: 600)])))
        cases.append(("all paddling", RouteGenerator.generate(phases: [
            .paddle(seconds: 400, speedMetersPerSecond: 1.5, headingDegrees: 270)
        ])))
        cases.append(("gap heavy", RouteGenerator.generate(phases: [
            .paddle(seconds: 20, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .dropout(seconds: 30, speedMetersPerSecond: 3, headingDegrees: 90),
            .ride(seconds: 10, peakSpeedMetersPerSecond: 6, headingDegrees: 90),
            .dropout(seconds: 45, speedMetersPerSecond: 2, headingDegrees: 90),
            .ride(seconds: 7, peakSpeedMetersPerSecond: 5, headingDegrees: 90),
            .paddle(seconds: 25, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])))
        cases.append(("back to back waves", RouteGenerator.generate(phases: [
            .paddle(seconds: 15, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 8, peakSpeedMetersPerSecond: 5.5, headingDegrees: 90),
            .paddle(seconds: 8, speedMetersPerSecond: 1.4, headingDegrees: 270),
            .ride(seconds: 8, peakSpeedMetersPerSecond: 5.5, headingDegrees: 90),
            .paddle(seconds: 15, speedMetersPerSecond: 1.4, headingDegrees: 270)
        ])))
        cases.append(("empty", []))
        return cases
    }

    func testInvariantsHoldAcrossSessionBattery() {
        for (name, samples) in sessionBattery {
            let stats = WaveAnalyzer.analyze(samples: samples)
            XCTAssertNoThrow(assertInvariants(stats), "invariants failed for \(name)")
        }
    }

    func testDistancePartitionIsSubsetOfTotal() {
        for (name, samples) in sessionBattery {
            let stats = WaveAnalyzer.analyze(samples: samples)
            let waveDistance = stats.waves.reduce(0) { $0 + $1.distanceMeters }
            XCTAssertLessThanOrEqual(
                stats.paddleDistanceMeters + waveDistance,
                stats.totalDistanceMeters + 1e-6,
                "distance partition violated for \(name)"
            )
        }
    }

    func testTopSpeedDominatesEveryWavePeak() {
        for (name, samples) in sessionBattery {
            let stats = WaveAnalyzer.analyze(samples: samples)
            for wave in stats.waves {
                XCTAssertLessThanOrEqual(
                    wave.peakSpeedMetersPerSecond * 3.6,
                    stats.topSpeedKph + 1e-9,
                    "top speed below a wave peak for \(name)"
                )
            }
        }
    }

    func testWaveDurationsAndDistancesArePositive() {
        for (name, samples) in sessionBattery {
            let stats = WaveAnalyzer.analyze(samples: samples)
            for wave in stats.waves {
                XCTAssertGreaterThanOrEqual(
                    wave.durationSeconds,
                    WaveAnalyzer.Tuning().minWaveDurationSeconds - 1e-9,
                    "sub-minimum ride reported for \(name)"
                )
                XCTAssertGreaterThan(wave.distanceMeters, 0, "zero-distance ride for \(name)")
            }
        }
    }

    func testWaveSegmentsDoNotOverlap() {
        for (name, samples) in sessionBattery {
            let stats = WaveAnalyzer.analyze(samples: samples)
            for (previous, next) in zip(stats.waves, stats.waves.dropFirst()) {
                XCTAssertLessThan(previous.endIndex, next.startIndex, "overlapping rides in \(name)")
            }
        }
    }

    /// Tightening the entry threshold can only ever reduce the wave count.
    /// A monotonicity property like this catches whole classes of logic errors
    /// that fixed expectations miss.
    func testRaisingTheEntryThresholdNeverIncreasesWaveCount() {
        let samples = RouteGenerator.generate(phases: threeWaveScript)
        var previousCount = Int.max

        for threshold in [1.8, 2.2, 3.0, 4.0, 5.0, 6.5, 9.0] {
            var tuning = WaveAnalyzer.Tuning()
            tuning.waveEnterSpeedMetersPerSecond = threshold
            tuning.waveExitSpeedMetersPerSecond = min(threshold, tuning.waveExitSpeedMetersPerSecond)
            let count = WaveAnalyzer.analyze(samples: samples, tuning: tuning).waveCount

            XCTAssertLessThanOrEqual(count, previousCount, "count rose when threshold rose to \(threshold)")
            previousCount = count
        }
        XCTAssertEqual(previousCount, 0, "no ride should survive a 9 m/s entry threshold")
    }

    /// Total distance must not depend on wave detection at all.
    func testTotalDistanceIsIndependentOfDetectionTuning() {
        let samples = RouteGenerator.generate(phases: threeWaveScript)
        var strict = WaveAnalyzer.Tuning()
        strict.waveEnterSpeedMetersPerSecond = 12

        let normal = WaveAnalyzer.analyze(samples: samples)
        let tightened = WaveAnalyzer.analyze(samples: samples, tuning: strict)

        XCTAssertEqual(normal.totalDistanceMeters, tightened.totalDistanceMeters, accuracy: 1e-9)
        XCTAssertEqual(tightened.waveCount, 0)
    }

    /// Position noise inflates raw track length badly — every wiggle of error
    /// adds path that was never travelled. Speed-integrated distance must not
    /// suffer from that, or a 300 m paddle gets reported as a kilometre.
    func testNoiseDoesNotInflateDistance() {
        let phases: [RoutePhase] = [
            .paddle(seconds: 200, speedMetersPerSecond: 1.5, headingDegrees: 270)
        ]
        let truthMeters = 300.0

        var noisy = GeneratorOptions()
        noisy.positionNoiseSigmaMeters = 4
        noisy.horizontalAccuracyMeters = 9
        noisy.seed = 8080
        let samples = RouteGenerator.generate(phases: phases, options: noisy)

        let integrated = WaveAnalyzer.analyze(samples: samples)
        XCTAssertEqual(integrated.totalDistanceMeters, truthMeters, accuracy: 90)

        // The raw-track measure is offered as a tuning comparison; it is
        // expected to over-report badly, which is exactly why it is not default.
        var rawTuning = WaveAnalyzer.Tuning()
        rawTuning.usesSpeedIntegratedDistance = false
        let raw = WaveAnalyzer.analyze(samples: samples, tuning: rawTuning)

        XCTAssertGreaterThan(raw.totalDistanceMeters, integrated.totalDistanceMeters * 1.5)
        assertInvariants(integrated)
        assertInvariants(raw)
    }

    /// Both distance measures must satisfy the partition invariant.
    func testInvariantsHoldForRawTrackDistanceMode() {
        var tuning = WaveAnalyzer.Tuning()
        tuning.usesSpeedIntegratedDistance = false
        for (name, samples) in sessionBattery {
            let stats = WaveAnalyzer.analyze(samples: samples, tuning: tuning)
            let waveDistance = stats.waves.reduce(0) { $0 + $1.distanceMeters }
            XCTAssertLessThanOrEqual(
                stats.paddleDistanceMeters + waveDistance,
                stats.totalDistanceMeters + 1e-6,
                "raw-distance partition violated for \(name)"
            )
            assertAllFinite(stats)
        }
    }

    func testHaversineMatchesKnownDistance() {
        // One minute of latitude is one nautical mile, 1852 m, by definition.
        let distance = WaveAnalyzer.haversineMeters(
            lat1: 0, lon1: 0, lat2: 1.0 / 60.0, lon2: 0
        )
        XCTAssertEqual(distance, 1852, accuracy: 6)
    }

    func testBearingIsNormalisedAndCorrect() {
        XCTAssertEqual(WaveAnalyzer.bearingDegrees(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 0, accuracy: 0.01)
        XCTAssertEqual(WaveAnalyzer.bearingDegrees(lat1: 0, lon1: 0, lat2: 0, lon2: 1), 90, accuracy: 0.01)
        XCTAssertEqual(WaveAnalyzer.bearingDegrees(lat1: 0, lon1: 0, lat2: -1, lon2: 0), 180, accuracy: 0.01)
        XCTAssertEqual(WaveAnalyzer.bearingDegrees(lat1: 0, lon1: 0, lat2: 0, lon2: -1), 270, accuracy: 0.01)
        XCTAssertEqual(WaveAnalyzer.bearingDegrees(lat1: 0, lon1: 0, lat2: 0, lon2: 0), 0, accuracy: 0.01)
    }
}
