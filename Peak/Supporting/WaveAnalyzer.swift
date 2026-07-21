import Foundation

// MARK: - Input

/// A single GPS fix from a surf workout's route.
///
/// This mirrors the subset of `CLLocation` that matters for surf analysis, but
/// deliberately does **not** import CoreLocation so the algorithm stays testable
/// on any platform (Linux CI, command-line harnesses, synthetic fixtures).
///
/// Mapping from CoreLocation is one-to-one:
/// ```swift
/// RouteSample(
///     timestamp: loc.timestamp,
///     latitude: loc.coordinate.latitude,
///     longitude: loc.coordinate.longitude,
///     speedMetersPerSecond: loc.speed,          // CoreLocation uses -1 for "unknown"
///     horizontalAccuracyMeters: loc.horizontalAccuracy,
///     courseDegrees: loc.course                 // CoreLocation uses -1 for "unknown"
/// )
/// ```
/// Negative sentinel values are handled internally, so callers never need to
/// pre-clean CoreLocation's `-1` conventions.
nonisolated public struct RouteSample: Sendable, Equatable {
    /// Wall-clock time of the fix.
    public var timestamp: Date
    /// Degrees, WGS-84.
    public var latitude: Double
    /// Degrees, WGS-84.
    public var longitude: Double
    /// Device-reported ground speed. `nil` or negative means "not available";
    /// the analyzer then derives speed geometrically.
    public var speedMetersPerSecond: Double?
    /// Radius of 68% confidence. Negative means the fix is invalid entirely.
    public var horizontalAccuracyMeters: Double
    /// Device-reported course over ground, degrees clockwise from true north.
    /// `nil` or negative means "not available".
    public var courseDegrees: Double?

    public init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        speedMetersPerSecond: Double? = nil,
        horizontalAccuracyMeters: Double,
        courseDegrees: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedMetersPerSecond = speedMetersPerSecond
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.courseDegrees = courseDegrees
    }
}

// MARK: - Output

/// One detected ride.
///
/// `startIndex` / `endIndex` refer to positions in the **original, caller-supplied**
/// sample array (not the internally filtered one), so a UI can highlight the exact
/// fixes that make up the ride on a map.
///
/// "Start" and "end" mean *earliest* and *latest in time*. Samples are sorted by
/// timestamp before analysis, so if the caller passes an array that is not already
/// in chronological order, `startIndex` may be numerically greater than `endIndex`.
/// `startTime <= endTime` always holds.
nonisolated public struct WaveSegment: Sendable, Equatable {
    /// Index into the caller's input array of the first fix in the ride.
    public var startIndex: Int
    /// Index into the caller's input array of the last fix in the ride.
    public var endIndex: Int
    public var startTime: Date
    public var endTime: Date
    /// Highest smoothed speed observed inside the ride, m/s.
    public var peakSpeedMetersPerSecond: Double
    /// Ground distance covered, summed only over *trusted* links (see `Tuning`).
    public var distanceMeters: Double
    /// `endTime - startTime`, seconds.
    public var durationSeconds: Double

    public init(
        startIndex: Int,
        endIndex: Int,
        startTime: Date,
        endTime: Date,
        peakSpeedMetersPerSecond: Double,
        distanceMeters: Double,
        durationSeconds: Double
    ) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.startTime = startTime
        self.endTime = endTime
        self.peakSpeedMetersPerSecond = peakSpeedMetersPerSecond
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

/// Per-session surf statistics.
nonisolated public struct WaveStats: Sendable, Equatable {
    public var waveCount: Int
    public var topSpeedKph: Double
    public var longestRideSeconds: Double
    /// Distance of the ride with the greatest *duration* — deliberately the same
    /// ride that `longestRideSeconds` describes, so the two numbers agree.
    public var longestRideMeters: Double
    /// Distance travelled while moving, but below wave speed (i.e. paddling out,
    /// paddling for position). Excludes anything inside a detected ride.
    public var paddleDistanceMeters: Double
    /// All trusted ground distance in the session, regardless of activity.
    public var totalDistanceMeters: Double
    public var waves: [WaveSegment]

    /// All-zero statistics. Returned for empty / unusable input.
    public static let zero = WaveStats(
        waveCount: 0,
        topSpeedKph: 0,
        longestRideSeconds: 0,
        longestRideMeters: 0,
        paddleDistanceMeters: 0,
        totalDistanceMeters: 0,
        waves: []
    )

    public init(
        waveCount: Int,
        topSpeedKph: Double,
        longestRideSeconds: Double,
        longestRideMeters: Double,
        paddleDistanceMeters: Double,
        totalDistanceMeters: Double,
        waves: [WaveSegment]
    ) {
        self.waveCount = waveCount
        self.topSpeedKph = topSpeedKph
        self.longestRideSeconds = longestRideSeconds
        self.longestRideMeters = longestRideMeters
        self.paddleDistanceMeters = paddleDistanceMeters
        self.totalDistanceMeters = totalDistanceMeters
        self.waves = waves
    }
}

// MARK: - Analyzer

/// Stateless surf-session analyzer.
///
/// `WaveAnalyzer` turns a gappy, noisy Apple Watch GPS route into wave count,
/// top speed, ride lengths and paddle distance.
///
/// ### Why this is not just "speed > threshold"
/// GPS does not work underwater. A surf watch only gets fixes when the wrist
/// clears the surface, so the raw track is a sequence of short, well-sampled
/// bursts separated by dropouts of unpredictable length, sprinkled with
/// single-sample position spikes from partially-obstructed fixes. Naive
/// thresholding on such a track produces two classic failure modes seen in
/// shipping surf apps:
///
/// 1. **Phantom waves** — a lone bad fix implies 12 m/s for one sample and is
///    logged as a ride. Defended against in depth: median smoothing removes
///    isolated spikes, derived speed is fitted over a window and de-biased for
///    its own noise floor, a ride must hold wave speed for a sustained stretch
///    rather than merely touch it once, and its heading must stay consistent.
/// 2. **Absurd ride distances** — a 40 ft ride logged as 350 ft because the
///    watch lost the wrist for 20 s and the straight line across the dropout was
///    counted as travel. Defended against by refusing to accumulate distance or
///    continue a ride across an untrusted link, and by integrating distance from
///    speed rather than summing noise-inflated position differences.
///
/// ### Bias
/// Where the evidence is genuinely ambiguous the analyzer prefers to *miss* a
/// marginal ride rather than invent one. An invented wave is a visible lie in
/// the UI; a missed marginal one is a small undercount the surfer will not
/// notice. Several thresholds are set with that asymmetry in mind.
///
/// The analyzer is a pure function: same input always yields the same output,
/// no randomness, no shared state, safe to call from any actor or task.
nonisolated public enum WaveAnalyzer {

    // MARK: Tuning

    /// Every tunable constant in the algorithm.
    ///
    /// Defaults are physically-reasoned starting points, **not** ocean-validated
    /// numbers. They live here as a single struct so the whole model can be
    /// re-fit against real recorded sessions without touching a line of logic.
    nonisolated public struct Tuning: Sendable, Equatable {

        // ---- Fix quality -------------------------------------------------

        /// Fixes with a 68% confidence radius worse than this are discarded.
        ///
        /// Rationale: a surf ride is 20–150 m long. At worse than ~20 m accuracy
        /// the positional error is a meaningful fraction of the ride itself, and
        /// derived speed becomes dominated by noise. Apple Watch GPS in the open
        /// ocean typically reports 5–15 m; anything much worse is a fix taken
        /// with the wrist half-submerged. Negative accuracy (CoreLocation's
        /// "invalid" sentinel) is always dropped.
        public var maxHorizontalAccuracyMeters: Double = 20

        // ---- Time continuity ---------------------------------------------

        /// Longest gap between consecutive surviving fixes that is still treated
        /// as continuous motion.
        ///
        /// Rationale: this is the single most important constant for avoiding
        /// inflated ride distances. Watch GPS on a wrist that is mostly in the
        /// water routinely misses 1–3 samples; bridging up to ~5 s keeps real
        /// rides intact. Beyond that we genuinely do not know what the surfer
        /// did — they may have wiped out and drifted — so the straight-line
        /// interpolation is not evidence and is thrown away: no distance is
        /// accumulated and any in-progress ride is terminated.
        public var maxBridgeableGapSeconds: Double = 5.0

        /// A link whose implied speed exceeds this — after allowing for the
        /// reported position uncertainty of its endpoints — is treated as a
        /// teleport (position spike, or a jump across dropped low-accuracy
        /// fixes). Such a link is excluded from distance *and* breaks ride
        /// continuity.
        ///
        /// Rationale: 15 m/s = 54 km/h. Nothing on a surfboard, including a
        /// tow-in, sustains that between two consecutive fixes; if the geometry
        /// says otherwise, the geometry is wrong.
        public var maxPlausibleLinkSpeedMetersPerSecond: Double = 15.0

        /// How many multiples of the endpoints' reported accuracy to add to the
        /// plausible-displacement budget before calling a link a teleport.
        ///
        /// Rationale: a pure speed cap is wrong at 1 Hz. Two fixes 1 s apart
        /// with 10 m accuracy each can differ by 20 m of pure measurement error
        /// while the surfer barely moved — that is 20 m/s of *apparent* speed
        /// with no teleport involved. Rejecting those links would shred real
        /// rides into fragments and inflate the wave count. The budget is
        /// therefore `maxSpeed × Δt + slack × (accuracyA + accuracyB)`, which
        /// scales with how much the fixes admit they might be wrong. 1.5 keeps
        /// genuine multi-hundred-metre jumps out while tolerating noise.
        public var linkAccuracySlackSigmas: Double = 1.5

        // ---- Speed estimation --------------------------------------------

        /// Time span of the regression window used to derive speed from
        /// positions when the device supplies no speed value, seconds.
        ///
        /// Rationale: differentiating two consecutive 1 Hz fixes is unusable in
        /// practice. With 4 m position noise, the *differential* error is ~5.7 m,
        /// so a surfer sitting perfectly still measures 5.7 m/s — well above the
        /// wave threshold. Fitting a least-squares velocity across a ~5 s window
        /// divides that error by roughly √Σ(t−t̄)², bringing a stationary
        /// surfer back under 1 m/s while a real 6 m/s ride is barely touched.
        /// Longer windows suppress more noise but blur short rides, so this
        /// trades directly against `minWaveDurationSeconds`.
        ///
        /// 5 s is chosen to stay close to `minWaveDurationSeconds` so the
        /// shortest ride the analyzer will report is still temporally resolved.
        public var derivedSpeedWindowSeconds: Double = 5.0

        /// Fraction of the reported horizontal accuracy treated as the
        /// *differential* position error when de-biasing derived speed, 0…1.
        ///
        /// Rationale: consecutive fixes share satellites, ephemeris and
        /// ionospheric conditions, so their errors are strongly correlated. The
        /// error that matters over a few seconds is much smaller than the
        /// absolute 68% radius the device reports — treating the full accuracy
        /// as independent noise would over-subtract and erase real rides. 0.5 is
        /// a deliberately conservative middle: it removes most of the stationary
        /// noise floor while leaving genuine ride speed intact.
        ///
        /// Empirically, 0.65 was the point at which synthetic sessions at σ = 3 m
        /// with no device speed stopped producing phantom rides during paddling
        /// without starting to lose real ones. This constant is the single most
        /// likely to need re-fitting against real ocean data, because it encodes
        /// an assumption about how correlated successive fix errors are — which
        /// depends on the watch, the sky view, and how wet the wrist is.
        public var derivedSpeedNoiseCompensation: Double = 0.65

        /// Whether reported distances are integrated from speed (`true`) or
        /// summed from position differences (`false`).
        ///
        /// Rationale: summing haversine distances between consecutive noisy
        /// fixes systematically *inflates* distance, because every wiggle of
        /// measurement error adds path length that was never travelled. At 1 Hz
        /// with 3 m noise, a surfer paddling 300 m accumulates roughly 900 m of
        /// apparent track. Integrating speed over the same links avoids this:
        /// the speed series has already had its noise floor removed, so error
        /// cancels instead of accumulating. This is the same reason running
        /// watches report Doppler-integrated distance rather than GPS-polyline
        /// length. Distance is still only accumulated over *trusted* links, so
        /// gap handling is identical either way. Set to `false` to compare
        /// against raw track length when validating against real recordings.
        public var usesSpeedIntegratedDistance: Bool = true

        /// Window (in samples) of the rolling **median** applied to the speed
        /// series before detection. Must be odd; 1 disables it.
        ///
        /// Rationale: a median is chosen over a mean specifically because a
        /// single-sample GPS spike survives averaging (one 10 m/s sample among
        /// 1 m/s neighbours averages to ~4 m/s — above the wave threshold) but
        /// is annihilated by a median. This is the primary spike defence.
        public var medianWindowSamples: Int = 3

        /// Window (in samples) of the moving average applied *after* the median.
        /// Must be odd; 1 disables it.
        ///
        /// Rationale: the median removes outliers but leaves the ±1σ jitter of
        /// geometrically-derived speed. A short mean reduces that variance by
        /// ~√window while blurring ride edges by well under a second at 1 Hz.
        public var meanWindowSamples: Int = 3

        // ---- Ride detection ----------------------------------------------

        /// Speed at which a ride is considered to have started. m/s.
        ///
        /// Rationale: 2.2 m/s ≈ 8 km/h. Sustained paddling on a shortboard tops
        /// out around 1.5–2 m/s; even a strong paddler catching a wave crosses
        /// this only once the wave is doing the work. Set it lower and paddle
        /// sprints become "waves".
        public var waveEnterSpeedMetersPerSecond: Double = 2.2

        /// Speed below which an in-progress ride is considered over. m/s.
        ///
        /// Rationale: hysteresis. Real rides have a slow section — the bottom of
        /// a turn, a flat spot, a reform — where speed dips briefly. A single
        /// exit threshold equal to the entry threshold chops one wave into
        /// three. 1.5 m/s is above drift/paddle speed but below anything that
        /// still counts as being carried by a wave.
        public var waveExitSpeedMetersPerSecond: Double = 1.5

        /// Minimum number of surviving fixes a ride must contain.
        ///
        /// Rationale: this is an *evidence* floor, distinct from the duration
        /// floor next to it, which is a definition of what surfers call a ride.
        /// A burst of four fixes surrounded by dropouts contains barely enough
        /// information to fit a velocity, let alone confirm one; the chance that
        /// noise alone lines up into something ride-shaped over so few points is
        /// not small. Requiring five fixes costs nothing on a 1 Hz watch (it is
        /// 4 s of observation, close to the duration floor anyway) and removes
        /// the whole class of phantom waves that live in short isolated bursts.
        /// At sampling rates much slower than 1 Hz this becomes the binding
        /// constraint and should be lowered.
        public var minWaveSampleCount: Int = 5

        /// Minimum ride duration, seconds.
        ///
        /// Rationale: nobody logs a 1-second wave, and at 1 Hz sampling a 3 s
        /// floor forces at least 3–4 corroborating fixes before anything is
        /// called a ride. This is the second line of defence against noise.
        public var minWaveDurationSeconds: Double = 3.0

        /// How long a candidate must hold a speed at or above the *entry*
        /// threshold, seconds, counted only over contiguous stretches.
        ///
        /// Rationale: without this, a ride qualifies on a single sample touching
        /// the entry threshold and then coasts to its required duration on the
        /// much lower exit threshold — so the only real evidence is one noisy
        /// reading. Because smoothing correlates neighbouring samples, noise
        /// excursions readily produce exactly that shape, and the wave count
        /// climbs with GPS noise instead of staying flat. A genuine ride spends
        /// most of its length well above the entry threshold, so demanding a
        /// couple of seconds there separates the two cleanly while leaving the
        /// hysteresis free to do its real job: measuring the ride's full extent
        /// once it has been believed.
        ///
        /// 2.5 s means "three whole seconds" at the 1 Hz a watch samples at,
        /// while staying a genuine time threshold at other sample rates.
        public var minSustainedAboveEntrySeconds: Double = 2.5

        /// Two candidate rides separated by less than this are merged into one.
        ///
        /// Rationale: even with hysteresis, a deep speed trough (a wipeout-and-
        /// recover, or a section the surfer pumps through) can drop below the
        /// exit threshold for a sample or two. Merging across ≤2 s keeps a wave
        /// counted once. Merging is never allowed across an untrusted link.
        public var maxWaveMergeGapSeconds: Double = 2.0

        /// Rides whose peak smoothed speed exceeds this are discarded outright,
        /// and speeds above it never contribute to `topSpeedKph`. m/s.
        ///
        /// Rationale: 14 m/s ≈ 50 km/h. World-record surfing speeds on giant
        /// waves are in the 40–50 km/h range and are not what a recreational
        /// session contains. Anything faster is GPS error that got past the
        /// median filter (i.e. two or more consecutive bad fixes).
        public var maxPlausibleWaveSpeedMetersPerSecond: Double = 14.0

        // ---- Directional consistency --------------------------------------

        /// Whether to require a ride to hold a roughly consistent heading.
        public var requiresDirectionalConsistency: Bool = true

        /// Minimum distance-weighted circular resultant length, 0…1, for a
        /// candidate ride to be accepted.
        ///
        /// Rationale: a real ride tracks toward shore — its per-link headings
        /// cluster, so the resultant of the unit heading vectors is long
        /// (typically >0.85, and >0.6 even with several metres of position
        /// noise). A burst of GPS scatter while sitting produces near-uniform
        /// headings and a resultant near 0. Weighting each heading by its link
        /// distance makes the statistic equivalent to "net displacement ÷ path
        /// length", which is exactly the physical property we mean by
        /// "held a line".
        ///
        /// On the value: for `n` randomly-oriented links the resultant is
        /// roughly `0.9/√n` by chance alone, so a 4-link candidate scores ~0.45
        /// with no real motion at all. The threshold therefore cannot be pushed
        /// far above that without rejecting genuine short rides, and it is not
        /// meant to carry scatter rejection alone — the de-biased speed
        /// estimate upstream does most of that work. 0.45 is the point where
        /// synthetic scatter stops passing and real rides still do.
        public var minHeadingResultantLength: Double = 0.45

        /// Minimum number of trusted links in a candidate before the directional
        /// test is applied at all.
        ///
        /// Rationale: heading data is only meaningful with several corroborating
        /// links. With 1–2 links the resultant is trivially ~1 and the test is
        /// vacuous, so we neither trust nor apply it — the duration and speed
        /// gates carry those cases.
        public var minHeadingLinksForCheck: Int = 3

        /// Links shorter than this contribute no heading information when the
        /// bearing has to be derived from geometry.
        ///
        /// Rationale: bearing error scales as atan(positionNoise / linkDistance).
        /// Below ~3 m of travel the derived bearing is essentially random at
        /// realistic noise levels, so including such links would only inject
        /// noise into the resultant. Device-reported course is not subject to
        /// this limit — it is Doppler-derived, not differential.
        public var minHeadingLinkDistanceMeters: Double = 3.0

        /// Fraction of a candidate's path length that must carry usable heading
        /// information before the directional test is considered applicable.
        ///
        /// Rationale: judging a ride's straightness from a minority of its
        /// travel is unsound — an absent measurement must not read as a failed
        /// one. Below this coverage the test is skipped entirely and the ride is
        /// accepted or rejected on speed and duration alone.
        public var minHeadingCoverageFraction: Double = 0.5

        // ---- Activity classification --------------------------------------

        /// Speed below which the surfer is considered stationary (sitting on the
        /// board, waiting), so the movement is GPS jitter rather than paddling.
        ///
        /// Rationale: 0.4 m/s is slower than a deliberate paddle stroke but
        /// faster than the apparent motion produced by a few metres of fix
        /// noise at 1 Hz once smoothed. Distance below this floor is excluded
        /// from `paddleDistanceMeters` so a 90-minute session of sitting does
        /// not silently report a kilometre of "paddling".
        public var stationarySpeedMetersPerSecond: Double = 0.4

        public init() {}
    }

    // MARK: Public API

    /// Analyze a surf workout route.
    ///
    /// - Parameters:
    ///   - samples: Route fixes in any order (they are sorted by timestamp
    ///     internally). May be empty, may contain invalid or non-finite values.
    ///   - tuning: Algorithm constants. Defaults are documented on `Tuning`.
    /// - Returns: Session statistics. Never throws, never traps, and never
    ///   contains NaN or infinity — unusable input yields `WaveStats.zero`.
    public static func analyze(
        samples: [RouteSample],
        tuning: Tuning = Tuning()
    ) -> WaveStats {
        let tuning = sanitized(tuning)

        // 1. Drop unusable fixes and put the rest in time order.
        let clean = cleanedSamples(samples, tuning: tuning)
        guard clean.count >= 2 else { return .zero }

        // 2. Describe the motion between each consecutive pair of fixes, and
        //    decide which of those links we are willing to believe.
        let links = buildLinks(clean, tuning: tuning)

        // 3. Split into runs of uninterrupted, trusted motion. All detection
        //    happens inside a run; a run boundary is a hard stop.
        let runs = contiguousRuns(linkCount: links.count, links: links)

        // 4. Per-sample speed, then smoothing — done per run so a dropout never
        //    lets one burst's speeds leak into the next.
        let speeds = smoothedSpeeds(clean, links: links, runs: runs, tuning: tuning)

        // 5. The distance credited to each link, which is a different question
        //    from how far apart its endpoints appear to be.
        let distances = reportedDistances(links: links, speeds: speeds, tuning: tuning)

        // 6. Candidate rides, merged and then filtered on physical plausibility.
        let waves = detectWaves(
            clean, links: links, runs: runs, speeds: speeds,
            distances: distances, tuning: tuning
        )

        // 7. Distance bookkeeping.
        return assembleStats(
            clean, links: links, speeds: speeds,
            distances: distances, waves: waves, tuning: tuning
        )
    }

    /// Off-main-thread `analyze`.
    ///
    /// The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a plain
    /// `nonisolated` sync call from a view still runs on the main thread — and a
    /// 90-minute route is tens of thousands of fixes with an O(window) regression
    /// at every one of them. `@concurrent` forces the work onto the cooperative
    /// pool so a long session can never hitch the UI. Every call site that comes
    /// from a view must use this one.
    @concurrent
    public static func analyzeOffMain(
        samples: [RouteSample],
        tuning: Tuning = Tuning()
    ) async -> WaveStats {
        analyze(samples: samples, tuning: tuning)
    }

    // MARK: - Stage 0: tuning hygiene

    /// Clamps caller-supplied tuning into a range where the algorithm's
    /// invariants hold (odd smoothing windows, exit ≤ enter, no NaN).
    /// Defensive rather than corrective: a bad constant should degrade the
    /// result, not crash the app mid-session.
    private static func sanitized(_ t: Tuning) -> Tuning {
        var s = t
        func finite(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

        s.maxHorizontalAccuracyMeters = max(0, finite(t.maxHorizontalAccuracyMeters, 20))
        s.maxBridgeableGapSeconds = max(0, finite(t.maxBridgeableGapSeconds, 5))
        s.maxPlausibleLinkSpeedMetersPerSecond = max(0.1, finite(t.maxPlausibleLinkSpeedMetersPerSecond, 15))
        s.linkAccuracySlackSigmas = max(0, finite(t.linkAccuracySlackSigmas, 1.5))
        s.derivedSpeedWindowSeconds = max(0, finite(t.derivedSpeedWindowSeconds, 5))
        s.derivedSpeedNoiseCompensation = min(1, max(0, finite(t.derivedSpeedNoiseCompensation, 0.5)))
        s.waveEnterSpeedMetersPerSecond = max(0, finite(t.waveEnterSpeedMetersPerSecond, 2.2))
        s.waveExitSpeedMetersPerSecond = min(
            s.waveEnterSpeedMetersPerSecond,
            max(0, finite(t.waveExitSpeedMetersPerSecond, 1.5))
        )
        s.minWaveDurationSeconds = max(0, finite(t.minWaveDurationSeconds, 3))
        s.minWaveSampleCount = max(2, min(1000, t.minWaveSampleCount))
        s.minSustainedAboveEntrySeconds = max(0, finite(t.minSustainedAboveEntrySeconds, 2.5))
        s.maxWaveMergeGapSeconds = max(0, finite(t.maxWaveMergeGapSeconds, 2))
        s.maxPlausibleWaveSpeedMetersPerSecond = max(0.1, finite(t.maxPlausibleWaveSpeedMetersPerSecond, 14))
        s.minHeadingResultantLength = min(1, max(0, finite(t.minHeadingResultantLength, 0.55)))
        s.minHeadingLinksForCheck = max(1, t.minHeadingLinksForCheck)
        s.minHeadingLinkDistanceMeters = max(0, finite(t.minHeadingLinkDistanceMeters, 3))
        s.minHeadingCoverageFraction = min(1, max(0, finite(t.minHeadingCoverageFraction, 0.5)))
        s.stationarySpeedMetersPerSecond = max(0, finite(t.stationarySpeedMetersPerSecond, 0.4))

        // Smoothing windows must be odd and ≥1 for the centred-window logic.
        s.medianWindowSamples = normalizedOddWindow(t.medianWindowSamples)
        s.meanWindowSamples = normalizedOddWindow(t.meanWindowSamples)
        return s
    }

    private static func normalizedOddWindow(_ w: Int) -> Int {
        let clamped = max(1, min(31, w))
        return clamped % 2 == 0 ? clamped - 1 : clamped
    }

    // MARK: - Stage 1: fix cleaning

    /// A fix that survived quality filtering, with a back-reference to where it
    /// came from in the caller's array so reported indices stay meaningful.
    private struct CleanSample {
        var originalIndex: Int
        var time: TimeInterval          // seconds since reference date
        var timestamp: Date
        var latitude: Double
        var longitude: Double
        var deviceSpeed: Double?        // already validated
        var course: Double?             // already validated, 0..<360
        var accuracy: Double            // metres, ≥ 0
    }

    private static func cleanedSamples(_ samples: [RouteSample], tuning: Tuning) -> [CleanSample] {
        var out: [CleanSample] = []
        out.reserveCapacity(samples.count)

        for (index, sample) in samples.enumerated() {
            // Reject anything non-finite before it can poison arithmetic downstream.
            guard sample.latitude.isFinite, sample.longitude.isFinite,
                  abs(sample.latitude) <= 90, abs(sample.longitude) <= 180 else { continue }

            let time = sample.timestamp.timeIntervalSinceReferenceDate
            guard time.isFinite else { continue }

            // Accuracy gate. Negative is CoreLocation's "this fix is invalid".
            let accuracy = sample.horizontalAccuracyMeters
            guard accuracy.isFinite, accuracy >= 0,
                  accuracy <= tuning.maxHorizontalAccuracyMeters else { continue }

            // Device speed: honour it only when it is a real measurement.
            var deviceSpeed: Double?
            if let s = sample.speedMetersPerSecond, s.isFinite, s >= 0,
               s <= tuning.maxPlausibleLinkSpeedMetersPerSecond {
                deviceSpeed = s
            }

            // Course: CoreLocation reports -1 when unknown.
            var course: Double?
            if let c = sample.courseDegrees, c.isFinite, c >= 0, c < 360 {
                course = c
            }

            out.append(CleanSample(
                originalIndex: index,
                time: time,
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                deviceSpeed: deviceSpeed,
                course: course,
                accuracy: accuracy
            ))
        }

        // Stable sort by time keeps output deterministic for equal timestamps.
        out.sort { lhs, rhs in
            lhs.time == rhs.time ? lhs.originalIndex < rhs.originalIndex : lhs.time < rhs.time
        }
        return out
    }

    // MARK: - Stage 2: links

    /// The motion between sample `i` and sample `i + 1`.
    ///
    /// Geometry is recorded even for untrusted links. Distance accumulation
    /// ignores them, but the *shape* of a rejected link is still evidence — an
    /// out-and-back position spike is only recognisable if you look at the leg
    /// you refused to believe.
    private struct Link {
        var distance: Double        // metres, straight-line, always populated
        var dt: Double              // seconds
        var bearing: Double?        // degrees from true north, nil if unusable
        var trusted: Bool
    }

    private static func buildLinks(_ s: [CleanSample], tuning: Tuning) -> [Link] {
        var links: [Link] = []
        links.reserveCapacity(max(0, s.count - 1))

        for i in 0..<(s.count - 1) {
            let dt = s[i + 1].time - s[i].time
            let distance = haversineMeters(
                lat1: s[i].latitude, lon1: s[i].longitude,
                lat2: s[i + 1].latitude, lon2: s[i + 1].longitude
            )

            // Duplicate or out-of-order timestamps carry no motion information.
            guard dt > 0, dt.isFinite, distance.isFinite else {
                links.append(Link(distance: 0, dt: max(0, dt), bearing: nil, trusted: false))
                continue
            }

            // Two independent reasons to distrust a link:
            //  - the gap is too long to assume the surfer travelled in a straight
            //    line (submersion, watch off wrist, tunnel of whitewater);
            //  - the displacement is larger than physical motion *plus* the
            //    fixes' own admitted uncertainty can explain, which means at
            //    least one endpoint is a position spike, or that low-accuracy
            //    fixes were dropped between two genuinely distant points.
            // In both cases the honest answer is "unknown", not "a straight line
            // at high speed" — that assumption is what turns a 40 ft ride into a
            // 350 ft one.
            //
            // The accuracy term matters: a flat speed cap applied at 1 Hz would
            // reject ordinary noisy links inside real rides, fragmenting one
            // wave into several and inflating the count.
            let bridgeable = dt <= tuning.maxBridgeableGapSeconds
            let budget = tuning.maxPlausibleLinkSpeedMetersPerSecond * dt
                + tuning.linkAccuracySlackSigmas * (s[i].accuracy + s[i + 1].accuracy)
            let plausible = distance <= budget
            let trusted = bridgeable && plausible

            // Prefer the device's course (Doppler-derived, far better than
            // differential position at these distances); fall back to geometry.
            // An untrusted link keeps its geometric bearing on purpose: that is
            // precisely the leg that reveals a spike as an out-and-back.
            var bearing: Double?
            if let c = s[i].course, trusted {
                bearing = c
            } else if distance >= tuning.minHeadingLinkDistanceMeters {
                bearing = bearingDegrees(
                    lat1: s[i].latitude, lon1: s[i].longitude,
                    lat2: s[i + 1].latitude, lon2: s[i + 1].longitude
                )
            }

            links.append(Link(
                distance: distance,
                dt: dt,
                bearing: bearing,
                trusted: trusted
            ))
        }
        return links
    }

    // MARK: - Stage 3: runs

    /// A maximal range of sample indices connected end-to-end by trusted links.
    /// Nothing — not a ride, not a smoothing window, not a distance sum —
    /// crosses a run boundary.
    private static func contiguousRuns(linkCount: Int, links: [Link]) -> [ClosedRange<Int>] {
        guard linkCount > 0 else { return [] }
        var runs: [ClosedRange<Int>] = []
        var start = 0
        for i in 0..<linkCount where !links[i].trusted {
            if i >= start { runs.append(start...i) }   // run ends at sample i
            start = i + 1
        }
        if start <= linkCount { runs.append(start...linkCount) }
        return runs.filter { $0.lowerBound <= $0.upperBound }
    }

    // MARK: - Stage 4: speed

    private static func smoothedSpeeds(
        _ s: [CleanSample],
        links: [Link],
        runs: [ClosedRange<Int>],
        tuning: Tuning
    ) -> [Double] {
        // Raw per-sample speed: the device's own measurement when it has one
        // (Doppler-derived and far better than anything we can compute), else a
        // regression over a short window of positions.
        var raw = [Double](repeating: 0, count: s.count)
        for run in runs {
            for i in run {
                if let device = s[i].deviceSpeed {
                    raw[i] = device
                } else {
                    raw[i] = regressedSpeed(at: i, within: run, samples: s, tuning: tuning)
                }
            }
        }

        // Smooth within each run only.
        var smoothed = raw
        for run in runs {
            let slice = Array(raw[run])
            let median = rollingMedian(slice, window: tuning.medianWindowSamples)
            let mean = movingAverage(median, window: tuning.meanWindowSamples)
            for (offset, value) in mean.enumerated() {
                smoothed[run.lowerBound + offset] = value.isFinite ? value : 0
            }
        }
        return smoothed
    }

    /// Least-squares ground speed at `index`, fitted over a time window of
    /// neighbouring fixes and de-biased for measurement noise.
    ///
    /// Two things make this much better than `distance / Δt` between adjacent
    /// fixes, which is what a naive implementation uses:
    ///
    /// 1. **Regression instead of differencing.** The slope of a line fitted
    ///    through `n` positions has error `σ / √Σ(tₖ − t̄)²`, which for a 5 s
    ///    window at 1 Hz is roughly a third of the single-link error.
    /// 2. **Noise de-biasing.** Position noise does not average out of a
    ///    *speed* — it is a strictly positive bias, so a stationary surfer
    ///    reads as moving. Because the expected magnitude of that bias is known
    ///    from the reported accuracy, it can be removed in quadrature. Without
    ///    this step a session of sitting still reads as continuous paddling.
    ///
    /// The window never crosses a run boundary, so a dropout cannot pull a
    /// distant burst into the estimate.
    private static func regressedSpeed(
        at index: Int,
        within run: ClosedRange<Int>,
        samples s: [CleanSample],
        tuning: Tuning
    ) -> Double {
        let halfWindow = tuning.derivedSpeedWindowSeconds / 2
        let centreTime = s[index].time

        // Collect the window, clamped to the run.
        var lower = index, upper = index
        while lower > run.lowerBound, centreTime - s[lower - 1].time <= halfWindow { lower -= 1 }
        while upper < run.upperBound, s[upper + 1].time - centreTime <= halfWindow { upper += 1 }
        guard upper > lower else { return 0 }

        // Project onto a local tangent plane centred on this fix. Over the few
        // hundred metres a surf session spans, equirectangular is exact enough
        // and avoids any pole/antimeridian special-casing at these latitudes.
        let latitudeRadians = s[index].latitude * .pi / 180
        let metersPerDegreeLat = earthRadiusMeters * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(latitudeRadians)

        var meanTime = 0.0, meanEast = 0.0, meanNorth = 0.0, meanAccuracy = 0.0
        let count = Double(upper - lower + 1)
        for k in lower...upper {
            meanTime += s[k].time - centreTime
            meanEast += (s[k].longitude - s[index].longitude) * metersPerDegreeLon
            meanNorth += (s[k].latitude - s[index].latitude) * metersPerDegreeLat
            meanAccuracy += s[k].accuracy
        }
        meanTime /= count; meanEast /= count; meanNorth /= count; meanAccuracy /= count

        var timeVariance = 0.0, covarianceEast = 0.0, covarianceNorth = 0.0
        for k in lower...upper {
            let dt = (s[k].time - centreTime) - meanTime
            let east = (s[k].longitude - s[index].longitude) * metersPerDegreeLon - meanEast
            let north = (s[k].latitude - s[index].latitude) * metersPerDegreeLat - meanNorth
            timeVariance += dt * dt
            covarianceEast += dt * east
            covarianceNorth += dt * north
        }
        guard timeVariance > 0 else { return 0 }

        let velocityEast = covarianceEast / timeVariance
        let velocityNorth = covarianceNorth / timeVariance
        let speedSquared = velocityEast * velocityEast + velocityNorth * velocityNorth
        guard speedSquared.isFinite else { return 0 }

        // Expected variance of the fitted slope per axis, from the fixes' own
        // accuracy. Both axes contribute, hence the factor of two.
        let effectiveSigma = meanAccuracy * tuning.derivedSpeedNoiseCompensation
        let slopeVariance = (effectiveSigma * effectiveSigma) / timeVariance
        let debiased = speedSquared - 2 * slopeVariance

        guard debiased > 0, debiased.isFinite else { return 0 }
        return debiased.squareRoot()
    }

    /// Centred rolling median with edge clamping (shrinking window at the ends).
    /// Kills isolated spikes without shifting the series in time.
    private static func rollingMedian(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > 2 else { return values }
        let radius = window / 2
        var out = values
        var scratch: [Double] = []
        scratch.reserveCapacity(window)
        for i in values.indices {
            let lower = max(values.startIndex, i - radius)
            let upper = min(values.index(before: values.endIndex), i + radius)
            scratch.removeAll(keepingCapacity: true)
            scratch.append(contentsOf: values[lower...upper])
            scratch.sort()
            let count = scratch.count
            out[i] = count % 2 == 1
                ? scratch[count / 2]
                : (scratch[count / 2 - 1] + scratch[count / 2]) / 2
        }
        return out
    }

    /// Centred moving average with edge clamping.
    private static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > 2 else { return values }
        let radius = window / 2
        var out = values
        for i in values.indices {
            let lower = max(values.startIndex, i - radius)
            let upper = min(values.index(before: values.endIndex), i + radius)
            var sum = 0.0
            for j in lower...upper { sum += values[j] }
            out[i] = sum / Double(upper - lower + 1)
        }
        return out
    }

    // MARK: - Stage 5: distance per link

    /// Distance credited to each link.
    ///
    /// Untrusted links are always worth zero — we do not know what happened
    /// across them, and guessing is what produces 350 ft "rides". Trusted links
    /// are credited either by integrating the smoothed speed across the interval
    /// (default, noise-resistant) or by the raw position difference.
    private static func reportedDistances(
        links: [Link],
        speeds: [Double],
        tuning: Tuning
    ) -> [Double] {
        var distances = [Double](repeating: 0, count: links.count)
        for i in links.indices where links[i].trusted {
            let value: Double
            if tuning.usesSpeedIntegratedDistance {
                // Trapezoidal integration of the speed series over the interval.
                value = (speeds[i] + speeds[i + 1]) / 2 * links[i].dt
            } else {
                value = links[i].distance
            }
            distances[i] = value.isFinite && value > 0 ? value : 0
        }
        return distances
    }

    // MARK: - Stage 6: detection

    private struct Candidate {
        var start: Int      // index into clean samples
        var end: Int
    }

    private static func detectWaves(
        _ s: [CleanSample],
        links: [Link],
        runs: [ClosedRange<Int>],
        speeds: [Double],
        distances: [Double],
        tuning: Tuning
    ) -> [WaveSegment] {
        // Threshold crossing happens per run, but merging is session-wide on
        // purpose. If a single corrupt fix in the middle of a ride breaks the
        // run, the two halves are still one wave — counting them separately
        // would *over*-report, which is the worse error. The untrusted link
        // between them still contributes no distance, so the ride's length
        // stays honest even though its count is corrected.
        var candidates: [Candidate] = []
        for run in runs {
            candidates.append(contentsOf: rawCandidates(in: run, speeds: speeds, tuning: tuning))
        }
        let merged = mergeCandidates(candidates, samples: s, tuning: tuning)

        var accepted: [WaveSegment] = []
        for candidate in merged {
            guard let wave = validate(
                candidate, samples: s, links: links, speeds: speeds,
                distances: distances, tuning: tuning
            ) else { continue }
            accepted.append(wave)
        }
        return accepted
    }

    /// Threshold crossing with hysteresis, inside one run.
    private static func rawCandidates(
        in run: ClosedRange<Int>,
        speeds: [Double],
        tuning: Tuning
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        var i = run.lowerBound

        while i <= run.upperBound {
            guard speeds[i] >= tuning.waveEnterSpeedMetersPerSecond else {
                i += 1
                continue
            }

            // Extend backwards over the acceleration ramp: everything from the
            // moment speed rose past the exit threshold is part of the ride, even
            // though the ride was only *confirmed* once it crossed the entry
            // threshold. Without this the measured duration is biased short.
            var start = i
            while start > run.lowerBound,
                  speeds[start - 1] >= tuning.waveExitSpeedMetersPerSecond {
                start -= 1
            }

            // Extend forwards while above the (lower) exit threshold.
            var end = i
            while end < run.upperBound,
                  speeds[end + 1] >= tuning.waveExitSpeedMetersPerSecond {
                end += 1
            }

            // A backwards extension can overlap the previous candidate when two
            // bursts share a trough; the merge pass below resolves that, but we
            // clamp here so ranges never invert.
            if let last = candidates.last, start <= last.end {
                candidates[candidates.count - 1].end = max(last.end, end)
            } else {
                candidates.append(Candidate(start: start, end: end))
            }
            i = end + 1
        }
        return candidates
    }

    /// Joins candidates whose separation is shorter than the merge window.
    /// Only ever called with candidates from the same run, so there is no
    /// untrusted link between them by construction.
    private static func mergeCandidates(
        _ candidates: [Candidate],
        samples: [CleanSample],
        tuning: Tuning
    ) -> [Candidate] {
        guard candidates.count > 1 else { return candidates }
        var merged: [Candidate] = [candidates[0]]

        for candidate in candidates.dropFirst() {
            let previous = merged[merged.count - 1]
            let gap = samples[candidate.start].time - samples[previous.end].time
            if gap <= tuning.maxWaveMergeGapSeconds {
                merged[merged.count - 1].end = candidate.end
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }

    /// Applies the physical plausibility gates and materialises a `WaveSegment`.
    private static func validate(
        _ candidate: Candidate,
        samples: [CleanSample],
        links: [Link],
        speeds: [Double],
        distances: [Double],
        tuning: Tuning
    ) -> WaveSegment? {
        let start = candidate.start
        let end = candidate.end
        guard start < end else { return nil }   // a single fix is not a ride

        guard end - start + 1 >= tuning.minWaveSampleCount else { return nil }

        let duration = samples[end].time - samples[start].time
        guard duration.isFinite, duration >= tuning.minWaveDurationSeconds else { return nil }

        // Time actually spent at or above the entry threshold, summed over
        // contiguous stretches. This is the candidate's real evidence; the
        // hysteresis-extended duration above is only its extent.
        var sustained = 0.0
        for i in start..<end
        where speeds[i] >= tuning.waveEnterSpeedMetersPerSecond
            && speeds[i + 1] >= tuning.waveEnterSpeedMetersPerSecond {
            let dt = samples[i + 1].time - samples[i].time
            if dt > 0, dt <= tuning.maxBridgeableGapSeconds { sustained += dt }
        }
        guard sustained >= tuning.minSustainedAboveEntrySeconds else { return nil }

        var peak = 0.0
        for i in start...end { peak = max(peak, speeds[i]) }
        // A "ride" faster than any surfer has ever gone is a measurement fault,
        // not an achievement. Drop the whole segment rather than clamp it.
        guard peak.isFinite, peak <= tuning.maxPlausibleWaveSpeedMetersPerSecond else { return nil }

        var distance = 0.0
        for i in start..<end { distance += distances[i] }
        guard distance.isFinite else { return nil }

        if tuning.requiresDirectionalConsistency,
           let resultant = headingResultantLength(from: start, to: end, links: links, tuning: tuning),
           resultant < tuning.minHeadingResultantLength {
            // Held no line — this is a cluster of GPS scatter, not a wave.
            return nil
        }

        return WaveSegment(
            startIndex: samples[start].originalIndex,
            endIndex: samples[end].originalIndex,
            startTime: samples[start].timestamp,
            endTime: samples[end].timestamp,
            peakSpeedMetersPerSecond: peak,
            distanceMeters: distance,
            durationSeconds: duration
        )
    }

    /// Distance-weighted mean resultant length of the segment's headings, 0…1.
    ///
    /// Returns `nil` when there is not enough heading evidence to judge, in
    /// which case the caller must not apply the test — an absent measurement is
    /// not a failed measurement.
    ///
    /// Weighting by link distance makes this numerically equal to
    /// `netDisplacement / pathLength` when headings come from geometry, i.e. a
    /// straightness ratio, which is the physically meaningful quantity.
    private static func headingResultantLength(
        from start: Int,
        to end: Int,
        links: [Link],
        tuning: Tuning
    ) -> Double? {
        var x = 0.0, y = 0.0
        var weightedDistance = 0.0     // path length backed by a usable bearing
        var totalDistance = 0.0        // whole path length of the candidate
        var linkCount = 0

        for i in start..<end {
            let link = links[i]
            linkCount += 1
            totalDistance += link.distance

            guard let bearing = link.bearing else { continue }
            let radians = bearing * .pi / 180
            x += link.distance * sin(radians)
            y += link.distance * cos(radians)
            weightedDistance += link.distance
        }

        // Not enough evidence to judge: say so rather than guessing.
        guard linkCount >= tuning.minHeadingLinksForCheck,
              totalDistance > 0, weightedDistance > 0,
              weightedDistance / totalDistance >= tuning.minHeadingCoverageFraction
        else { return nil }

        let resultant = (x * x + y * y).squareRoot() / weightedDistance
        return resultant.isFinite ? min(1, resultant) : nil
    }

    // MARK: - Stage 7: statistics

    private static func assembleStats(
        _ samples: [CleanSample],
        links: [Link],
        speeds: [Double],
        distances: [Double],
        waves: [WaveSegment],
        tuning: Tuning
    ) -> WaveStats {
        // Map accepted waves back onto link indices so paddle distance can
        // exclude them. Waves report *original* indices, so translate via a
        // lookup rather than assuming clean indices line up.
        var originalToClean: [Int: Int] = [:]
        originalToClean.reserveCapacity(samples.count)
        for (cleanIndex, sample) in samples.enumerated() {
            originalToClean[sample.originalIndex] = cleanIndex
        }

        var insideWave = [Bool](repeating: false, count: links.count)
        for wave in waves {
            guard let start = originalToClean[wave.startIndex],
                  let end = originalToClean[wave.endIndex], start < end else { continue }
            for i in start..<end where i < insideWave.count { insideWave[i] = true }
        }

        var total = 0.0
        var paddle = 0.0
        for i in links.indices where links[i].trusted {
            let distance = distances[i]
            guard distance.isFinite else { continue }
            total += distance
            guard !insideWave[i] else { continue }

            // Classify the link by the mean of its endpoints' smoothed speeds.
            // Using the smoothed series (not the raw link speed) keeps the
            // classification consistent with what detection saw.
            let linkSpeed = (speeds[i] + speeds[i + 1]) / 2
            if linkSpeed >= tuning.stationarySpeedMetersPerSecond,
               linkSpeed < tuning.waveEnterSpeedMetersPerSecond {
                paddle += distance
            }
        }

        // Top speed considers the whole session, but only values we believe.
        var topSpeed = 0.0
        for speed in speeds where speed.isFinite && speed <= tuning.maxPlausibleWaveSpeedMetersPerSecond {
            topSpeed = max(topSpeed, speed)
        }
        // Invariant: top speed can never be below a reported ride's peak.
        for wave in waves { topSpeed = max(topSpeed, wave.peakSpeedMetersPerSecond) }

        // "Longest" ride means longest in time; its distance is reported
        // alongside so the two figures describe the same wave.
        let longest = waves.max { lhs, rhs in
            lhs.durationSeconds == rhs.durationSeconds
                ? lhs.distanceMeters < rhs.distanceMeters
                : lhs.durationSeconds < rhs.durationSeconds
        }

        return WaveStats(
            waveCount: waves.count,
            topSpeedKph: finiteOrZero(topSpeed * 3.6),
            longestRideSeconds: finiteOrZero(longest?.durationSeconds ?? 0),
            longestRideMeters: finiteOrZero(longest?.distanceMeters ?? 0),
            paddleDistanceMeters: finiteOrZero(paddle),
            totalDistanceMeters: finiteOrZero(total),
            waves: waves
        )
    }

    private static func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    // MARK: - Geodesy

    /// Mean Earth radius, metres (IUGG). Adequate for the ≤1 km scales here.
    private static let earthRadiusMeters = 6_371_008.8

    /// Great-circle distance between two WGS-84 coordinates.
    ///
    /// Haversine is used rather than a planar approximation because it is just
    /// as cheap at these scales and has no latitude-dependent failure mode.
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180

        let sinPhi = sin(deltaPhi / 2)
        let sinLambda = sin(deltaLambda / 2)
        let a = sinPhi * sinPhi + cos(phi1) * cos(phi2) * sinLambda * sinLambda
        // Clamp guards against a > 1 from floating-point drift, which would make
        // asin produce NaN for two effectively identical coordinates.
        let clamped = min(1, max(0, a))
        let c = 2 * atan2(clamped.squareRoot(), (1 - clamped).squareRoot())
        let distance = earthRadiusMeters * c
        return distance.isFinite ? distance : 0
    }

    /// Initial great-circle bearing, degrees clockwise from true north, 0..<360.
    static func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        let degrees = atan2(y, x) * 180 / .pi
        guard degrees.isFinite else { return 0 }
        return degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
    }
}
