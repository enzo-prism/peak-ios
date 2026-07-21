import Foundation
import SwiftData
import XCTest

@testable import Peak

// Ported from the standalone WindowScorer package, where the suite was written
// against swift-testing. Peak's test target is XCTest, so `@Test` functions
// became `test…` methods, `#expect` became `XCTAssert…`, `#require` became
// `XCTUnwrap`, and parameterised `@Test(arguments:)` cases became explicit loops
// (kept as loops rather than split into methods so the shared fixture setup and
// the measured thresholds stay together, which is where the meaning lives).
//
// Every assertion and every threshold is preserved verbatim. The numbers quoted
// in the comments are what the algorithm actually measured on these exact seeded
// fixtures; the assertions sit deliberately below them so ordinary variance does
// not red the suite but a real regression does.

// MARK: - Deterministic randomness

/// SplitMix64. Implemented here rather than using `SystemRandomNumberGenerator`
/// so that every "random" fixture in this suite is reproducible from an explicit
/// seed — a failing test can always be replayed exactly.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)   // 2^-53
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func bool(probability: Double) -> Bool {
        double(in: 0...1) < probability
    }

    /// Box-Muller. Deterministic given the seed, like everything else here.
    mutating func gaussian(mean: Double, sd: Double) -> Double {
        let u1 = max(1e-12, double(in: 0...1))
        let u2 = double(in: 0...1)
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    mutating func gaussian(mean: Double, sd: Double, in range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, gaussian(mean: mean, sd: sd)))
    }
}

// MARK: - Latent preference function (the synthetic "ground truth" surfer)

/// The hidden function the scorer is supposed to rediscover from ratings alone.
///
/// This surfer likes head-high-ish groundswell with light wind off a bearing of
/// 040 and a slightly-above-mean tide. Crucially it is *non-monotone* in height and
/// period (too small is bad, too big is also bad) and has a wind speed x direction
/// interaction — exactly the structure a linear model could not represent, and
/// exactly what the neighbour-based design is meant to handle.
enum LatentSurfer {
    static let idealHeight = 1.5
    static let idealPeriod = 12.5
    static let offshoreBearing = 40.0

    static func rating(_ c: ConditionsSample) -> Double {
        func gauss(_ x: Double, _ mu: Double, _ sigma: Double) -> Double {
            let z = (x - mu) / sigma
            return exp(-0.5 * z * z)
        }

        let h = c.swellWaveHeightMeters ?? idealHeight
        let p = c.swellWavePeriodSeconds ?? idealPeriod
        let speed = c.windSpeedKph ?? 0
        let dir = c.windDirectionDegrees ?? offshoreBearing
        let tide = c.seaLevelHeightMeters ?? 0.2

        // Size and period trade off against each other rather than multiplying, so
        // a small clean long-period day is still decent. Both are non-monotone.
        let swellQuality = 0.55 * gauss(h, idealHeight, 0.8) + 0.45 * gauss(p, idealPeriod, 3.6)
        let tideFactor = 0.78 + 0.22 * gauss(tide, 0.2, 0.7)

        // 0 when the wind is exactly offshore, 1 when it is exactly onshore.
        let delta = abs(((dir - offshoreBearing).truncatingRemainder(dividingBy: 360) + 540)
            .truncatingRemainder(dividingBy: 360) - 180)
        let onshoreness = (1 - cos(delta * .pi / 180)) / 2
        // The interaction: at 3 kph the bearing is irrelevant, at 30 kph it is
        // everything. A pure linear model in (speed, direction) cannot express this.
        let windFactor = max(0, 1 - speed / 85 - (speed / 30) * onshoreness)

        return max(0, min(5, 5.6 * swellQuality * tideFactor * windFactor))
    }

    /// What the user would actually type in: an integer star count.
    static func stars(_ c: ConditionsSample) -> Int {
        Int(rating(c).rounded())
    }
}

// MARK: - Fixture generation

enum WindowFixtures {
    static let trends: [TideTrend] = [.rising, .high, .falling, .low]

    /// Assembles a sample with the derived fields (wind chop, total height) kept
    /// physically consistent with the drivers, as a real forecast provider would.
    static func assemble(
        swell: Double, period: Double, swellDirection: Double,
        windSpeed: Double, windDirection: Double,
        seaLevel: Double, trend: TideTrend, sst: Double,
        rng: inout SeededRNG
    ) -> ConditionsSample {
        let windWave = max(0, windSpeed / 45 * 0.9 + rng.double(in: -0.08...0.08))
        return ConditionsSample(
            swellWaveHeightMeters: swell,
            swellWavePeriodSeconds: period,
            swellWaveDirectionDegrees: swellDirection,
            windWaveHeightMeters: windWave,
            waveHeightMeters: (swell * swell + windWave * windWave).squareRoot(),
            windSpeedKph: windSpeed,
            windDirectionDegrees: windDirection,
            seaSurfaceTemperatureC: sst,
            seaLevelHeightMeters: seaLevel,
            tideTrend: trend
        )
    }

    /// One logged session's conditions.
    ///
    /// Drawn from a realistic *logbook* distribution, not a uniform sweep of the
    /// physically possible: surfers paddle out mostly in ordinary-to-decent
    /// conditions, so the mass sits near the middle with long tails either side.
    /// Uniform sampling produced a history that was 61% zero-star, which is not a
    /// logbook any real user would have.
    static func randomConditions(_ rng: inout SeededRNG) -> ConditionsSample {
        assemble(
            swell: rng.gaussian(mean: 1.45, sd: 0.6, in: 0.25...3.2),
            period: rng.gaussian(mean: 12.0, sd: 3.0, in: 5...19),
            swellDirection: rng.double(in: 180...340),
            windSpeed: rng.gaussian(mean: 11, sd: 7.5, in: 0...36),
            windDirection: rng.double(in: 0...360),
            seaLevel: rng.gaussian(mean: 0, sd: 0.55, in: -1.2...1.2),
            trend: trends[Int(rng.double(in: 0...3.999))],
            sst: rng.double(in: 13...22),
            rng: &rng
        )
    }

    static func history(count: Int, rng: inout SeededRNG) -> [RatedSession] {
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        return (0..<count).map { i in
            let c = randomConditions(&rng)
            return RatedSession(
                date: base.addingTimeInterval(Double(i) * -86_400 * 3),
                rating: LatentSurfer.stars(c),
                conditions: c
            )
        }
    }

    /// One forecast day.
    ///
    /// Deliberately *correlated across hours*, unlike the history: within a single
    /// day the swell is essentially fixed and what actually changes is wind and
    /// tide. That is the real intraday question — "when today?" is almost always
    /// answered by the wind and tide profile — and it is also what makes contiguous
    /// good windows arise naturally instead of as random noise.
    static func forecast(hours: Int, rng: inout SeededRNG) -> [ForecastHour] {
        let base = Date(timeIntervalSinceReferenceDate: 760_000_000)

        let swell = rng.gaussian(mean: 1.5, sd: 0.65, in: 0.3...3.2)
        let period = rng.gaussian(mean: 12.0, sd: 3.0, in: 5...19)
        let swellDirection = rng.double(in: 180...340)
        let sst = rng.double(in: 13...22)

        // Typical diurnal wind: light at dawn, building through the afternoon, with
        // a random baseline and a random veer over the day.
        let dawnWind = rng.gaussian(mean: 6, sd: 3.5, in: 0...18)
        let peakWind = dawnWind + rng.gaussian(mean: 13, sd: 6, in: 0...30)
        let windDirStart = rng.double(in: 0...360)
        let windVeer = rng.gaussian(mean: 0, sd: 60, in: -140...140)

        // Semi-diurnal tide: ~12.4 h period, random phase and range.
        let tideRange = rng.gaussian(mean: 0.8, sd: 0.25, in: 0.25...1.4)
        let tidePhase = rng.double(in: 0...(2 * .pi))

        return (0..<hours).map { i in
            let t = Double(i)
            let dayFraction = min(1, max(0, (t - 5) / 9))            // ramps 05:00-14:00
            let afternoonFade = min(1, max(0, (22 - t) / 4))          // eases after 18:00
            let windSpeed = max(0, dawnWind + (peakWind - dawnWind) * dayFraction * afternoonFade)
            let windDirection = windDirStart + windVeer * dayFraction

            let angle = tidePhase + 2 * .pi * t / 12.42
            let seaLevel = tideRange * sin(angle)
            let slope = cos(angle)
            let trend: TideTrend
            if abs(slope) < 0.25 { trend = seaLevel >= 0 ? .high : .low }
            else { trend = slope > 0 ? .rising : .falling }

            return ForecastHour(
                date: base.addingTimeInterval(t * 3600),
                conditions: assemble(
                    swell: swell, period: period, swellDirection: swellDirection,
                    windSpeed: windSpeed, windDirection: windDirection,
                    seaLevel: seaLevel, trend: trend, sst: sst, rng: &rng
                )
            )
        }
    }

    /// Randomly nulls out fields to simulate manual logging and failed auto-fill.
    static func puncture(_ c: ConditionsSample, probability: Double, rng: inout SeededRNG) -> ConditionsSample {
        var out = c
        if rng.bool(probability: probability) { out.swellWaveHeightMeters = nil }
        if rng.bool(probability: probability) { out.swellWavePeriodSeconds = nil }
        if rng.bool(probability: probability) { out.swellWaveDirectionDegrees = nil }
        if rng.bool(probability: probability) { out.windWaveHeightMeters = nil }
        if rng.bool(probability: probability) { out.waveHeightMeters = nil }
        if rng.bool(probability: probability) { out.windSpeedKph = nil }
        if rng.bool(probability: probability) { out.windDirectionDegrees = nil }
        if rng.bool(probability: probability) { out.seaSurfaceTemperatureC = nil }
        if rng.bool(probability: probability) { out.seaLevelHeightMeters = nil }
        if rng.bool(probability: probability) { out.tideTrend = nil }
        return out
    }
}

/// One complete experiment fixture.
///
/// History and forecast are drawn from **independent** RNG streams derived from
/// the same seed. Without that, changing `historyCount` also changes the forecast
/// day (because it consumes a different number of draws), which silently confounds
/// every "does more history help?" comparison.
struct WindowScenario {
    let history: [RatedSession]
    let forecast: [ForecastHour]
    /// Latent truth per forecast hour, computed from the *complete* conditions
    /// before any puncturing.
    let truth: [Double]

    /// - Parameters:
    ///   - historyPuncture: fraction of fields nulled in *logged sessions*. This is
    ///     the realistic axis — logbook entries are patchy.
    ///   - forecastPuncture: fraction nulled in the *forecast*. Usually 0 in
    ///     practice, because the forecast comes complete from the provider; a
    ///     non-zero value is a stress test of the pathological case.
    init(
        seed: UInt64,
        historyCount: Int,
        forecastHours: Int = 24,
        historyPuncture: Double = 0,
        forecastPuncture: Double = 0
    ) {
        var historyRNG = SeededRNG(seed: seed &* 6_364_136_223_846_793_005 &+ 1)
        var forecastRNG = SeededRNG(seed: seed &* 1_442_695_040_888_963_407 &+ 7)
        var punctureRNG = SeededRNG(seed: seed &* 2_862_933_555_777_941_757 &+ 13)

        let rawHistory = WindowFixtures.history(count: historyCount, rng: &historyRNG)
        let rawForecast = WindowFixtures.forecast(hours: forecastHours, rng: &forecastRNG)
        self.truth = rawForecast.map { LatentSurfer.rating($0.conditions) }

        self.history = historyPuncture <= 0 ? rawHistory : rawHistory.map {
            RatedSession(date: $0.date, rating: $0.rating,
                         conditions: WindowFixtures.puncture($0.conditions,
                                                             probability: historyPuncture,
                                                             rng: &punctureRNG))
        }
        self.forecast = forecastPuncture <= 0 ? rawForecast : rawForecast.map {
            ForecastHour(date: $0.date,
                         conditions: WindowFixtures.puncture($0.conditions,
                                                             probability: forecastPuncture,
                                                             rng: &punctureRNG))
        }
    }

    /// Spearman correlation between predicted rating and latent truth.
    func rankingQuality(tuning: Tuning = .init()) -> Double {
        let hours = WindowScorer.scoreHours(forecast: forecast, history: history, tuning: tuning)
        return WindowStats.spearman(hours.map { $0.predictedRating }, truth)
    }
}

// MARK: - Statistics

enum WindowStats {
    /// Fractional ranks with ties averaged.
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.enumerated().sorted { lhs, rhs in
            if lhs.element != rhs.element { return lhs.element < rhs.element }
            return lhs.offset < rhs.offset
        }
        var out = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, order[j + 1].element == order[i].element { j += 1 }
            let mean = Double(i + j) / 2 + 1
            for t in i...j { out[order[t].offset] = mean }
            i = j + 1
        }
        return out
    }

    /// Spearman rank correlation. Returns 0 for degenerate input rather than NaN.
    static func spearman(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0 }
        return pearson(ranks(a), ranks(b))
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0 }
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n
        let mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            let x = a[i] - ma, y = b[i] - mb
            num += x * y; da += x * x; db += y * y
        }
        let denom = (da * db).squareRoot()
        guard denom > 1e-12, denom.isFinite else { return 0 }
        let r = num / denom
        return r.isFinite ? r : 0
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Assertions shared across suites

extension ScoredWindow {
    var isFinite: Bool {
        predictedRating.isFinite && confidence.isFinite && rankScore.isFinite
            && start.timeIntervalSinceReferenceDate.isFinite
            && end.timeIntervalSinceReferenceDate.isFinite
    }
}

extension ScoredHour {
    var isFinite: Bool {
        predictedRating.isFinite && confidence.isFinite && bestMatchWeight.isFinite
    }
}

// MARK: - Synthetic ground truth

/// Does the scorer actually recover a hidden preference function from ratings
/// alone, and does it degrade gracefully when the data is full of holes?
///
/// Every assertion is a *rate or median over many seeded fixtures*, never an
/// outcome on one hand-picked case, so the thresholds cannot be met by tuning the
/// algorithm to one lucky dataset.
final class WindowScorerGroundTruthTests: XCTestCase {

    static let seedCount = 60

    private func qualities(
        historyCount: Int,
        historyPuncture: Double = 0,
        forecastPuncture: Double = 0,
        seedBase: UInt64 = 1000,
        tuning: Tuning = .init()
    ) -> [Double] {
        (0..<Self.seedCount).map { seed in
            WindowScenario(
                seed: seedBase + UInt64(seed),
                historyCount: historyCount,
                historyPuncture: historyPuncture,
                forecastPuncture: forecastPuncture
            ).rankingQuality(tuning: tuning)
        }
    }

    // MARK: Ranking quality on complete data

    func testRanksForecastDayInAgreementWithLatentPreference() {
        let correlations = qualities(historyCount: 40)
        let median = WindowStats.median(correlations)
        let mean = WindowStats.mean(correlations)
        let strongFraction = Double(correlations.filter { $0 >= 0.6 }.count) / Double(correlations.count)

        // Measured on this exact fixture set: median 0.87, mean 0.78, 88% of seeds
        // above 0.6. Thresholds keep a clear margin below those.
        XCTAssertGreaterThanOrEqual(median, 0.78, "median Spearman \(median)")
        XCTAssertGreaterThanOrEqual(mean, 0.70, "mean Spearman \(mean)")
        XCTAssertGreaterThanOrEqual(strongFraction, 0.78, "only \(strongFraction) of seeds cleared 0.6")
        XCTAssertTrue(correlations.allSatisfy { $0.isFinite })
    }

    func testQualityImprovesWithHistorySize() {
        // Independent RNG streams for history and forecast (see `WindowScenario`)
        // make this a clean comparison: only the history count changes.
        let tiny = WindowStats.median(qualities(historyCount: 3, seedBase: 5000))
        let small = WindowStats.median(qualities(historyCount: 10, seedBase: 5000))
        let medium = WindowStats.median(qualities(historyCount: 25, seedBase: 5000))
        let large = WindowStats.median(qualities(historyCount: 80, seedBase: 5000))

        XCTAssertLessThan(tiny, small, "3 sessions (\(tiny)) should be worse than 10 (\(small))")
        XCTAssertLessThan(small, medium, "10 sessions (\(small)) should be worse than 25 (\(medium))")
        XCTAssertLessThanOrEqual(medium, large + 0.02, "25 sessions (\(medium)) vs 80 (\(large))")
        // Measured: 0.38 at n=3, 0.74 at n=10, 0.82 at n=25, 0.85 at n=80.
        XCTAssertGreaterThanOrEqual(large, 0.80, "median Spearman with a full logbook was \(large)")
    }

    // MARK: Missing-data robustness

    /// The realistic axis. Open-Meteo returns a complete forecast; it is the user's
    /// *logged* sessions that are patchy, because they were typed in by hand or the
    /// auto-fill failed.
    func testSurvivesPatchyLogbook() {
        for probability in [0.3, 0.45, 0.6] {
            let correlations = qualities(historyCount: 40, historyPuncture: probability, seedBase: 2000)
            XCTAssertTrue(correlations.allSatisfy { $0.isFinite }, "produced a non-finite correlation")

            let median = WindowStats.median(correlations)
            // Measured: 0.84 at 30% missing, 0.80 at 45%, 0.77 at 60%. Barely
            // degrades, because imputation stops sparse sessions from either
            // dominating or being thrown away.
            XCTAssertGreaterThanOrEqual(
                median, 0.7,
                "median Spearman with \(probability) of history missing was \(median)"
            )
        }
    }

    /// The pathological axis: the forecast itself is missing fields. Ranking hours
    /// within a day depends almost entirely on the wind and tide fields, so nulling
    /// those genuinely destroys the ability to discriminate. What is required here
    /// is that it degrades rather than breaks.
    func testSurvivesPuncturedForecastWithoutBreaking() {
        for probability in [0.3, 0.45, 0.6] {
            var correlations: [Double] = []
            for seed in 0..<Self.seedCount {
                let scenario = WindowScenario(
                    seed: 2500 + UInt64(seed), historyCount: 40,
                    historyPuncture: probability, forecastPuncture: probability
                )
                let hours = WindowScorer.scoreHours(forecast: scenario.forecast, history: scenario.history)
                XCTAssertTrue(hours.allSatisfy { $0.isFinite }, "non-finite hour score")
                XCTAssertTrue(hours.allSatisfy { (0...5).contains($0.predictedRating) })
                let windows = WindowScorer.rank(forecast: scenario.forecast, history: scenario.history)
                XCTAssertTrue(windows.allSatisfy { $0.isFinite }, "non-finite window")
                correlations.append(WindowStats.spearman(hours.map { $0.predictedRating }, scenario.truth))
            }
            let median = WindowStats.median(correlations)
            XCTAssertTrue(correlations.allSatisfy { $0.isFinite })
            // Measured: 0.63 at 30%, 0.45 at 45%, 0.24 at 60%. Still positive, i.e.
            // whatever signal remains is used rather than the output becoming noise.
            let floor: Double = probability <= 0.35 ? 0.45 : (probability <= 0.5 ? 0.25 : 0.05)
            XCTAssertGreaterThanOrEqual(
                median, floor,
                "median Spearman at \(probability) forecast missing was \(median)"
            )
        }
    }

    func testMissingDataDegradesMonotonically() {
        let clean = WindowStats.median(qualities(historyCount: 40, seedBase: 3000))
        let light = WindowStats.median(qualities(historyCount: 40, historyPuncture: 0.3,
                                                 forecastPuncture: 0.3, seedBase: 3000))
        let heavy = WindowStats.median(qualities(historyCount: 40, historyPuncture: 0.6,
                                                 forecastPuncture: 0.6, seedBase: 3000))
        XCTAssertGreaterThanOrEqual(clean, light - 0.03, "clean \(clean) vs 30% \(light)")
        XCTAssertGreaterThanOrEqual(light, heavy - 0.03, "30% \(light) vs 60% \(heavy)")
    }

    /// The headline design claim: imputing unobserved features at the expected
    /// distance, plus an overlap reliability discount, beats the naive
    /// "skip missing fields and average what you have".
    ///
    /// Asserted as a *paired* comparison — both configurations run on the identical
    /// scenario, and the win rate is counted across 200 of them. A comparison of
    /// two independent medians is far too noisy to settle this: at one seed set the
    /// naive version won by chance, which is exactly the kind of false conclusion
    /// pairing removes.
    func testImputationBeatsNaiveSkipAndAverage() {
        var naive = Tuning()
        naive.missingFeatureDistance = 0     // unobserved features cost nothing
        naive.overlapReliabilityExponent = 0 // sparse neighbours are not discounted
        naive.minOverlapRatio = 0            // and nothing is rejected for sparsity

        for probability in [0.3, 0.45, 0.6] {
            var designedTotal = 0.0
            var naiveTotal = 0.0
            var wins = 0
            let trials = 200

            for seed in 0..<trials {
                let s = WindowScenario(seed: 40000 + UInt64(seed), historyCount: 40,
                                       historyPuncture: probability, forecastPuncture: probability)
                let designed = s.rankingQuality()
                let naiveQuality = s.rankingQuality(tuning: naive)
                designedTotal += designed
                naiveTotal += naiveQuality
                if designed > naiveQuality { wins += 1 }
            }

            let designedMean = designedTotal / Double(trials)
            let naiveMean = naiveTotal / Double(trials)
            let winRate = Double(wins) / Double(trials)

            // Measured: mean 0.57 vs 0.52 at 30% missing, 0.42 vs 0.34 at 45%,
            // 0.22 vs 0.16 at 60%; win rates 0.64, 0.74, 0.65.
            XCTAssertGreaterThan(
                designedMean, naiveMean,
                "at \(probability) missing: designed \(designedMean) vs naive \(naiveMean)"
            )
            XCTAssertGreaterThan(
                winRate, 0.55,
                "designed won only \(winRate) of paired trials at \(probability)"
            )
        }
    }

    func testSparseSessionsDoNotOutCompeteDenseOnes() {
        // The classic failure of skip-and-average: a session that recorded only
        // swell height, and happens to match it exactly, scores a perfect distance
        // of zero and beats a genuinely similar full session.
        let query = ConditionsSample(
            swellWaveHeightMeters: 1.5, swellWavePeriodSeconds: 13,
            swellWaveDirectionDegrees: 270, windWaveHeightMeters: 0.2,
            waveHeightMeters: 1.55, windSpeedKph: 6, windDirectionDegrees: 40,
            seaSurfaceTemperatureC: 17, seaLevelHeightMeters: 0.2, tideTrend: .rising
        )
        let sparseExactMatch = RatedSession(
            date: Date(timeIntervalSinceReferenceDate: 0), rating: 5,
            conditions: ConditionsSample(swellWaveHeightMeters: 1.5, waveHeightMeters: 1.55)
        )
        var denseConditions = query
        denseConditions.swellWaveHeightMeters = 1.6
        denseConditions.swellWavePeriodSeconds = 12.5
        denseConditions.windSpeedKph = 8
        let denseCloseMatch = RatedSession(
            date: Date(timeIntervalSinceReferenceDate: 86_400), rating: 4, conditions: denseConditions
        )

        let result = WindowScorer.evaluate(conditions: query, history: [sparseExactMatch, denseCloseMatch])
        XCTAssertEqual(
            result.bestMatch?.date, denseCloseMatch.date,
            "the sparse one-field 'perfect' match outranked a dense near match"
        )
    }

    func testDenseExactMatchBeatsDenseDistantMatch() {
        var rng = SeededRNG(seed: 77)
        let target = WindowFixtures.randomConditions(&rng)
        let far = ConditionsSample(
            swellWaveHeightMeters: 0.4, swellWavePeriodSeconds: 6,
            swellWaveDirectionDegrees: 190, windWaveHeightMeters: 0.9,
            waveHeightMeters: 1.0, windSpeedKph: 33, windDirectionDegrees: 220,
            seaSurfaceTemperatureC: 13, seaLevelHeightMeters: -1.0, tideTrend: .low
        )
        let history = [
            RatedSession(date: Date(timeIntervalSinceReferenceDate: 0), rating: 5, conditions: target),
            RatedSession(date: Date(timeIntervalSinceReferenceDate: 1), rating: 1, conditions: far)
        ]
        let result = WindowScorer.evaluate(conditions: target, history: history)
        XCTAssertEqual(result.bestMatch?.rating, 5)
        XCTAssertGreaterThan(
            result.predictedRating, 3.5,
            "predicted \(result.predictedRating) for an exact replay of a 5-star session"
        )
    }

    // MARK: Calibration

    /// Kernel regression shrinks toward the mean. Without the leave-one-out
    /// calibration the model's predicted spread across a day was 0.58 stars against
    /// a true spread of 1.75 — a 3x compression that made every absolute threshold
    /// meaningless.
    func testPredictedRatingsSpanARealisticRange() {
        var modelSpreads: [Double] = []
        var truthSpreads: [Double] = []
        for seed in 0..<Self.seedCount {
            let s = WindowScenario(seed: 4000 + UInt64(seed), historyCount: 45)
            let hours = WindowScorer.scoreHours(forecast: s.forecast, history: s.history)
            let r = hours.map { $0.predictedRating }
            modelSpreads.append((r.max() ?? 0) - (r.min() ?? 0))
            truthSpreads.append((s.truth.max() ?? 0) - (s.truth.min() ?? 0))
        }
        let model = WindowStats.median(modelSpreads)
        let truth = WindowStats.median(truthSpreads)
        // Measured: 1.45 vs 1.70, a ratio of 0.85.
        XCTAssertGreaterThanOrEqual(model, truth * 0.6, "model spread \(model) is compressed vs truth \(truth)")
        XCTAssertLessThanOrEqual(model, truth * 1.6, "model spread \(model) is exaggerated vs truth \(truth)")
    }

    func testCalibrationIsMonotoneAndPreservesRanking() {
        var uncalibrated = Tuning()
        uncalibrated.maxCalibrationGain = 1
        uncalibrated.minCalibrationGain = 1

        for seed in 0..<20 {
            let s = WindowScenario(seed: 7700 + UInt64(seed), historyCount: 45)
            let a = WindowScorer.scoreHours(forecast: s.forecast, history: s.history)
                .map { $0.predictedRating }
            let b = WindowScorer.scoreHours(forecast: s.forecast, history: s.history, tuning: uncalibrated)
                .map { $0.predictedRating }
            // Clamping at 0 and 5 can flatten extreme ties, so compare rank
            // correlation rather than exact rank equality.
            XCTAssertGreaterThanOrEqual(
                WindowStats.spearman(a, b), 0.999,
                "calibration reordered the day at seed \(seed)"
            )
        }
    }

    // MARK: Window quality against a fixed oracle

    /// Fixed, tuning-independent definition of a genuinely good hour, so that
    /// sweeping the window constants against it is not circular: the *true* latent
    /// rating is at least 3.0 and within 0.5 stars of the day's true peak.
    private func oracleGoodHours(_ s: WindowScenario) -> Set<Date> {
        guard let peak = s.truth.max(), peak >= 3.0 else { return [] }
        return Set(zip(s.forecast, s.truth)
            .filter { $0.1 >= 3.0 && $0.1 >= peak - 0.5 }
            .map { $0.0.date })
    }

    func testRecommendedWindowsLandOnOracleGoodHours() {
        var precisions: [Double] = []
        var recalls: [Double] = []

        for seed in 0..<80 {
            let s = WindowScenario(seed: 4000 + UInt64(seed), historyCount: 45)
            let oracle = oracleGoodHours(s)
            guard !oracle.isEmpty else { continue }

            let windows = WindowScorer.rank(forecast: s.forecast, history: s.history)
            let picked = Set(s.forecast.map { $0.date }.filter { d in
                windows.contains { d >= $0.start && d < $0.end }
            })
            guard !picked.isEmpty else { precisions.append(0); recalls.append(0); continue }

            let hit = Double(picked.intersection(oracle).count)
            precisions.append(hit / Double(picked.count))
            recalls.append(hit / Double(oracle.count))
        }

        let precision = WindowStats.mean(precisions)
        let recall = WindowStats.mean(recalls)
        // Measured at the default tolerance of 0.35: precision 0.72, recall 0.90.
        XCTAssertGreaterThanOrEqual(precision, 0.62, "window precision against the oracle was \(precision)")
        XCTAssertGreaterThanOrEqual(recall, 0.78, "window recall against the oracle was \(recall)")
    }

    func testTopWindowContainsOneOfTheDaysBestHours() {
        var hits = 0
        var trials = 0

        for seed in 0..<80 {
            let s = WindowScenario(seed: 9000 + UInt64(seed), historyCount: 45)
            let truthRanks = WindowStats.ranks(s.truth)
            guard let top = WindowScorer.rank(forecast: s.forecast, history: s.history).first else { continue }
            trials += 1

            let inWindow = s.forecast.indices.filter {
                s.forecast[$0].date >= top.start && s.forecast[$0].date < top.end
            }
            let bestRank = inWindow.map { truthRanks[$0] }.max() ?? 0
            if bestRank / Double(s.forecast.count) >= 0.75 { hits += 1 }
        }

        XCTAssertGreaterThanOrEqual(trials, 50, "only \(trials) of 80 seeds produced any recommendation")
        let hitRate = Double(hits) / Double(max(1, trials))
        XCTAssertGreaterThanOrEqual(hitRate, 0.85, "top window held a top-quartile hour only \(hitRate) of the time")
    }
}

// MARK: - Confidence and sparse history

/// Confidence must be explicit, must rise with evidence, and must fall when the
/// model is extrapolating. Confidence — not the predicted rating — is the gate
/// the app enforces before showing anything.
final class WindowScorerConfidenceTests: XCTestCase {

    static let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    static func conditions(
        swell: Double, period: Double, wind: Double,
        windDirection: Double = 40, seaLevel: Double = 0.2
    ) -> ConditionsSample {
        ConditionsSample(
            swellWaveHeightMeters: swell,
            swellWavePeriodSeconds: period,
            swellWaveDirectionDegrees: 270,
            windWaveHeightMeters: 0.2,
            waveHeightMeters: swell + 0.05,
            windSpeedKph: wind,
            windDirectionDegrees: windDirection,
            seaSurfaceTemperatureC: 17,
            seaLevelHeightMeters: seaLevel,
            tideTrend: .rising
        )
    }

    /// Sessions clustered near the query, with ratings chosen so their spread rises
    /// monotonically as the list grows (population sd: 0, 0.5, 0.82, 1.12). That
    /// isolates the count and support effects from the signal effect.
    static let ladder: [RatedSession] = [
        RatedSession(date: base, rating: 4, conditions: conditions(swell: 1.5, period: 13, wind: 6)),
        RatedSession(date: base.addingTimeInterval(-86_400), rating: 3,
                     conditions: conditions(swell: 1.4, period: 12.5, wind: 8)),
        RatedSession(date: base.addingTimeInterval(-172_800), rating: 5,
                     conditions: conditions(swell: 1.6, period: 13.5, wind: 5)),
        RatedSession(date: base.addingTimeInterval(-259_200), rating: 2,
                     conditions: conditions(swell: 1.45, period: 12.8, wind: 7))
    ]

    func testZeroHistoryReturnsNoRecommendation() {
        var rng = SeededRNG(seed: 11)
        let forecast = WindowFixtures.forecast(hours: 24, rng: &rng)

        let windows = WindowScorer.rank(forecast: forecast, history: [])
        XCTAssertTrue(windows.isEmpty, "produced a recommendation from an empty history")

        // The per-hour scores still exist (the app may plot them) but must be
        // zero-confidence and finite.
        let hours = WindowScorer.scoreHours(forecast: forecast, history: [])
        XCTAssertEqual(hours.count, 24)
        XCTAssertTrue(hours.allSatisfy { $0.confidence == 0 })
        XCTAssertTrue(hours.allSatisfy { $0.isFinite })
        XCTAssertTrue(hours.allSatisfy { $0.bestMatch == nil })
        XCTAssertTrue(hours.allSatisfy { $0.matchFactors.isEmpty })
    }

    func testConfidenceIncreasesWithRatedSessionCount() {
        let query = Self.conditions(swell: 1.5, period: 13, wind: 6)
        let confidences = (0...4).map { count in
            WindowScorer.evaluate(conditions: query, history: Array(Self.ladder.prefix(count))).confidence
        }

        XCTAssertTrue(
            confidences.allSatisfy { $0.isFinite && (0...1).contains($0) },
            "confidence out of range: \(confidences)"
        )

        // Zero and one session are both exactly zero, and that is correct rather
        // than a floor: a single rating has no variance, so the history cannot
        // discriminate between any two hours. Confidence only becomes meaningful
        // once the user has rated at least two sessions differently.
        XCTAssertEqual(confidences[0], 0, "empty history had confidence \(confidences[0])")
        XCTAssertEqual(confidences[1], 0, "one session had confidence \(confidences[1])")

        // From two sessions on it must strictly increase. The ladder fixture is
        // built so rating spread also rises (0.5, 0.82, 1.12), isolating this from
        // the signal term.
        for count in 2...4 {
            XCTAssertGreaterThan(
                confidences[count], confidences[count - 1],
                "confidence did not increase from \(count - 1) to \(count) sessions: \(confidences)"
            )
        }
        XCTAssertGreaterThan(confidences[4], confidences[2])
    }

    func testSparseHistoryStaysBelowTheRecommendationThreshold() {
        let query = Self.conditions(swell: 1.5, period: 13, wind: 6)
        let threshold = Tuning().minConfidence

        for count in 0...3 {
            let result = WindowScorer.evaluate(conditions: query, history: Array(Self.ladder.prefix(count)))
            XCTAssertLessThan(
                result.confidence, threshold,
                "\(count) sessions produced confidence \(result.confidence), at or above the \(threshold) gate"
            )
        }
    }

    func testDenseHistoryClearsTheThreshold() {
        var rng = SeededRNG(seed: 4242)
        let query = Self.conditions(swell: 1.5, period: 13, wind: 6)
        let history = (0..<40).map { i in
            RatedSession(
                date: Self.base.addingTimeInterval(Double(-i) * 86_400),
                rating: [5, 4, 3, 2, 4, 5][i % 6],
                conditions: Self.conditions(
                    swell: 1.5 + rng.double(in: -0.25...0.25),
                    period: 13 + rng.double(in: -1.5...1.5),
                    wind: 6 + rng.double(in: -3...5)
                )
            )
        }
        let result = WindowScorer.evaluate(conditions: query, history: history)
        XCTAssertGreaterThan(
            result.confidence, Tuning().minConfidence,
            "40 close sessions only produced confidence \(result.confidence)"
        )
        XCTAssertNotNil(result.bestMatch)
    }

    func testExtrapolationCollapsesConfidence() {
        var rng = SeededRNG(seed: 8080)
        let history = (0..<40).map { i in
            RatedSession(
                date: Self.base.addingTimeInterval(Double(-i) * 86_400),
                rating: [5, 4, 3, 2, 4, 5][i % 6],
                conditions: Self.conditions(
                    swell: 1.5 + rng.double(in: -0.25...0.25),
                    period: 13 + rng.double(in: -1.5...1.5),
                    wind: 6 + rng.double(in: -3...5)
                )
            )
        }

        let inside = WindowScorer.evaluate(
            conditions: Self.conditions(swell: 1.5, period: 13, wind: 6), history: history)
        // A day nothing like anything this surfer has ever logged.
        let outside = WindowScorer.evaluate(
            conditions: Self.conditions(swell: 4.2, period: 6, wind: 34, windDirection: 220, seaLevel: -1.1),
            history: history)

        XCTAssertLessThan(
            outside.confidence, inside.confidence * 0.5,
            "extrapolated confidence \(outside.confidence) vs in-envelope \(inside.confidence)"
        )
        XCTAssertTrue(outside.confidence.isFinite)
        // Same sample count and same rating spread, so the drop must come entirely
        // from the neighbourhood support term.
        XCTAssertLessThan(outside.confidence, Tuning().minConfidence)
    }

    func testNoRatingVarianceMeansNoConfidence() {
        var rng = SeededRNG(seed: 909)
        let history = (0..<60).map { i in
            RatedSession(
                date: Self.base.addingTimeInterval(Double(-i) * 86_400),
                rating: 4,       // every session rated identically: no signal at all
                conditions: Self.conditions(
                    swell: 1.5 + rng.double(in: -0.4...0.4),
                    period: 13 + rng.double(in: -2...2),
                    wind: 6 + rng.double(in: -4...8)
                )
            )
        }
        let result = WindowScorer.evaluate(
            conditions: Self.conditions(swell: 1.5, period: 13, wind: 6), history: history)

        XCTAssertEqual(
            result.confidence, 0,
            "60 identically-rated sessions produced confidence \(result.confidence)"
        )
        XCTAssertTrue(result.predictedRating.isFinite)

        var rng2 = SeededRNG(seed: 909)
        let forecast = WindowFixtures.forecast(hours: 24, rng: &rng2)
        XCTAssertTrue(
            WindowScorer.rank(forecast: forecast, history: history).isEmpty,
            "recommended a window from a history that cannot discriminate"
        )
    }

    func testConfidenceStaysInRangeAcrossAWideSweep() {
        for seed in 0..<40 {
            for count in [0, 1, 2, 5, 15, 60] {
                let s = WindowScenario(seed: 3300 + UInt64(seed), historyCount: count,
                                       historyPuncture: 0.4, forecastPuncture: 0.2)
                for hour in WindowScorer.scoreHours(forecast: s.forecast, history: s.history) {
                    XCTAssertTrue(
                        hour.confidence >= 0 && hour.confidence <= 1,
                        "confidence \(hour.confidence) out of range"
                    )
                    XCTAssertTrue(hour.confidence.isFinite)
                }
            }
        }
    }

    func testRecommendationYieldGrowsWithLogbookSize() {
        func produced(_ count: Int) -> Int {
            (0..<60).reduce(into: 0) { total, seed in
                let s = WindowScenario(seed: 9000 + UInt64(seed), historyCount: count)
                if !WindowScorer.rank(forecast: s.forecast, history: s.history).isEmpty { total += 1 }
            }
        }
        // Measured over 80 seeds: 0/80 at n=3, 2/80 at n=10, 64/80 at n=25, 71/80 at n=60.
        let tiny = produced(3)
        let small = produced(10)
        let full = produced(60)

        XCTAssertEqual(tiny, 0, "\(tiny) recommendations from 3-session logbooks")
        XCTAssertLessThan(small, full, "10 sessions produced \(small), 60 produced \(full)")
        XCTAssertGreaterThanOrEqual(full, 30, "only \(full)/60 days produced a recommendation with a full logbook")
    }
}

// MARK: - Similarity function

/// The shape of the distance function itself — circular directions, the wind
/// speed x direction interaction, and rating-weighted scoring.
final class WindowScorerSimilarityTests: XCTestCase {

    static let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// Builds a sample where everything is held fixed except the fields under test,
    /// so a single feature's behaviour can be isolated.
    static func sample(
        windDirection: Double? = 40,
        windSpeed: Double? = 22,
        swellDirection: Double? = 270
    ) -> ConditionsSample {
        ConditionsSample(
            swellWaveHeightMeters: 1.5,
            swellWavePeriodSeconds: 13,
            swellWaveDirectionDegrees: swellDirection,
            windWaveHeightMeters: 0.2,
            waveHeightMeters: 1.55,
            windSpeedKph: windSpeed,
            windDirectionDegrees: windDirection,
            seaSurfaceTemperatureC: 17,
            seaLevelHeightMeters: 0.2,
            tideTrend: .rising
        )
    }

    /// Neighbour weight of the single history entry, which is a direct read of how
    /// similar the scorer thinks the two samples are.
    static func similarity(_ a: ConditionsSample, _ b: ConditionsSample) -> Double {
        WindowScorer.evaluate(
            conditions: a,
            history: [RatedSession(date: base, rating: 4, conditions: b)]
        ).bestMatchWeight
    }

    // MARK: Circularity

    func testWindDirectionIsCircular() {
        let good = Self.sample(windDirection: 355)
        let near = Self.similarity(Self.sample(windDirection: 5), good)
        let alsoNear = Self.similarity(Self.sample(windDirection: 345), good)
        let far = Self.similarity(Self.sample(windDirection: 175), good)

        XCTAssertGreaterThan(near, far, "5 vs 355 (\(near)) should be more similar than 175 vs 355 (\(far))")
        // 5 and 345 are both 10 degrees away, so they must score identically.
        XCTAssertLessThan(
            abs(near - alsoNear), 1e-12,
            "equal angular distances scored differently: \(near) vs \(alsoNear)"
        )
        XCTAssertGreaterThan(near, 0.5, "a 10-degree wind shift should still read as a close match, got \(near)")
    }

    func testSwellDirectionIsCircular() {
        let reference = Self.sample(swellDirection: 350)
        let near = Self.similarity(Self.sample(swellDirection: 10), reference)
        let far = Self.similarity(Self.sample(swellDirection: 170), reference)
        XCTAssertGreaterThan(near, far, "swell 10 vs 350 (\(near)) should beat 170 vs 350 (\(far))")
    }

    func testDegenerateBearingsAreHandled() {
        let reference = Self.sample(windDirection: 10)
        // -10, 350 and 710 are all the same bearing.
        let a = Self.similarity(Self.sample(windDirection: -10), reference)
        let b = Self.similarity(Self.sample(windDirection: 350), reference)
        let c = Self.similarity(Self.sample(windDirection: 710), reference)
        XCTAssertTrue(
            abs(a - b) < 1e-12 && abs(b - c) < 1e-12,
            "equivalent bearings scored differently: \(a), \(b), \(c)"
        )
        XCTAssertTrue(a.isFinite && a > 0)

        let opposite = Self.similarity(Self.sample(windDirection: 190), reference)
        XCTAssertLessThan(opposite, a, "a 180-degree reversal should be less similar than a 20-degree shift")
        XCTAssertTrue(opposite.isFinite)
    }

    // MARK: Wind speed x direction interaction

    func testWindDirectionMattersOnlyWhenWindy() {
        // Two glassy mornings from opposite bearings: essentially the same session.
        let lightA = Self.sample(windDirection: 40, windSpeed: 3)
        let lightB = Self.sample(windDirection: 220, windSpeed: 3)
        let lightSimilarity = Self.similarity(lightA, lightB)

        // Two 28 kph days from opposite bearings: completely different sessions.
        let strongA = Self.sample(windDirection: 40, windSpeed: 28)
        let strongB = Self.sample(windDirection: 220, windSpeed: 28)
        let strongSimilarity = Self.similarity(strongA, strongB)

        XCTAssertGreaterThan(
            lightSimilarity, strongSimilarity,
            "opposite light winds (\(lightSimilarity)) should be more similar than opposite strong winds (\(strongSimilarity))"
        )
        XCTAssertGreaterThan(
            lightSimilarity, 0.85,
            "two glassy mornings should read as near-identical, got \(lightSimilarity)"
        )
    }

    func testLightWindBearingReversalIsNearlyFree() {
        let reference = Self.sample(windDirection: 40, windSpeed: 3)
        let same = Self.similarity(Self.sample(windDirection: 40, windSpeed: 3), reference)
        let reversed = Self.similarity(Self.sample(windDirection: 220, windSpeed: 3), reference)
        XCTAssertLessThan(
            same - reversed, 0.1,
            "light-wind bearing reversal cost \(same - reversed), which is too much"
        )
    }

    func testStrongWindBearingReversalIsExpensive() {
        let reference = Self.sample(windDirection: 40, windSpeed: 30)
        let same = Self.similarity(Self.sample(windDirection: 40, windSpeed: 30), reference)
        let reversed = Self.similarity(Self.sample(windDirection: 220, windSpeed: 30), reference)
        XCTAssertGreaterThan(
            same - reversed, 0.2,
            "strong-wind bearing reversal only cost \(same - reversed)"
        )
    }

    // MARK: Rating-weighted scoring

    func testPredictionFollowsNeighbourRatings() {
        let goodConditions = Self.sample(windDirection: 40, windSpeed: 5)
        let badConditions = Self.sample(windDirection: 220, windSpeed: 30)

        let history = (0..<12).map { i -> RatedSession in
            let good = i % 2 == 0
            return RatedSession(
                date: Self.base.addingTimeInterval(Double(-i) * 86_400),
                rating: good ? 5 : 1,
                conditions: good ? goodConditions : badConditions
            )
        }

        let nearGood = WindowScorer.evaluate(conditions: goodConditions, history: history)
        let nearBad = WindowScorer.evaluate(conditions: badConditions, history: history)

        XCTAssertGreaterThan(
            nearGood.predictedRating, nearBad.predictedRating + 1.0,
            "good \(nearGood.predictedRating) vs bad \(nearBad.predictedRating)"
        )
        XCTAssertEqual(nearGood.bestMatch?.rating, 5)
        XCTAssertEqual(nearBad.bestMatch?.rating, 1)
    }

    func testTideTrendIsCyclic() {
        func withTrend(_ t: TideTrend) -> ConditionsSample {
            var s = Self.sample()
            s.tideTrend = t
            return s
        }
        let reference = withTrend(.rising)
        let adjacent = Self.similarity(withTrend(.high), reference)
        let opposite = Self.similarity(withTrend(.falling), reference)
        let identical = Self.similarity(withTrend(.rising), reference)

        XCTAssertGreaterThan(identical, adjacent, "identical \(identical) vs adjacent \(adjacent)")
        XCTAssertGreaterThan(adjacent, opposite, "adjacent \(adjacent) vs opposite \(opposite)")
    }

    func testEveryFeatureMovesSimilarityInTheRightDirection() {
        let features = [
            "swellHeight", "swellPeriod", "windWaveHeight", "waveHeight",
            "windSpeed", "seaTemperature", "seaLevel"
        ]

        for feature in features {
            var reference = Self.sample()
            var near = Self.sample()
            var far = Self.sample()

            switch feature {
            case "swellHeight":
                reference.swellWaveHeightMeters = 1.5
                near.swellWaveHeightMeters = 1.6; far.swellWaveHeightMeters = 3.0
            case "swellPeriod":
                reference.swellWavePeriodSeconds = 13
                near.swellWavePeriodSeconds = 13.5; far.swellWavePeriodSeconds = 6
            case "windWaveHeight":
                reference.windWaveHeightMeters = 0.2
                near.windWaveHeightMeters = 0.25; far.windWaveHeightMeters = 1.4
            case "waveHeight":
                reference.waveHeightMeters = 1.55
                near.waveHeightMeters = 1.6; far.waveHeightMeters = 3.2
            case "windSpeed":
                reference.windSpeedKph = 22
                near.windSpeedKph = 23; far.windSpeedKph = 0
            case "seaTemperature":
                reference.seaSurfaceTemperatureC = 17
                near.seaSurfaceTemperatureC = 17.5; far.seaSurfaceTemperatureC = 2
            case "seaLevel":
                reference.seaLevelHeightMeters = 0.2
                near.seaLevelHeightMeters = 0.25; far.seaLevelHeightMeters = -1.8
            default:
                XCTFail("unknown feature \(feature)")
                continue
            }

            let nearScore = Self.similarity(near, reference)
            let farScore = Self.similarity(far, reference)
            XCTAssertGreaterThan(nearScore, farScore, "\(feature): near \(nearScore) should beat far \(farScore)")
            XCTAssertTrue(nearScore.isFinite && farScore.isFinite)
        }
    }

    // MARK: Explanation payload

    func testEveryRecommendedWindowIsExplained() {
        var explained = 0
        for seed in 0..<40 {
            let s = WindowScenario(seed: 4000 + UInt64(seed), historyCount: 45)
            for window in WindowScorer.rank(forecast: s.forecast, history: s.history) {
                XCTAssertNotNil(window.bestMatch, "window without a best match")
                XCTAssertFalse(window.matchFactors.isEmpty, "window without match factors")
                XCTAssertLessThanOrEqual(window.matchFactors.count, Tuning().maxMatchFactors)
                XCTAssertEqual(
                    Set(window.matchFactors).count, window.matchFactors.count,
                    "duplicate match factors: \(window.matchFactors)"
                )
                XCTAssertTrue(window.matchFactors.allSatisfy { !$0.isEmpty })
                explained += 1
            }
        }
        XCTAssertGreaterThan(explained, 40, "only \(explained) windows produced across 40 days")
    }

    /// A window predicted at 3.5 stars must not be justified with "similar to your
    /// 2-star session" — the exemplar would read as an argument against the
    /// recommendation it is supposed to support.
    func testCitedSessionIsNeverRatedBelowThePrediction() {
        let tolerance = Tuning().exemplarMaxRatingShortfall
        var windows = 0
        var inconsistent = 0

        for seed in 0..<120 {
            let s = WindowScenario(seed: 4000 + UInt64(seed), historyCount: 45)
            for window in WindowScorer.rank(forecast: s.forecast, history: s.history) {
                windows += 1
                guard let match = window.bestMatch else { continue }
                // The window rating is a mean over its hours, so allow a little
                // slack beyond the per-hour tolerance.
                if Double(match.rating) < window.predictedRating - tolerance - 0.5 {
                    inconsistent += 1
                }
            }
        }

        XCTAssertGreaterThan(windows, 100, "only \(windows) windows produced")
        XCTAssertEqual(
            inconsistent, 0,
            "\(inconsistent) of \(windows) windows cited a session rated well below their own prediction"
        )
    }

    func testExemplarIsStillAGenuinelySimilarSession() {
        // A 5-star session that looks nothing like today, and a 4-star session that
        // looks exactly like today. The 4-star one must be cited: consistency
        // filtering must not degenerate into "show the best rating you have".
        let today = Self.sample(windDirection: 40, windSpeed: 5)
        let unrelated = ConditionsSample(
            swellWaveHeightMeters: 3.2, swellWavePeriodSeconds: 18,
            swellWaveDirectionDegrees: 120, windWaveHeightMeters: 1.2,
            waveHeightMeters: 3.4, windSpeedKph: 34, windDirectionDegrees: 210,
            seaSurfaceTemperatureC: 8, seaLevelHeightMeters: -1.2, tideTrend: .low
        )
        let history = [
            RatedSession(date: Self.base, rating: 5, conditions: unrelated),
            RatedSession(date: Self.base.addingTimeInterval(86_400), rating: 4, conditions: today)
        ]
        let result = WindowScorer.evaluate(conditions: today, history: history)
        XCTAssertEqual(
            result.bestMatch?.rating, 4,
            "cited the unrelated 5-star session over the near-identical 4-star one"
        )
    }

    func testMatchFactorsNameFeaturesThatActuallyAgree() {
        // A history entry identical in period and wind but wildly different in
        // swell height: the explanation must not claim the size matched.
        var past = Self.sample(windDirection: 40, windSpeed: 5)
        past.swellWaveHeightMeters = 3.1
        past.waveHeightMeters = 3.15

        var today = Self.sample(windDirection: 40, windSpeed: 5)
        today.swellWaveHeightMeters = 1.0
        today.waveHeightMeters = 1.05

        let result = WindowScorer.evaluate(
            conditions: today,
            history: [RatedSession(date: Self.base, rating: 5, conditions: past)]
        )

        XCTAssertFalse(result.matchFactors.isEmpty)
        XCTAssertFalse(
            result.matchFactors.contains { $0.contains("m swell") },
            "claimed the swell height matched when it went 3.1 m -> 1.0 m: \(result.matchFactors)"
        )
        XCTAssertTrue(
            result.matchFactors.contains { $0.contains("13 s period") },
            "failed to mention the period, which did match: \(result.matchFactors)"
        )
    }

    func testMatchFactorTextIsStableAndLocaleIndependent() {
        let today = Self.sample(windDirection: 40, windSpeed: 5)
        let result = WindowScorer.evaluate(
            conditions: today,
            history: [RatedSession(date: Self.base, rating: 5, conditions: today)]
        )
        // Decimal separator must always be ".", never "," under a European locale.
        XCTAssertTrue(
            result.matchFactors.allSatisfy { !$0.contains(",") },
            "locale-dependent formatting leaked into \(result.matchFactors)"
        )
        XCTAssertEqual(result.matchFactors.count, Tuning().maxMatchFactors)
    }

    /// The algorithm deliberately refuses to say "offshore" or "onshore": deciding
    /// that needs the coastline orientation of the break, which Peak does not model
    /// and cannot reliably infer. Wind is described by strength and bearing instead.
    func testWindFactorsNeverClaimOffshoreOrOnshore() {
        var seen = 0
        for seed in 0..<40 {
            let s = WindowScenario(seed: 4000 + UInt64(seed), historyCount: 45)
            for window in WindowScorer.rank(forecast: s.forecast, history: s.history) {
                for factor in window.matchFactors {
                    seen += 1
                    let lowered = factor.lowercased()
                    XCTAssertFalse(lowered.contains("offshore"), "claimed offshore in \(factor)")
                    XCTAssertFalse(lowered.contains("onshore"), "claimed onshore in \(factor)")
                    XCTAssertFalse(lowered.contains("cross-shore"), "claimed cross-shore in \(factor)")
                }
            }
        }
        XCTAssertGreaterThan(seen, 50, "only \(seen) factors inspected")
    }
}

// MARK: - Window grouping

/// Contiguous good hours merge into one window, gaps split them, and longer
/// windows outrank isolated great hours.
///
/// These drive `groupWindows` with synthetic `ScoredHour` values directly, which
/// is why that function is exposed: constructing a history that happens to produce
/// an exact rating profile would test the wrong thing.
final class WindowScorerGroupingTests: XCTestCase {

    static let dayStart = Date(timeIntervalSinceReferenceDate: 760_000_000)

    static func hours(_ ratings: [Double], confidence: Double = 0.8, startHour: Int = 0) -> [ScoredHour] {
        ratings.enumerated().map { index, rating in
            ScoredHour(
                date: dayStart.addingTimeInterval(Double(startHour + index) * 3600),
                predictedRating: rating,
                confidence: confidence
            )
        }
    }

    static func hourOffset(_ date: Date) -> Int {
        Int(date.timeIntervalSince(dayStart) / 3600)
    }

    func testContiguousHoursMergeIntoASingleWindow() throws {
        // Hours 0-2 poor, 3-5 good, 6-8 poor.
        let scored = Self.hours([1, 1.5, 2, 4.2, 4.4, 4.3, 2, 1.5, 1])
        let windows = WindowScorer.groupWindows(hours: scored)

        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(Self.hourOffset(window.start), 3)
        // End is exclusive: hours 3,4,5 -> 03:00 to 06:00.
        XCTAssertEqual(Self.hourOffset(window.end), 6)
        XCTAssertEqual(window.hourCount, 3)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 3 * 3600)
        XCTAssertLessThan(abs(window.predictedRating - 4.3), 1e-9)
    }

    func testDipInConditionsSplitsOneRunIntoTwoWindows() {
        // The dip at hour 3 is more than the relative tolerance below the peak.
        let scored = Self.hours([4.4, 4.3, 4.4, 3.1, 4.4, 4.3])
        let windows = WindowScorer.groupWindows(hours: scored).sorted { $0.start < $1.start }

        XCTAssertEqual(windows.count, 2, "expected two windows, got \(windows.count)")
        XCTAssertEqual(Self.hourOffset(windows[0].start), 0)
        XCTAssertEqual(Self.hourOffset(windows[0].end), 3)
        XCTAssertEqual(Self.hourOffset(windows[1].start), 4)
        XCTAssertEqual(Self.hourOffset(windows[1].end), 6)
    }

    func testMissingForecastHourSplitsTheWindow() {
        var scored = Self.hours([4.4, 4.3, 4.4, 4.4, 4.3])
        scored.remove(at: 2)                 // hour 2 never arrived from the provider
        let windows = WindowScorer.groupWindows(hours: scored).sorted { $0.start < $1.start }

        XCTAssertEqual(windows.count, 2, "a two-hour hole should split the window, got \(windows.count)")
        XCTAssertEqual(windows[0].hourCount, 2)
        XCTAssertEqual(windows[1].hourCount, 2)
    }

    func testJitteredTimestampInsideToleranceDoesNotSplit() {
        var scored = Self.hours([4.4, 4.3, 4.4, 4.4])
        // Provider returned 02:20 instead of 02:00 — still contiguous.
        scored[2] = ScoredHour(date: scored[2].date.addingTimeInterval(20 * 60),
                               predictedRating: 4.4, confidence: 0.8)
        let windows = WindowScorer.groupWindows(hours: scored)
        XCTAssertEqual(windows.count, 1, "a 20-minute jitter split the window")
    }

    func testSingleGoodHourProducesAValidOneHourWindow() throws {
        let scored = Self.hours([1, 1, 4.5, 1, 1])
        let windows = WindowScorer.groupWindows(hours: scored)

        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.hourCount, 1)
        XCTAssertEqual(Self.hourOffset(window.start), 2)
        XCTAssertEqual(Self.hourOffset(window.end), 3)
        XCTAssertGreaterThan(window.end, window.start)
    }

    func testMultipleNonContiguousWindowsAreAllReturned() {
        let scored = Self.hours([4.4, 4.3, 1, 1, 4.4, 4.4, 1, 4.5])
        let windows = WindowScorer.groupWindows(hours: scored)
        XCTAssertEqual(windows.count, 3, "expected 3 windows, got \(windows.count)")
        XCTAssertEqual(windows.map { $0.hourCount }.sorted(), [1, 2, 2])
    }

    func testThreeHourWindowOutranksAnIsolatedBetterHour() throws {
        // Hour 0 is the single best hour of the day; hours 3-5 are a touch worse but
        // sustained. The sustained window must come first.
        let scored = Self.hours([4.5, 1, 1, 4.2, 4.2, 4.2])
        let windows = WindowScorer.groupWindows(hours: scored)

        XCTAssertEqual(windows.count, 2)
        let top = try XCTUnwrap(windows.first)
        XCTAssertEqual(top.hourCount, 3, "the isolated peak outranked the sustained window")
        XCTAssertEqual(Self.hourOffset(top.start), 3)
        // The displayed rating stays honest: the duration bonus lives in rankScore.
        XCTAssertLessThan(abs(top.predictedRating - 4.2), 1e-9)
        XCTAssertGreaterThan(top.rankScore, top.predictedRating)
    }

    func testDurationBonusIsCapped() throws {
        let tuning = Tuning()
        // Ten hours of mediocrity vs three hours of excellence.
        let flat = WindowScorer.groupWindows(hours: Self.hours(Array(repeating: 3.2, count: 10)))
        let sharp = WindowScorer.groupWindows(hours: Self.hours([1, 4.9, 4.9, 4.9, 1]))

        let flatScore = try XCTUnwrap(flat.first).rankScore
        let sharpScore = try XCTUnwrap(sharp.first).rankScore
        XCTAssertGreaterThan(sharpScore, flatScore, "flat \(flatScore) outranked sharp \(sharpScore)")
        XCTAssertLessThanOrEqual(flatScore - 3.2, tuning.maxDurationBonus + 1e-9)
    }

    func testHoursBelowTheAbsoluteRatingFloorNeverFormAWindow() {
        let scored = Self.hours([2.9, 2.8, 2.95, 2.7])
        XCTAssertTrue(
            WindowScorer.groupWindows(hours: scored).isEmpty,
            "recommended a window on a day where nothing cleared 3.0 stars"
        )
    }

    func testHoursBelowTheConfidenceFloorNeverFormAWindow() {
        let scored = Self.hours([4.5, 4.6, 4.5], confidence: 0.05)
        XCTAssertTrue(
            WindowScorer.groupWindows(hours: scored).isEmpty,
            "recommended a window from hours the model has no confidence in"
        )
    }

    func testSingleLowConfidenceHourSplitsAnOtherwiseGoodRun() {
        var scored = Self.hours([4.4, 4.4, 4.4, 4.4, 4.4])
        scored[2] = ScoredHour(date: scored[2].date, predictedRating: 4.4, confidence: 0.01)
        let windows = WindowScorer.groupWindows(hours: scored)
        XCTAssertEqual(windows.count, 2, "expected the untrusted hour to split the run, got \(windows.count)")
    }

    func testUnsortedAndDuplicatedInputHoursAreNormalised() throws {
        let ordered = Self.hours([4.4, 4.3, 4.4])
        let scrambled = [ordered[2], ordered[0], ordered[1], ordered[0]]   // shuffled + duplicate

        let windows = WindowScorer.groupWindows(hours: scrambled)
        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.hourCount, 3, "duplicate hour was counted, got \(window.hourCount)")
        XCTAssertEqual(Self.hourOffset(window.start), 0)
        XCTAssertEqual(Self.hourOffset(window.end), 3)
    }

    func testMaxWindowsIsRespected() {
        var tuning = Tuning()
        tuning.maxWindows = 2
        // Six isolated good hours separated by poor ones.
        let scored = Self.hours([4.4, 1, 4.4, 1, 4.4, 1, 4.4, 1, 4.4, 1, 4.4])
        let windows = WindowScorer.groupWindows(hours: scored, tuning: tuning)
        XCTAssertEqual(windows.count, 2)
    }

    func testReturnedWindowsAreRankedAndDisjoint() {
        let scored = Self.hours([4.4, 4.5, 1, 4.2, 4.2, 4.2, 1, 4.9])
        let windows = WindowScorer.groupWindows(hours: scored)

        for (a, b) in zip(windows, windows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.rankScore, b.rankScore, "windows are not in rank order")
        }
        let chronological = windows.sorted { $0.start < $1.start }
        for (a, b) in zip(chronological, chronological.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start, "windows overlap: \(a.start)-\(a.end) and \(b.start)-\(b.end)")
        }
    }

    func testEmptyInputProducesNoWindows() {
        XCTAssertTrue(WindowScorer.groupWindows(hours: []).isEmpty)
    }
}

// MARK: - Robustness, determinism and invariants

/// Degenerate input, determinism, and the invariants the app relies on to render
/// safely.
final class WindowScorerRobustnessTests: XCTestCase {

    static let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    static func goodHistory(seed: UInt64 = 5150, count: Int = 40) -> [RatedSession] {
        var rng = SeededRNG(seed: seed)
        return WindowFixtures.history(count: count, rng: &rng)
    }

    // MARK: Degenerate input

    func testEmptyForecastProducesEmptyOutput() {
        XCTAssertTrue(WindowScorer.rank(forecast: [], history: Self.goodHistory()).isEmpty)
        XCTAssertTrue(WindowScorer.scoreHours(forecast: [], history: Self.goodHistory()).isEmpty)
        XCTAssertTrue(WindowScorer.rank(forecast: [], history: []).isEmpty)
    }

    func testAllNilConditionsNeverCrashAndNeverRecommend() {
        let empty = ConditionsSample()
        let forecast = (0..<12).map {
            ForecastHour(date: Self.base.addingTimeInterval(Double($0) * 3600), conditions: empty)
        }

        // Nil forecast against a real history.
        let a = WindowScorer.scoreHours(forecast: forecast, history: Self.goodHistory())
        XCTAssertEqual(a.count, 12)
        XCTAssertTrue(a.allSatisfy { $0.isFinite })
        XCTAssertTrue(a.allSatisfy { $0.confidence == 0 }, "empty conditions produced non-zero confidence")
        XCTAssertTrue(WindowScorer.rank(forecast: forecast, history: Self.goodHistory()).isEmpty)

        // Real forecast against a history of nil-conditioned sessions.
        let nilHistory = (0..<30).map {
            RatedSession(date: Self.base.addingTimeInterval(Double(-$0) * 86_400),
                         rating: $0 % 6, conditions: empty)
        }
        var rng = SeededRNG(seed: 3)
        let realForecast = WindowFixtures.forecast(hours: 24, rng: &rng)
        let b = WindowScorer.scoreHours(forecast: realForecast, history: nilHistory)
        XCTAssertTrue(b.allSatisfy { $0.isFinite })
        XCTAssertTrue(b.allSatisfy { $0.confidence == 0 })
        XCTAssertTrue(b.allSatisfy { $0.bestMatch == nil })
        XCTAssertTrue(WindowScorer.rank(forecast: realForecast, history: nilHistory).isEmpty)
    }

    func testSingleFieldSessionIsIgnoredRatherThanTrusted() {
        let oneField = RatedSession(
            date: Self.base, rating: 5,
            conditions: ConditionsSample(seaSurfaceTemperatureC: 18)
        )
        let result = WindowScorer.evaluate(
            conditions: ConditionsSample(seaSurfaceTemperatureC: 18),
            history: [oneField]
        )
        XCTAssertNil(result.bestMatch, "matched on water temperature alone")
        XCTAssertEqual(result.confidence, 0)
        XCTAssertTrue(result.predictedRating.isFinite)
    }

    func testNonFiniteInputNeverReachesTheOutput() {
        let poison = ConditionsSample(
            swellWaveHeightMeters: .nan,
            swellWavePeriodSeconds: .infinity,
            swellWaveDirectionDegrees: -.infinity,
            windWaveHeightMeters: .nan,
            waveHeightMeters: .signalingNaN,
            windSpeedKph: .infinity,
            windDirectionDegrees: .nan,
            seaSurfaceTemperatureC: -.infinity,
            seaLevelHeightMeters: .nan,
            tideTrend: .rising
        )

        // Poison in the forecast.
        let forecast = (0..<8).map {
            ForecastHour(date: Self.base.addingTimeInterval(Double($0) * 3600), conditions: poison)
        }
        let a = WindowScorer.scoreHours(forecast: forecast, history: Self.goodHistory())
        XCTAssertTrue(a.allSatisfy { $0.isFinite }, "NaN leaked into hour scores")
        XCTAssertTrue(a.allSatisfy { (0...5).contains($0.predictedRating) })
        XCTAssertTrue(a.allSatisfy { (0...1).contains($0.confidence) })
        XCTAssertTrue(WindowScorer.rank(forecast: forecast, history: Self.goodHistory())
            .allSatisfy { $0.isFinite })

        // Poison in the history, mixed with real sessions.
        var mixed = Self.goodHistory()
        mixed.append(RatedSession(date: Self.base, rating: 5, conditions: poison))
        mixed.append(RatedSession(date: Self.base.addingTimeInterval(1), rating: -99, conditions: poison))
        mixed.append(RatedSession(date: Self.base.addingTimeInterval(2), rating: 9999, conditions: poison))

        var rng = SeededRNG(seed: 12)
        let realForecast = WindowFixtures.forecast(hours: 24, rng: &rng)
        let b = WindowScorer.scoreHours(forecast: realForecast, history: mixed)
        XCTAssertTrue(b.allSatisfy { $0.isFinite }, "NaN leaked in from history")
        XCTAssertTrue(b.allSatisfy { (0...5).contains($0.predictedRating) })
        XCTAssertTrue(WindowScorer.rank(forecast: realForecast, history: mixed).allSatisfy {
            $0.isFinite && (0...5).contains($0.predictedRating) && (0...1).contains($0.confidence)
        })
    }

    func testOutOfRangeRatingsAreClamped() {
        let conditions = ConditionsSample(
            swellWaveHeightMeters: 1.5, swellWavePeriodSeconds: 13,
            windSpeedKph: 5, windDirectionDegrees: 40, seaLevelHeightMeters: 0.2
        )
        let absurd = (0..<20).map {
            RatedSession(date: Self.base.addingTimeInterval(Double(-$0) * 86_400),
                         rating: $0.isMultiple(of: 2) ? 10_000 : -10_000,
                         conditions: conditions)
        }
        let result = WindowScorer.evaluate(conditions: conditions, history: absurd)
        XCTAssertTrue((0...5).contains(result.predictedRating), "predicted \(result.predictedRating)")
        XCTAssertTrue(result.predictedRating.isFinite)
    }

    func testCorruptNegativeMagnitudesAreDiscarded() {
        // A negative wave height is corrupt data. Sea level may legitimately be
        // negative, so it must survive.
        var corrupt = ConditionsSample(
            swellWaveHeightMeters: -3, swellWavePeriodSeconds: -12,
            windSpeedKph: -40, seaLevelHeightMeters: -0.8, tideTrend: .falling
        )
        corrupt.waveHeightMeters = -1

        let result = WindowScorer.evaluate(
            conditions: corrupt,
            history: [RatedSession(date: Self.base, rating: 5, conditions: corrupt)]
        )
        XCTAssertTrue(result.predictedRating.isFinite)
        XCTAssertTrue((0...1).contains(result.confidence))
        // Only sea level and tide trend remain comparable, which is enough overlap
        // in feature count but the result must stay finite and bounded regardless.
        XCTAssertTrue(result.isFinite)
    }

    func testExtremeButFiniteValuesStayBounded() {
        let extreme = ConditionsSample(
            swellWaveHeightMeters: 1e12, swellWavePeriodSeconds: 1e12,
            swellWaveDirectionDegrees: 1e9, windWaveHeightMeters: 1e12,
            waveHeightMeters: 1e12, windSpeedKph: 1e12,
            windDirectionDegrees: -1e9, seaSurfaceTemperatureC: 1e12,
            seaLevelHeightMeters: -1e12, tideTrend: .low
        )
        let forecast = [ForecastHour(date: Self.base, conditions: extreme)]
        let hours = WindowScorer.scoreHours(forecast: forecast, history: Self.goodHistory())
        XCTAssertTrue(hours.allSatisfy { $0.isFinite })
        XCTAssertTrue(hours.allSatisfy { (0...5).contains($0.predictedRating) })
        XCTAssertTrue(hours.allSatisfy { (0...1).contains($0.confidence) })
    }

    func testDegenerateTuningValuesCannotProduceNaN() {
        var tuning = Tuning()
        tuning.kernelBandwidth = 0
        tuning.confidenceCountHalfLife = 0
        tuning.confidenceSupportHalfLife = 0
        tuning.confidenceSignalHalfLife = 0
        tuning.scales.swellHeightMeters = 0
        tuning.scales.windSpeedKph = 0
        tuning.priorStrength = -5
        tuning.neighbourCount = -1
        tuning.confidenceNeighbourCount = 0
        tuning.maxWindows = -3
        tuning.hourDurationSeconds = -3600
        tuning.durationBonusPerExtraHour = -1

        var rng = SeededRNG(seed: 31)
        let forecast = WindowFixtures.forecast(hours: 24, rng: &rng)
        let hours = WindowScorer.scoreHours(forecast: forecast, history: Self.goodHistory(), tuning: tuning)
        XCTAssertTrue(hours.allSatisfy { $0.isFinite })
        XCTAssertTrue(hours.allSatisfy { (0...5).contains($0.predictedRating) })
        XCTAssertTrue(hours.allSatisfy { (0...1).contains($0.confidence) })
        XCTAssertTrue(WindowScorer.rank(forecast: forecast, history: Self.goodHistory(), tuning: tuning)
            .allSatisfy { $0.isFinite })
    }

    func testDuplicateAndUnsortedForecastHoursAreNormalised() {
        var rng = SeededRNG(seed: 44)
        let forecast = WindowFixtures.forecast(hours: 12, rng: &rng)
        let scrambled = (forecast.reversed() + forecast).map { $0 }

        let hours = WindowScorer.scoreHours(forecast: scrambled, history: Self.goodHistory())
        XCTAssertEqual(hours.count, 12, "duplicates were not removed, got \(hours.count)")
        for (a, b) in zip(hours, hours.dropFirst()) {
            XCTAssertLessThan(a.date, b.date, "output is not chronological")
        }
    }

    func testSingleForecastHourIsHandled() {
        var rng = SeededRNG(seed: 55)
        let forecast = Array(WindowFixtures.forecast(hours: 1, rng: &rng))
        let hours = WindowScorer.scoreHours(forecast: forecast, history: Self.goodHistory())
        XCTAssertEqual(hours.count, 1)
        XCTAssertTrue(hours[0].isFinite)
        XCTAssertTrue(WindowScorer.rank(forecast: forecast, history: Self.goodHistory())
            .allSatisfy { $0.hourCount == 1 && $0.isFinite })
    }

    // MARK: Determinism

    func testIdenticalInputProducesIdenticalOutput() {
        for seed in 0..<25 {
            let s = WindowScenario(seed: 6100 + UInt64(seed), historyCount: 45,
                                   historyPuncture: 0.3)
            let first = WindowScorer.rank(forecast: s.forecast, history: s.history)
            let second = WindowScorer.rank(forecast: s.forecast, history: s.history)
            XCTAssertEqual(first, second, "rank() was not deterministic at seed \(seed)")

            let hoursA = WindowScorer.scoreHours(forecast: s.forecast, history: s.history)
            let hoursB = WindowScorer.scoreHours(forecast: s.forecast, history: s.history)
            XCTAssertEqual(hoursA, hoursB, "scoreHours() was not deterministic at seed \(seed)")
        }
    }

    func testReorderingHistoryDoesNotChangeTheResult() {
        for seed in 0..<15 {
            let s = WindowScenario(seed: 6200 + UInt64(seed), historyCount: 40)
            let forward = WindowScorer.rank(forecast: s.forecast, history: s.history)
            let backward = WindowScorer.rank(forecast: s.forecast, history: s.history.reversed())

            XCTAssertEqual(forward.count, backward.count, "window count changed with history order")
            for (a, b) in zip(forward, backward) {
                XCTAssertTrue(a.start == b.start && a.end == b.end, "window bounds moved with history order")
                XCTAssertLessThan(
                    abs(a.predictedRating - b.predictedRating), 1e-9,
                    "rating moved with history order: \(a.predictedRating) vs \(b.predictedRating)"
                )
                XCTAssertLessThan(abs(a.confidence - b.confidence), 1e-9)
            }
        }
    }

    func testTiesAreBrokenDeterministically() {
        // Two history entries with identical conditions and different ratings: the
        // tie-break must always pick the same one.
        let conditions = ConditionsSample(
            swellWaveHeightMeters: 1.5, swellWavePeriodSeconds: 13,
            windSpeedKph: 5, windDirectionDegrees: 40, seaLevelHeightMeters: 0.2
        )
        let history = (0..<10).map {
            RatedSession(date: Self.base.addingTimeInterval(Double(-$0) * 86_400),
                         rating: $0 % 2 == 0 ? 5 : 2, conditions: conditions)
        }
        let results = (0..<10).map {
            _ in WindowScorer.evaluate(conditions: conditions, history: history)
        }
        XCTAssertEqual(Set(results.map { $0.bestMatch?.date }).count, 1, "tie-break was unstable")
        XCTAssertEqual(Set(results.map { $0.predictedRating }).count, 1)
    }

    // MARK: Invariants

    func testOutputInvariantsHoldAcrossAWideSweep() {
        var checkedWindows = 0
        var checkedHours = 0

        for seed in 0..<40 {
            for count in [0, 1, 3, 12, 45] {
                for puncture in [0.0, 0.35, 0.7] {
                    let s = WindowScenario(seed: 7000 + UInt64(seed), historyCount: count,
                                           historyPuncture: puncture, forecastPuncture: puncture)

                    for hour in WindowScorer.scoreHours(forecast: s.forecast, history: s.history) {
                        checkedHours += 1
                        XCTAssertTrue(
                            hour.predictedRating >= 0 && hour.predictedRating <= 5,
                            "predictedRating \(hour.predictedRating) out of 0...5"
                        )
                        XCTAssertTrue(
                            hour.confidence >= 0 && hour.confidence <= 1,
                            "confidence \(hour.confidence) out of 0...1"
                        )
                        XCTAssertTrue(hour.bestMatchWeight >= 0 && hour.bestMatchWeight <= 1)
                        XCTAssertTrue(hour.isFinite)
                        // Never an unexplained number: a best match implies factors,
                        // and factors imply a best match.
                        if !hour.matchFactors.isEmpty { XCTAssertNotNil(hour.bestMatch) }
                    }

                    let windows = WindowScorer.rank(forecast: s.forecast, history: s.history)
                    XCTAssertLessThanOrEqual(windows.count, Tuning().maxWindows)

                    for window in windows {
                        checkedWindows += 1
                        XCTAssertTrue(
                            window.predictedRating >= 0 && window.predictedRating <= 5,
                            "window rating \(window.predictedRating) out of 0...5"
                        )
                        XCTAssertTrue(
                            window.confidence >= 0 && window.confidence <= 1,
                            "window confidence \(window.confidence) out of 0...1"
                        )
                        XCTAssertGreaterThan(window.end, window.start, "window has non-positive duration")
                        XCTAssertGreaterThanOrEqual(window.hourCount, 1)
                        XCTAssertTrue(window.isFinite)
                        XCTAssertGreaterThanOrEqual(
                            window.predictedRating, Tuning().minWindowRating - 1e-9,
                            "window below the rating floor was returned"
                        )
                        XCTAssertNotNil(window.bestMatch, "unexplained window")
                        XCTAssertFalse(window.matchFactors.isEmpty, "unexplained window")
                    }

                    // Ranked best-first, and pairwise disjoint in time.
                    for (a, b) in zip(windows, windows.dropFirst()) {
                        XCTAssertGreaterThanOrEqual(a.rankScore, b.rankScore - 1e-12, "windows out of rank order")
                    }
                    let chronological = windows.sorted { $0.start < $1.start }
                    for (a, b) in zip(chronological, chronological.dropFirst()) {
                        XCTAssertLessThanOrEqual(
                            a.end, b.start,
                            "overlapping windows \(a.start)-\(a.end) and \(b.start)-\(b.end)"
                        )
                    }
                }
            }
        }

        XCTAssertGreaterThan(checkedHours, 5000, "only \(checkedHours) hours exercised")
        XCTAssertGreaterThan(checkedWindows, 100, "only \(checkedWindows) windows exercised")
    }

    func testEveryWindowsHoursComeFromTheForecastItWasGiven() {
        for seed in 0..<30 {
            let s = WindowScenario(seed: 7500 + UInt64(seed), historyCount: 45)
            let dates = Set(s.forecast.map { $0.date })
            for window in WindowScorer.rank(forecast: s.forecast, history: s.history) {
                let covered = dates.filter { $0 >= window.start && $0 < window.end }
                XCTAssertEqual(
                    covered.count, window.hourCount,
                    "window claims \(window.hourCount) hours but covers \(covered.count)"
                )
                XCTAssertTrue(
                    window.bestMatch.map { s.history.contains($0) } ?? false,
                    "best match is not a session from the supplied history"
                )
            }
        }
    }

    /// The app must never block the main actor on this. Proves the `@concurrent`
    /// entry point agrees with the synchronous one it wraps.
    func testOffMainRankingMatchesSynchronousRanking() async {
        for seed in 0..<5 {
            let s = WindowScenario(seed: 8800 + UInt64(seed), historyCount: 45)
            let sync = WindowScorer.rank(forecast: s.forecast, history: s.history)
            let async = await WindowScorer.rankOffMain(forecast: s.forecast, history: s.history)
            XCTAssertEqual(sync, async, "rankOffMain disagreed with rank at seed \(seed)")
        }
    }
}

// MARK: - App bindings

/// Covers the glue between the logbook and the scorer, plus the one thing the UI
/// test cannot check for itself: that the fixture it runs against is genuinely
/// capable of producing the state it asserts on.
final class TodayWindowServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: PeakSchemaV9.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func makeSpot(_ name: String, located: Bool, in context: ModelContext) -> Spot {
        let spot = located
            ? Spot(name: name, latitude: 33.38, longitude: -117.59)
            : Spot(name: name)
        context.insert(spot)
        return spot
    }

    private func addSessions(_ count: Int, at spot: Spot, from base: Date, in context: ModelContext) {
        for index in 0..<count {
            let session = SurfSession(
                date: base.addingTimeInterval(Double(-index) * 86_400),
                spot: spot,
                rating: index % 5
            )
            context.insert(session)
        }
    }

    // MARK: Favourite spots

    func testFavouriteSpotsRanksByHowOftenTheSpotIsSurfed() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let home = makeSpot("Home Break", located: true, in: context)
        let backup = makeSpot("Backup", located: true, in: context)
        let rare = makeSpot("Rare Trip", located: true, in: context)

        addSessions(9, at: home, from: base, in: context)
        addSessions(4, at: backup, from: base, in: context)
        addSessions(1, at: rare, from: base, in: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        let favourites = TodayWindowService.favouriteSpots(sessions: sessions)
        XCTAssertEqual(favourites.map(\.name), ["Home Break", "Backup", "Rare Trip"])
    }

    /// Without coordinates there is no forecast to fetch, so an unlocated spot is
    /// not a candidate however often it is surfed.
    func testSpotsWithoutCoordinatesAreNotCandidates() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let unlocated = makeSpot("Secret Spot", located: false, in: context)
        let located = makeSpot("Mapped Spot", located: true, in: context)

        addSessions(20, at: unlocated, from: base, in: context)
        addSessions(2, at: located, from: base, in: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        let favourites = TodayWindowService.favouriteSpots(sessions: sessions)
        XCTAssertEqual(favourites.map(\.name), ["Mapped Spot"])
    }

    func testFavouriteSpotsRespectsItsLimitAndHandlesAnEmptyLog() {
        XCTAssertTrue(TodayWindowService.favouriteSpots(sessions: []).isEmpty)
        XCTAssertTrue(TodayWindowService.favouriteSpots(sessions: [], limit: 0).isEmpty)
    }

    func testFavouriteSpotOrderIsStableAcrossRepeatedCalls() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        // Deliberately tied on session count, so only the tie-break can order them.
        let a = makeSpot("Alpha", located: true, in: context)
        let b = makeSpot("Beta", located: true, in: context)
        addSessions(5, at: a, from: base, in: context)
        addSessions(5, at: b, from: base, in: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        let first = TodayWindowService.favouriteSpots(sessions: sessions).map(\.name)
        for _ in 0..<10 {
            XCTAssertEqual(
                TodayWindowService.favouriteSpots(sessions: sessions).map(\.name), first,
                "favourite spot order shuffled between calls"
            )
        }
    }

    // MARK: History mapping

    /// The premise of the whole feature is that this spot's own history models this
    /// spot. Leaking another break's sessions in would quietly destroy that.
    func testRatedHistoryOnlyIncludesSessionsAtTheChosenSpot() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let here = makeSpot("Here", located: true, in: context)
        let elsewhere = makeSpot("Elsewhere", located: true, in: context)
        addSessions(6, at: here, from: base, in: context)
        addSessions(9, at: elsewhere, from: base, in: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(TodayWindowService.ratedHistory(sessions: sessions, at: here).count, 6)
        XCTAssertEqual(TodayWindowService.ratedHistory(sessions: sessions, at: elsewhere).count, 9)
    }

    func testRatedHistoryCarriesTideAndSessionIdentity() throws {
        let context = try makeContext()
        let spot = makeSpot("Tidal Reef", located: true, in: context)
        let session = SurfSession(date: Date(timeIntervalSince1970: 1_750_000_000), spot: spot, rating: 5)
        session.swellWaveHeightMeters = 1.4
        session.seaLevelHeightM = 0.42
        session.tide = .falling
        context.insert(session)

        let history = TodayWindowService.ratedHistory(
            sessions: try context.fetch(FetchDescriptor<SurfSession>()), at: spot)
        let mapped = try XCTUnwrap(history.first)
        XCTAssertEqual(mapped.conditions.tideTrend, .falling)
        XCTAssertEqual(mapped.conditions.seaLevelHeightMeters ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(mapped.rating, 5)
        // The identifier is what makes the card's "similar to your 5-star session"
        // tappable through to the real thing.
        XCTAssertEqual(mapped.sessionID, session.persistentModelID)
    }

    // MARK: The UI-test fixture is genuinely capable

    /// The UI test asserts that a recommendation appears. That assertion is only
    /// meaningful if the seeded history and the mocked forecast really do clear the
    /// confidence gate, which is a property of the algorithm's tuning, not of the
    /// view. Asserted here so a tuning change fails loudly in the fast suite rather
    /// than silently turning the UI test into a test of nothing.
    func testSeededUITestHistoryProducesAConfidentWindow() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let spot = makeSpot("Trestles", located: true, in: context)
        for session in PreviewData.windowHistory(at: spot, baseDate: base) {
            context.insert(session)
        }

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        let history = TodayWindowService.ratedHistory(sessions: sessions, at: spot)
        let forecast = SurfConditionsService.mockForecastHours(start: base, hours: 24)
        let windows = WindowScorer.rank(forecast: forecast, history: history)

        let top = try XCTUnwrap(
            windows.first,
            "the UI-test fixture produced no window, so the UI test would be asserting on nothing"
        )
        XCTAssertGreaterThanOrEqual(top.confidence, Tuning().minConfidence)
        XCTAssertGreaterThanOrEqual(top.predictedRating, Tuning().minWindowRating)
        XCTAssertNotNil(top.bestMatch, "the card needs a session to cite")
        XCTAssertFalse(top.matchFactors.isEmpty, "the card needs factors to show")

        // The mock day is glassy at dawn and blown out by afternoon, so the window
        // must land in the morning. If it did not, the fixture would not be
        // exercising the behaviour it claims to.
        let hourOffset = Int(top.start.timeIntervalSince(base) / 3600)
        XCTAssertLessThan(hourOffset, 8, "best window landed \(hourOffset) h in, not in the morning glass")
    }

    /// The mirror image: the default four-session seed must NOT produce a window.
    /// This is the low-confidence UI state, and it has to be genuinely reachable.
    func testDefaultSeedHistoryIsHonestlyTooThinForAWindow() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let spot = makeSpot("Trestles", located: true, in: context)
        let session = SurfSession(date: base, spot: spot, rating: 5)
        session.swellWaveHeightMeters = 1.2
        session.swellWavePeriodSeconds = 12
        session.windSpeedKph = 8
        context.insert(session)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        let history = TodayWindowService.ratedHistory(sessions: sessions, at: spot)
        let forecast = SurfConditionsService.mockForecastHours(start: base, hours: 24)

        XCTAssertTrue(
            WindowScorer.rank(forecast: forecast, history: history).isEmpty,
            "a single rated session produced a recommendation"
        )
    }

    // MARK: Mock forecast shape

    func testMockForecastIsAWholeDayOfUsableHours() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let forecast = SurfConditionsService.mockForecastHours(start: base, hours: 24)

        XCTAssertEqual(forecast.count, 24)
        XCTAssertTrue(forecast.allSatisfy { $0.conditions.swellWaveHeightMeters != nil })
        XCTAssertTrue(forecast.allSatisfy { $0.conditions.windSpeedKph != nil })
        XCTAssertTrue(forecast.allSatisfy { $0.conditions.tideTrend != nil })
        // Wind builds through the day, which is what makes dawn the answer.
        let firstWind = forecast.first?.conditions.windSpeedKph ?? 0
        let lastWind = forecast.last?.conditions.windSpeedKph ?? 0
        XCTAssertLessThan(firstWind, lastWind)
    }

    func testMockForecastScenariosSurfaceErrorsRatherThanEmptyData() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertThrowsError(try SurfConditionsService.mockDayForecast(for: "error", start: base, hours: 24))
        XCTAssertThrowsError(try SurfConditionsService.mockDayForecast(for: "no_data", start: base, hours: 24))
        XCTAssertNoThrow(try SurfConditionsService.mockDayForecast(for: "confident", start: base, hours: 24))
    }
}
