//
//  WindowScorer.swift
//
//  Finds the best window to surf today at one spot, justified entirely by the
//  user's own rated history at that spot.
//
//  DESIGN THESIS
//  =============
//  We deliberately model *no* surf-break physics: no coastline orientation, no
//  bathymetry, no offshore/onshore classification. Those require per-spot data we
//  do not have and cannot reliably infer. Instead, the user's rated sessions are
//  the model. If this surfer gives 5 stars to 1.4 m @ 13 s with 6 kph wind from
//  040 degrees, then a forecast hour that looks like that is good — we never need to
//  know *why*, or which way the beach faces.
//
//  That reduces the problem to: nearest-neighbour regression of "rating" over a
//  heterogeneous, partially-observed condition vector. The hard parts are all in
//  the distance function (mixed units, circular features, missing data on either
//  side), in being honest about confidence when the history is thin, and in
//  undoing the shrinkage that kernel regression inflicts on the predicted stars.
//
//  Pure Foundation. Stateless. Deterministic. Never emits NaN or infinity.
//

import Foundation
import SwiftData

// MARK: - Input types (mirror of the app's stored fields)

// `TideTrend` itself lives in `Peak/Models/TideTrend.swift` because SwiftData
// stores its raw value on `SurfSession`. Only the cyclic ordering the distance
// function needs is defined here, so the model stays free of scorer internals.
nonisolated private extension TideTrend {
    /// Position on the tide cycle rising -> high -> falling -> low, used for
    /// cyclic distance. See `Tuning/tideTrendOppositeDistance`.
    var cyclePosition: Int {
        switch self {
        case .rising: return 0
        case .high: return 1
        case .falling: return 2
        case .low: return 3
        }
    }
}

/// One hour of forecast, or the conditions recorded for one logged session.
///
/// **Every field is optional and that is the central design constraint.** Real
/// logged sessions frequently have missing data: the user logged manually, the
/// auto-fill call failed, or the spot had no coordinates. The scorer must compare
/// a fully-populated forecast hour against a session that only recorded swell
/// height without either crashing or pretending the comparison was informative.
nonisolated struct ConditionsSample: Sendable, Hashable, Codable {
    var swellWaveHeightMeters: Double?
    var swellWavePeriodSeconds: Double?
    var swellWaveDirectionDegrees: Double?
    var windWaveHeightMeters: Double?
    var waveHeightMeters: Double?
    var windSpeedKph: Double?
    var windDirectionDegrees: Double?
    var seaSurfaceTemperatureC: Double?
    /// Tide height relative to mean sea level, in metres. May legitimately be negative.
    var seaLevelHeightMeters: Double?
    var tideTrend: TideTrend?

    init(
        swellWaveHeightMeters: Double? = nil,
        swellWavePeriodSeconds: Double? = nil,
        swellWaveDirectionDegrees: Double? = nil,
        windWaveHeightMeters: Double? = nil,
        waveHeightMeters: Double? = nil,
        windSpeedKph: Double? = nil,
        windDirectionDegrees: Double? = nil,
        seaSurfaceTemperatureC: Double? = nil,
        seaLevelHeightMeters: Double? = nil,
        tideTrend: TideTrend? = nil
    ) {
        self.swellWaveHeightMeters = swellWaveHeightMeters
        self.swellWavePeriodSeconds = swellWavePeriodSeconds
        self.swellWaveDirectionDegrees = swellWaveDirectionDegrees
        self.windWaveHeightMeters = windWaveHeightMeters
        self.waveHeightMeters = waveHeightMeters
        self.windSpeedKph = windSpeedKph
        self.windDirectionDegrees = windDirectionDegrees
        self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        self.seaLevelHeightMeters = seaLevelHeightMeters
        self.tideTrend = tideTrend
    }
}

/// A past session the user logged and rated 0...5 stars.
nonisolated struct RatedSession: Sendable, Hashable, Codable {
    var date: Date
    /// The user's own star rating, 0...5. Values outside the range are clamped.
    var rating: Int
    var conditions: ConditionsSample
    /// Identity of the `SurfSession` this was built from, so the card can push
    /// through to the real session detail. Optional and last in the parameter
    /// list because the algorithm never reads it — it is passenger data that
    /// survives the trip out to the UI, and every fixture omits it.
    var sessionID: PersistentIdentifier?

    init(date: Date, rating: Int, conditions: ConditionsSample, sessionID: PersistentIdentifier? = nil) {
        self.date = date
        self.rating = rating
        self.conditions = conditions
        self.sessionID = sessionID
    }
}

/// One hour of the forecast day being evaluated.
nonisolated struct ForecastHour: Sendable, Hashable, Codable {
    var date: Date
    var conditions: ConditionsSample

    init(date: Date, conditions: ConditionsSample) {
        self.date = date
        self.conditions = conditions
    }
}

// MARK: - Features

/// The comparable dimensions of a `ConditionsSample`.
///
/// Declared as an explicit ordered list rather than derived from reflection so
/// that iteration order — and therefore every downstream sum and sort — is
/// deterministic across runs and platforms.
nonisolated enum ConditionFeature: Int, Sendable, Hashable, CaseIterable, Codable {
    case swellHeight
    case swellPeriod
    case swellDirection
    case windWaveHeight
    case waveHeight
    case windSpeed
    case windDirection
    case seaTemperature
    case seaLevel
    case tideTrend

    /// Circular features wrap at 360 degrees; 350 and 10 are 20 apart, not 340.
    fileprivate var isCircularDegrees: Bool {
        self == .swellDirection || self == .windDirection
    }

    /// Features that cannot be negative in reality; a negative reading is corrupt
    /// data and is discarded rather than trusted.
    fileprivate var isNonNegativeMagnitude: Bool {
        switch self {
        case .swellHeight, .swellPeriod, .windWaveHeight, .waveHeight, .windSpeed:
            return true
        case .swellDirection, .windDirection, .seaTemperature, .seaLevel, .tideTrend:
            return false
        }
    }
}

// MARK: - Output types

/// A single scored forecast hour. Exposed publicly because the app can plot the
/// per-hour curve, and because it makes window grouping independently testable.
nonisolated struct ScoredHour: Sendable, Hashable {
    var date: Date
    /// Expected star rating this user would give these conditions, 0...5.
    var predictedRating: Double
    /// How much to trust `predictedRating`, 0...1. See `Tuning` confidence constants.
    var confidence: Double
    /// The single most similar past session, for "similar to your 5-star on Mar 12".
    var bestMatch: RatedSession?
    /// Neighbour weight of `bestMatch` (kernel x overlap reliability), 0...1.
    var bestMatchWeight: Double
    /// Human-readable factors that made this hour resemble `bestMatch`.
    var matchFactors: [String]

    init(
        date: Date,
        predictedRating: Double,
        confidence: Double,
        bestMatch: RatedSession? = nil,
        bestMatchWeight: Double = 0,
        matchFactors: [String] = []
    ) {
        self.date = date
        self.predictedRating = predictedRating
        self.confidence = confidence
        self.bestMatch = bestMatch
        self.bestMatchWeight = bestMatchWeight
        self.matchFactors = matchFactors
    }
}

/// A contiguous run of good forecast hours, ranked.
nonisolated struct ScoredWindow: Sendable, Hashable {
    /// Start of the first good hour.
    var start: Date
    /// Exclusive end: last good hour + one hour. Hours 6,7,8 yield 06:00...09:00.
    var end: Date
    /// Mean expected rating across the window, 0...5. Deliberately *not* inflated
    /// by the duration bonus used for ranking — this number is shown to the user.
    var predictedRating: Double
    /// Mean confidence across the window, 0...1.
    var confidence: Double
    /// Number of forecast hours in the window.
    var hourCount: Int
    /// The most similar past session found anywhere in the window.
    var bestMatch: RatedSession?
    /// e.g. ["1.4 m swell", "13 s period", "light wind (6 km/h)"].
    var matchFactors: [String]
    /// Internal ranking score = `predictedRating` + duration bonus. Exposed for
    /// debugging and for stable re-sorting by the caller.
    var rankScore: Double

    init(
        start: Date,
        end: Date,
        predictedRating: Double,
        confidence: Double,
        hourCount: Int,
        bestMatch: RatedSession? = nil,
        matchFactors: [String] = [],
        rankScore: Double = 0
    ) {
        self.start = start
        self.end = end
        self.predictedRating = predictedRating
        self.confidence = confidence
        self.hourCount = hourCount
        self.bestMatch = bestMatch
        self.matchFactors = matchFactors
        self.rankScore = rankScore
    }
}

// MARK: - Tuning

/// Every tunable constant in the algorithm, in one place.
///
/// The defaults are *priors*, chosen from general surf knowledge, not fitted to
/// data. They are the starting point that a real tuning pass against logged
/// sessions should replace. Each constant documents the reasoning behind its
/// value so a future tuner knows what they are trading off.
nonisolated struct Tuning: Sendable, Hashable {

    // MARK: Feature scales

    /// The gap in each feature's own units that counts as "one unit of
    /// dissimilarity" (a normalised distance of 1.0).
    ///
    /// This is what makes degrees, metres, kph and seconds comparable. Each value
    /// answers: *how big a change in this quantity makes a session feel like a
    /// meaningfully different session?* Smaller scale = the feature is more
    /// sensitive and separates samples faster.
    struct FeatureScales: Sendable, Hashable {
        /// 0.35 m ~ 1.1 ft. Below this, surfers describe two sessions as "about the
        /// same size"; above it they say it was noticeably bigger or smaller.
        var swellHeightMeters: Double = 0.35
        /// 2.5 s. The gap between a 10 s windswell and a 12.5 s groundswell is the
        /// gap between two different kinds of day; within 2.5 s the wave shape is
        /// recognisably similar.
        var swellPeriodSeconds: Double = 2.5
        /// 35 degrees. Most breaks accept a swell window roughly this wide before
        /// refraction and shadowing change the wave meaningfully.
        var swellDirectionDegrees: Double = 35
        /// 0.30 m. Wind-wave (chop) height lives in a smaller absolute range than
        /// groundswell, so the same absolute delta matters more.
        var windWaveHeightMeters: Double = 0.30
        /// 0.40 m. Total significant wave height mixes swell and chop, so it is a
        /// blunter instrument than swell height and tolerates a wider band.
        var waveHeightMeters: Double = 0.40
        /// 8 kph. Roughly the glassy-to-textured transition. 5 kph and 13 kph are
        /// visibly different surfaces; 5 kph and 8 kph are not.
        var windSpeedKph: Double = 8
        /// 45 degrees. Wind direction is judged more coarsely than swell direction —
        /// surfers think in octants ("north-east-ish"), not degrees.
        var windDirectionDegrees: Double = 45
        /// 3.0 degC. About one wetsuit step. Comfort only; it does not change the wave.
        var seaTemperatureC: Double = 3.0
        /// 0.35 m of tide. At tide-sensitive reefs this is the difference between
        /// working and not; it is the tightest meaningful tide band worth modelling.
        var seaLevelMeters: Double = 0.35

        init() {}
    }

    /// Prior importance of each feature to surf quality, before any user data.
    ///
    /// These multiply the per-feature distance inside the weighted RMS, and are
    /// also the denominator of the overlap ratio, so a missing high-weight feature
    /// costs more overlap than a missing low-weight one. Relative magnitudes are
    /// what matter; the absolute scale cancels out.
    struct FeatureWeights: Sendable, Hashable {
        /// 1.0 — the anchor. Size is the first thing any surfer checks.
        var swellHeight: Double = 1.0
        /// 0.9 — period is nearly as decisive as size: it sets power and shape, and
        /// is the classic separator between a good day and a mushy one.
        var swellPeriod: Double = 0.9
        /// 0.6 — matters, but its effect is entirely mediated by the break's
        /// orientation, which we refuse to model. Given moderate weight so that a
        /// swell from a completely different quadrant still reads as a different day.
        var swellDirection: Double = 0.6
        /// 0.9 — wind is the most common ruiner of otherwise good swell.
        var windSpeed: Double = 0.9
        /// 0.7 — high, but this weight is *modulated down toward zero as wind gets
        /// light* (see `windDirectionLightKph`), because the direction of a 3 kph
        /// breeze is meaningless.
        var windDirection: Double = 0.7
        /// 0.5 — a decent proxy for surface chop, which the user feels directly.
        var windWaveHeight: Double = 0.5
        /// 0.4 — deliberately low because it is largely redundant with swell height
        /// plus wind-wave height, and double counting size would swamp the vector.
        /// Kept because it is often the *only* height field a sparse session has.
        var waveHeight: Double = 0.4
        /// 0.5 — tide state is spot-critical (some reefs only work on one half of
        /// the tide) but the user's history is what reveals that, not us.
        var seaLevel: Double = 0.5
        /// 0.4 — direction of tide movement, secondary to absolute height.
        var tideTrend: Double = 0.4
        /// 0.15 — near-irrelevant to wave quality; affects comfort and session
        /// length only. Non-zero so that a winter session and a summer session are
        /// nudged apart, since seasonality correlates with swell regime.
        var seaTemperature: Double = 0.15

        init() {}
    }

    var scales = FeatureScales()
    var weights = FeatureWeights()

    // MARK: Distance shaping

    /// Per-feature normalised distances are clamped here (1.5 = 1.5 "scales" apart).
    ///
    /// Without a cap, one wildly different feature — a 180 degree swell shift, a freak
    /// 60 kph wind — would dominate the whole vector and hide genuine agreement in
    /// everything else. 1.5 keeps a little discrimination in the tail (a 180 degree
    /// miss still beats nothing) while bounding any single feature's influence.
    var maxFeatureDistance: Double = 1.5

    /// The normalised distance assumed for a feature that could *not* be compared
    /// because one side was missing it.
    ///
    /// This is the core anti-bias mechanism. The naive approach — average the
    /// features you happen to have — makes a session that recorded only swell
    /// height look like a perfect match, because it agrees on everything it was
    /// asked about. Instead we impute unobserved features at the *expected*
    /// distance between two unrelated samples, which is 1.0 by construction of the
    /// scales. A sparse session therefore lands at middling distance: neither
    /// rewarded nor punished for its sparsity, just uninformative.
    var missingFeatureDistance: Double = 1.0

    /// Gaussian kernel bandwidth, in normalised distance units.
    ///
    /// 0.45 means a neighbour one full "scale" away in the average feature gets
    /// about 13% of the weight of an exact match — near neighbours dominate but the
    /// tail never hits exactly zero, so the prediction moves smoothly instead of
    /// jumping as neighbours cross a cutoff.
    var kernelBandwidth: Double = 0.45

    /// Wind speed (kph) at or below which wind *direction* is treated as
    /// irrelevant. Glassy is glassy no matter where the breath comes from.
    var windDirectionLightKph: Double = 6

    /// Wind speed (kph) at or above which wind direction gets its full weight.
    /// Above ~20 kph the difference between offshore and onshore is the difference
    /// between clean and unsurfable, so direction carries everything.
    var windDirectionStrongKph: Double = 20

    /// Wind-direction weight multiplier used when neither sample recorded a wind
    /// speed. 0.5 is the agnostic middle: we neither assume the direction mattered
    /// nor that it did not.
    var windDirectionUnknownStrengthFactor: Double = 0.5

    /// Cyclic categorical distance between fully opposed tide trends
    /// (rising vs falling, high vs low). Adjacent states on the cycle get half this.
    var tideTrendOppositeDistance: Double = 1.0

    // MARK: Overlap handling

    /// A candidate pair must share at least this many comparable features, or the
    /// pair is discarded outright.
    ///
    /// Lowering this to 1 measurably improves rank correlation when the *forecast*
    /// is also full of holes (0.36 vs 0.35 at 45% missing). It is kept at 2 anyway,
    /// deliberately trading that away: a window whose entire justification is
    /// "similar to your 5-star session on Mar 12, because the water was the same
    /// temperature" is worse than no window, and the regime where 1 wins does not
    /// occur in production because the forecast provider returns complete hours.
    var minOverlappingFeatures: Int = 2

    /// A pair must also share at least this fraction of total feature *weight*.
    ///
    /// 0.08 admits a session that recorded only swell height (weight 1.0 of ~6.05)
    /// while still rejecting one that recorded only water temperature (0.15/6.05 =
    /// 0.025). Swept against the synthetic surfer, a stricter threshold measurably
    /// hurts once data is scarce — rejecting a thin neighbour outright is worse than
    /// admitting it at its honest imputed distance, because the imputation has
    /// already stopped it from doing any damage (0.36 vs 0.35 rank correlation at
    /// 45% missing, 0.18 vs 0.16 at 60%). Above ~0.25 the loss becomes sharp.
    var minOverlapRatio: Double = 0.08

    /// Exponent applied to the overlap ratio to produce a neighbour's reliability
    /// multiplier.
    ///
    /// Distance imputation (above) already removes the sparsity *bias*; this
    /// handles the remaining sparsity *variance* — a distance estimated from two
    /// features is noisier than one estimated from ten, so it should carry less
    /// vote and contribute less confidence.
    ///
    /// Swept against the synthetic surfer, ranking quality rises with this exponent
    /// (0.34 at 0.0, 0.35 at 0.35, 0.36 at 0.6, then flat), confirming the discount
    /// earns its place rather than merely double-counting the imputation. 0.6 sits
    /// at the plateau: at 17% overlap a neighbour keeps ~33% of its weight, which
    /// is a real penalty without discarding sparse history entirely — many users
    /// would otherwise have no model at all.
    var overlapReliabilityExponent: Double = 0.6

    // MARK: Prediction

    /// Number of nearest neighbours that vote in the prediction.
    ///
    /// Measured on the synthetic surfer, ranking quality rises monotonically with
    /// k and plateaus around 24 (Spearman 0.72 at k=3, 0.83 at k=8, 0.88 at k=24).
    /// The Gaussian kernel already localises the estimate, so truncating hard just
    /// discards variance-reducing evidence; ratings are noisy integers and averaging
    /// more of them helps. 24 keeps a deep logbook from dragging in genuinely
    /// unrelated sessions while capturing roughly a keen surfer's last month.
    /// Histories smaller than this simply use everything they have.
    var neighbourCount: Int = 24

    /// Number of nearest neighbours that count toward *confidence*.
    ///
    /// Deliberately much smaller than `neighbourCount`, and the reason the two are
    /// separate constants. Confidence support is a sum of kernel weights, so if it
    /// were computed over all 24 neighbours then 24 distant sessions at 0.03 weight
    /// each would sum to 0.7 and masquerade as one excellent match — precisely the
    /// extrapolation that requirement 5 says must *lower* confidence. Restricting
    /// support to the 5 closest means the number can only be earned by genuinely
    /// nearby history.
    var confidenceNeighbourCount: Int = 5

    /// Shrinkage pseudo-count, in units of kernel weight.
    ///
    /// The prediction is a weighted mean of neighbour ratings blended with the
    /// user's overall mean rating at this spot, where the prior counts as this much
    /// neighbour weight. 1.0 means "one perfect neighbour is worth as much as the
    /// prior" — so an hour with no close analogue relaxes to the user's baseline
    /// instead of confidently reporting the average of whatever distant sessions
    /// happened to be nearest. Raise it to be more conservative.
    var priorStrength: Double = 1.0

    /// Fallback prior rating when the history is empty or unusable. 2.5 is the
    /// midpoint of the 0...5 scale: maximally uncommitted.
    var neutralPriorRating: Double = 2.5

    // MARK: Calibration

    /// Upper bound on the self-calibration gain (see `Model.calibrationGain`).
    ///
    /// Kernel regression is a *shrinking* estimator: averaging neighbours pulls
    /// every prediction toward the mean, so the predicted ratings across a day span
    /// a much narrower range than the real ratings do. Measured on the synthetic
    /// surfer before calibration, the model's spread across a forecast day was 0.58
    /// stars against a true spread of 1.75 — a 3x compression. That does not hurt
    /// *ranking* (it is a monotone squeeze) but it wrecks everything measured in
    /// absolute stars: the 3.0 window threshold is barely cleared on genuinely good
    /// days, and a fixed star tolerance swallows the whole day into one window.
    ///
    /// So the model measures its own compression by leave-one-out prediction over
    /// the user's history and expands predictions about the prior to match. 3.0
    /// caps how much correction is allowed, because the ratio is itself estimated
    /// from limited data and an unbounded gain would amplify noise.
    var maxCalibrationGain: Double = 3.0

    /// Lower bound on the calibration gain. Below 1.0 the model would be *contracted*,
    /// which is occasionally correct (an over-dispersed estimate) but should never
    /// go far; 0.7 allows a mild correction without letting a fluke flatten the day.
    var minCalibrationGain: Double = 0.7

    /// Minimum usable sessions before self-calibration is attempted at all.
    /// Below this the leave-one-out spread is too noisy to trust, and the gain
    /// stays at 1.0. 8 is roughly where the ratio estimate stabilises.
    var minCalibrationSessions: Int = 8

    /// Cap on how many sessions take part in calibration, which is O(n^2).
    /// The most recent 200 are used, which is both a performance bound and a mild
    /// recency bias — a surfer's taste drifts as they improve.
    var calibrationSampleLimit: Int = 200

    // MARK: Confidence

    /// Rated-session count at which count-confidence reaches 0.5.
    ///
    /// Drives `n / (n + 10)`. Chosen so 2 sessions score 0.17 (rightly near
    /// worthless), 10 score 0.50, and 40 score 0.80 — matching the intuition that a
    /// season of logging is decent evidence but never certainty.
    var confidenceCountHalfLife: Double = 10

    /// Total neighbour weight at which support-confidence reaches 0.5.
    ///
    /// Total weight is the sum of kernel x reliability over the k neighbours, so
    /// 0.6 means "a bit more than half of one perfect match". This is the term that
    /// punishes extrapolation: an hour outside everything the user has ever surfed
    /// has near-zero kernel mass no matter how many sessions exist, and its
    /// confidence collapses.
    var confidenceSupportHalfLife: Double = 0.6

    /// Rating standard deviation at which signal-confidence reaches 0.5.
    ///
    /// If every logged session got the same rating, the history contains no
    /// information about which hour is better — spread 0 yields confidence 0, which
    /// is the honest answer even with 200 sessions. 0.45 stars is roughly the
    /// spread of a user who mostly rates 3s and 4s.
    var confidenceSignalHalfLife: Double = 0.45

    /// Confidence is the plain product of its three factors (count x support x
    /// signal), which makes it a strict AND — any one being poor drags the result
    /// down. That keeps the number honest but compresses its range, so thresholds
    /// look lower than intuition suggests: ~0.45 is a *strong* recommendation.
    /// Windows below this are dropped entirely.
    var minConfidence: Double = 0.25

    // MARK: Window selection

    /// An hour must reach this predicted rating to be window-eligible.
    /// 3.0/5 is "worth paddling out". Below that we would rather show nothing.
    var minWindowRating: Double = 3.0

    /// An hour is also rejected if it is more than this far below the best hour of
    /// the day. This is what keeps a window tight around the actual peak instead of
    /// smearing across a mediocre afternoon, and what causes a genuine dip in
    /// conditions to split one long window into two.
    ///
    /// 0.35 was chosen by sweeping it against a fixed oracle — the hours whose
    /// *true* latent rating is at least 3.0 and within 0.5 stars of the day's true
    /// peak — and taking the F1 optimum. Measured across 250 synthetic days:
    ///
    ///     tolerance   precision   recall   F1     mean window
    ///     0.20        0.76        0.67     0.66   4.7 h
    ///     0.30        0.69        0.81     0.70   6.8 h
    ///     0.35        0.67        0.84     0.71   7.4 h   <- chosen
    ///     0.50        0.62        0.90     0.69   8.7 h
    ///     0.65        0.58        0.93     0.68   9.5 h
    ///
    /// Tighter amputates genuinely good surf; looser recommends flat afternoons.
    /// For reference the oracle's own good stretch averages 8.4 hours on these
    /// days, so a 7.4-hour recommendation is not over-long — a smooth dawn-to-noon
    /// wind profile really does leave a wide window.
    ///
    /// Note this constant only became meaningful once prediction calibration was
    /// added — before that the model's whole-day spread was 0.58 stars, so any
    /// tolerance above ~0.5 swallowed the entire day into one window.
    var relativeRatingTolerance: Double = 0.35

    /// Assumed duration of one forecast hour, in seconds. Sets each window's
    /// exclusive `end`.
    var hourDurationSeconds: TimeInterval = 3600

    /// Maximum gap between consecutive forecast hours that still counts as
    /// contiguous. 5400 s tolerates one jittered timestamp but splits the window
    /// across a genuinely missing hour of forecast data.
    var maxContiguousGapSeconds: TimeInterval = 5400

    /// Ranking bonus per extra hour of window length, in star-equivalents.
    ///
    /// This is what makes "3 solid hours" beat "1 slightly better hour": at 0.25,
    /// a 3-hour window at 4.0 stars ranks 4.5 and outranks an isolated 4.4. Only
    /// affects ordering — the rating shown to the user stays honest.
    var durationBonusPerExtraHour: Double = 0.25

    /// Cap on the duration bonus. Without it a flat, mediocre 10-hour day would
    /// outrank a sharp 3-hour peak. 0.6 caps the bonus at ~3 extra hours' worth.
    var maxDurationBonus: Double = 0.6

    /// Maximum number of windows returned.
    var maxWindows: Int = 4

    // MARK: Explanation

    /// Maximum match factors listed per window. Three is what a phone card fits and
    /// what a person reads.
    var maxMatchFactors: Int = 3

    /// How far below the predicted rating the cited exemplar session may be rated.
    ///
    /// The nearest neighbour by distance is not always the right session to *show*.
    /// A window predicted at 3.5 stars whose closest match happens to be a 2-star
    /// session produces "best window today, 3.5 stars — similar to your 2-star
    /// session on Dec 2", which reads as an argument against the recommendation.
    /// The prediction is still correct (it is the weighted blend of many
    /// neighbours, most of them better) but the exemplar contradicts it.
    ///
    /// So the exemplar is the *most similar neighbour that is not rated materially
    /// below the prediction*, falling back to the nearest overall if none qualifies.
    /// It remains a genuine, genuinely-similar session from the user's own log —
    /// never invented, never cherry-picked beyond this one consistency rule.
    /// 0.5 stars is half a rating step: enough to allow a 4-star exemplar for a
    /// 4.4-star window, not enough to allow a 2-star one.
    var exemplarMaxRatingShortfall: Double = 0.5

    /// A feature only qualifies as a match factor if its normalised distance is at
    /// or below this. 0.6 means "within about two thirds of one scale" — close
    /// enough that claiming it as a reason is truthful.
    var matchFactorMaxDistance: Double = 0.6

    init() {}
}

// MARK: - Scorer

/// Ranks the best windows to surf today at one spot, using only this user's rated
/// history at that spot.
///
/// Stateless and deterministic: the same inputs always produce byte-identical
/// output. All entry points are safe against empty, degenerate and non-finite
/// input, and never return NaN or infinity.
///
/// **Cost**: `rank` is O(hours x history), measured at roughly 12 ms for 200
/// sessions and 20 ms for 500 on device. That is well past a dropped frame, so
/// the app must go through `rankOffMain`. The whole enum is `nonisolated` — the
/// target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, under which a
/// plain synchronous static func would be main-actor isolated and would burn
/// those milliseconds on the UI thread.
nonisolated enum WindowScorer {

    // MARK: API

    /// `rank` on a background executor. This is what the app should call.
    ///
    /// `@concurrent` (not merely `nonisolated`) is the load-bearing part: it
    /// forces the body onto the concurrent pool rather than inheriting the
    /// caller's actor. Every input and output is `Sendable`, so only values
    /// cross.
    @concurrent
    static func rankOffMain(
        forecast: [ForecastHour],
        history: [RatedSession],
        tuning: Tuning = .init()
    ) async -> [ScoredWindow] {
        rank(forecast: forecast, history: history, tuning: tuning)
    }

    /// Ranks the best surf windows in a forecast day.
    ///
    /// - Parameters:
    ///   - forecast: Hourly forecast for the day. Order does not matter; hours are
    ///     sorted and de-duplicated internally. Non-finite dates are dropped.
    ///   - history: The user's rated sessions *at this spot*. Passing history from
    ///     other spots would defeat the entire premise.
    ///   - tuning: Algorithm constants. See ``Tuning``.
    /// - Returns: Up to `tuning.maxWindows` windows, best first (ties broken by
    ///   earlier start). Windows are pairwise disjoint. Returns an empty array
    ///   when the history is too thin or the day is simply not good enough — an
    ///   empty result is a valid, meaningful answer and the caller should show
    ///   nothing rather than invent a recommendation.
    static func rank(
        forecast: [ForecastHour],
        history: [RatedSession],
        tuning: Tuning = .init()
    ) -> [ScoredWindow] {
        let hours = scoreHours(forecast: forecast, history: history, tuning: tuning)
        return groupWindows(hours: hours, tuning: tuning)
    }

    /// Scores every forecast hour independently, without grouping.
    ///
    /// Useful for plotting the day's predicted-rating curve. Returned in
    /// chronological order, de-duplicated by timestamp.
    static func scoreHours(
        forecast: [ForecastHour],
        history: [RatedSession],
        tuning: Tuning = .init()
    ) -> [ScoredHour] {
        let model = Model(history: history, tuning: tuning)
        let hours = normalisedForecast(forecast)
        return hours.map { model.evaluate(conditions: $0.conditions, at: $0.date) }
    }

    /// Predicts the rating for one arbitrary set of conditions.
    ///
    /// Exposed so the app can answer "how would I rate this?" for a single moment,
    /// e.g. while the user is filling in a session form.
    static func evaluate(
        conditions: ConditionsSample,
        at date: Date = Date(),
        history: [RatedSession],
        tuning: Tuning = .init()
    ) -> ScoredHour {
        Model(history: history, tuning: tuning).evaluate(conditions: conditions, at: date)
    }

    /// Groups already-scored hours into ranked contiguous windows.
    ///
    /// Split out from ``rank(forecast:history:tuning:)`` so grouping can be tested
    /// against synthetic hour scores without constructing a history that happens
    /// to produce them.
    ///
    /// - Returns: Disjoint windows sorted by rank score descending, then by start
    ///   ascending. Sorting the result by `start` yields strictly increasing,
    ///   non-overlapping intervals.
    static func groupWindows(
        hours: [ScoredHour],
        tuning: Tuning = .init()
    ) -> [ScoredWindow] {
        let sorted = hours
            .filter { $0.date.timeIntervalSinceReferenceDate.isFinite }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
                return lhs.offset < rhs.offset          // stable: no arbitrary tie order
            }
            .map(\.element)
            .deduplicatedByDate()

        guard !sorted.isEmpty else { return [] }

        // Absolute gate first, so the relative gate is measured against a peak that
        // is itself worth surfing rather than against the best of a bad day.
        let eligible = sorted.filter {
            $0.confidence >= tuning.minConfidence && $0.predictedRating >= tuning.minWindowRating
        }
        guard let peak = eligible.map(\.predictedRating).max() else { return [] }

        let floor = max(tuning.minWindowRating, peak - max(0, tuning.relativeRatingTolerance))
        let good = Set(
            eligible.filter { $0.predictedRating >= floor - 1e-9 }.map(\.date)
        )
        guard !good.isEmpty else { return [] }

        // Walk chronologically, breaking runs on a non-good hour or a time gap.
        var windows: [ScoredWindow] = []
        var run: [ScoredHour] = []

        func flush() {
            guard !run.isEmpty else { return }
            windows.append(makeWindow(from: run, tuning: tuning))
            run.removeAll(keepingCapacity: true)
        }

        for hour in sorted {
            guard good.contains(hour.date) else { flush(); continue }
            if let previous = run.last {
                let gap = hour.date.timeIntervalSince(previous.date)
                if gap > tuning.maxContiguousGapSeconds { flush() }
            }
            run.append(hour)
        }
        flush()

        return windows
            .sorted { lhs, rhs in
                if lhs.rankScore != rhs.rankScore { return lhs.rankScore > rhs.rankScore }
                return lhs.start < rhs.start        // deterministic tie-break
            }
            .prefix(max(0, tuning.maxWindows))
            .map { $0 }
    }

    // MARK: Window assembly

    private static func makeWindow(from run: [ScoredHour], tuning: Tuning) -> ScoredWindow {
        let count = max(1, run.count)
        let meanRating = clamp(run.reduce(0) { $0 + $1.predictedRating } / Double(count), 0, 5)
        let meanConfidence = clamp(run.reduce(0) { $0 + $1.confidence } / Double(count), 0, 1)

        // Representative hour = the strongest match in the run; its explanation is
        // the one the user sees, because it is the moment the window is built around.
        let representative = run.enumerated().max { lhs, rhs in
            if lhs.element.bestMatchWeight != rhs.element.bestMatchWeight {
                return lhs.element.bestMatchWeight < rhs.element.bestMatchWeight
            }
            return lhs.offset > rhs.offset      // earliest wins ties
        }?.element

        let bonus = min(
            max(0, tuning.maxDurationBonus),
            max(0, tuning.durationBonusPerExtraHour) * Double(count - 1)
        )

        let start = run[0].date
        let end = start.addingTimeInterval(
            max(0, tuning.hourDurationSeconds) * Double(count)
        )

        return ScoredWindow(
            start: start,
            end: max(end, run[count - 1].date),
            predictedRating: meanRating,
            confidence: meanConfidence,
            hourCount: count,
            bestMatch: representative?.bestMatch,
            matchFactors: representative?.matchFactors ?? [],
            rankScore: finite(meanRating + bonus, fallback: meanRating)
        )
    }

    private static func normalisedForecast(_ forecast: [ForecastHour]) -> [ForecastHour] {
        forecast
            .filter { $0.date.timeIntervalSinceReferenceDate.isFinite }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
            .deduplicatedByDate()
    }
}

// MARK: - Model

/// Precomputes everything that depends only on the history, so scoring N forecast
/// hours does not redo it N times.
nonisolated private struct Model {
    let tuning: Tuning
    /// History sanitised: ratings clamped, corrupt numerics dropped, sessions with
    /// too little data removed.
    let sessions: [CleanSession]
    /// Mean rating over usable sessions — the shrinkage prior.
    let priorRating: Double
    /// Population standard deviation of ratings; zero means the history cannot
    /// discriminate between hours at all.
    let ratingSpread: Double
    /// Multiplier that undoes kernel regression's shrinkage toward the mean,
    /// measured from the user's own history by leave-one-out. See
    /// `Tuning/maxCalibrationGain` for why this exists.
    let calibrationGain: Double

    init(history: [RatedSession], tuning: Tuning) {
        self.tuning = tuning

        let cleaned = history.compactMap { CleanSession(session: $0, tuning: tuning) }
        self.sessions = cleaned

        if cleaned.isEmpty {
            self.priorRating = clamp(tuning.neutralPriorRating, 0, 5)
            self.ratingSpread = 0
            self.calibrationGain = 1
            return
        }

        let ratings = cleaned.map(\.rating)
        let mean = ratings.reduce(0, +) / Double(ratings.count)
        let variance = ratings.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(ratings.count)
        let prior = clamp(finite(mean, fallback: 2.5), 0, 5)
        let spread = max(0, finite(variance.squareRoot(), fallback: 0))
        self.priorRating = prior
        self.ratingSpread = spread
        self.calibrationGain = Model.calibrationGain(
            sessions: cleaned, priorRating: prior, ratingSpread: spread, tuning: tuning
        )
    }

    // MARK: Self-calibration

    /// Measures how much the estimator compresses this particular user's ratings,
    /// by predicting every logged session from all the *others* and comparing the
    /// spread of those predictions to the spread of the real ratings.
    ///
    /// Leave-one-out matters: predicting a session while it is still in the history
    /// would make it its own nearest neighbour at distance zero and report no
    /// shrinkage at all. Because the correction is a single global affine map about
    /// the prior, it is strictly monotone and therefore cannot change the *ranking*
    /// of forecast hours — only their calibration in stars.
    private static func calibrationGain(
        sessions: [CleanSession],
        priorRating: Double,
        ratingSpread: Double,
        tuning: Tuning
    ) -> Double {
        guard sessions.count >= max(2, tuning.minCalibrationSessions), ratingSpread > 1e-6 else { return 1 }

        // Most recent first, capped: calibration is O(n^2).
        let ordered = sessions
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.original.date != rhs.element.original.date {
                    return lhs.element.original.date > rhs.element.original.date
                }
                return lhs.offset < rhs.offset
            }
            .prefix(max(2, tuning.calibrationSampleLimit))
            .map(\.offset)

        var predictions: [Double] = []
        predictions.reserveCapacity(ordered.count)
        for index in ordered {
            let raw = rawPrediction(
                query: sessions[index].vector,
                sessions: sessions,
                excluding: index,
                priorRating: priorRating,
                tuning: tuning
            )
            predictions.append(raw.value)
        }

        guard predictions.count >= 2 else { return 1 }
        let mean = predictions.reduce(0, +) / Double(predictions.count)
        let variance = predictions.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(predictions.count)
        let predictedSpread = finite(max(0, variance).squareRoot(), fallback: 0)
        guard predictedSpread > 1e-6 else { return 1 }

        let gain = ratingSpread / predictedSpread
        guard gain.isFinite else { return 1 }
        return clamp(gain, max(0.01, tuning.minCalibrationGain), max(1, tuning.maxCalibrationGain))
    }

    /// Applies the calibration gain, expanding about the prior without ever leaving
    /// 0...5.
    ///
    /// A plain linear expansion followed by a hard clamp would be monotone only in
    /// the interior: with a gain near the 3.0 cap, a large fraction of a day's hours
    /// pin to exactly 0 or exactly 5, collapsing into ties and destroying the very
    /// ordering the scorer exists to produce. Measured, that cost 0.16 of rank
    /// correlation against the uncalibrated model.
    ///
    /// `tanh` squashes the tails into the available headroom instead: it is exactly
    /// linear near the prior, so the measured gain is applied faithfully where
    /// almost all predictions live, and asymptotic at the ends, so extremes stay
    /// ordered and no value can ever reach the boundary.
    static func calibrate(_ raw: Double, priorRating: Double, gain: Double) -> Double {
        let prior = clamp(priorRating, 0, 5)
        let deviation = (raw - prior) * gain
        guard deviation.isFinite else { return prior }
        // Headroom to the nearer boundary; floored so a prior pinned at 0 or 5 does
        // not divide by zero and does not flatten the whole day.
        let headroom = max(0.25, deviation >= 0 ? 5 - prior : prior)
        let scaled = tanh(deviation / headroom) * headroom
        return clamp(finite(prior + scaled, fallback: prior), 0, 5)
    }

    // MARK: Neighbour search and raw prediction

    /// Ranked neighbours for a query, strongest first. `excluding` supports the
    /// leave-one-out pass.
    static func neighbours(
        query: FeatureVector,
        sessions: [CleanSession],
        excluding excluded: Int?,
        tuning: Tuning
    ) -> [Neighbour] {
        var candidates: [Neighbour] = []
        candidates.reserveCapacity(sessions.count)

        for (index, session) in sessions.enumerated() {
            if index == excluded { continue }
            // No per-feature breakdown here: this loop runs once per history entry
            // per query, and O(n^2) times during calibration. The breakdown is
            // recomputed for the single best neighbour once, in `evaluate`.
            guard let pair = compare(query, session.vector, tuning: tuning,
                                     collectBreakdown: false) else { continue }
            let kernel = gaussianKernel(distance: pair.distance, bandwidth: tuning.kernelBandwidth)
            let reliability = pow(
                clamp(pair.overlapRatio, 0, 1),
                max(0, tuning.overlapReliabilityExponent)
            )
            let weight = clamp(finite(kernel * reliability, fallback: 0), 0, 1)
            guard weight > 0 else { continue }
            candidates.append(
                Neighbour(index: index, weight: weight, distance: pair.distance)
            )
        }

        // Deterministic ordering: strongest weight first, index as tie-break so two
        // equally-weighted sessions never swap between runs.
        candidates.sort { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            return lhs.index < rhs.index
        }
        return Array(candidates.prefix(max(1, tuning.neighbourCount)))
    }

    /// Shrunk Nadaraya-Watson, before calibration. See the "WHY THIS ESTIMATOR"
    /// note at the bottom of this file.
    static func rawPrediction(
        query: FeatureVector,
        sessions: [CleanSession],
        excluding excluded: Int?,
        priorRating: Double,
        tuning: Tuning
    ) -> (value: Double, support: Double, neighbours: [Neighbour]) {
        let neighbours = neighbours(query: query, sessions: sessions, excluding: excluded, tuning: tuning)

        let predictionMass = neighbours.reduce(0) { $0 + $1.weight }
        // Confidence support comes from a much tighter neighbourhood so that a
        // crowd of distant sessions cannot add up to false certainty.
        let support = neighbours
            .prefix(max(1, tuning.confidenceNeighbourCount))
            .reduce(0) { $0 + $1.weight }
        let prior = max(0, tuning.priorStrength)
        let numerator = neighbours.reduce(prior * priorRating) { $0 + $1.weight * sessions[$1.index].rating }
        let denominator = predictionMass + prior
        let value = denominator > 1e-12
            ? clamp(finite(numerator / denominator, fallback: priorRating), 0, 5)
            : clamp(priorRating, 0, 5)
        return (value, support, neighbours)
    }

    func evaluate(conditions: ConditionsSample, at date: Date) -> ScoredHour {
        let query = FeatureVector(sample: conditions, tuning: tuning)

        let raw = Model.rawPrediction(
            query: query, sessions: sessions, excluding: nil,
            priorRating: priorRating, tuning: tuning
        )
        let neighbours = raw.neighbours
        let support = raw.support

        // Undo the estimator's shrinkage toward the mean. Strictly monotone in
        // `raw.value`, so the ranking of hours is untouched; only the star scale
        // changes.
        let predicted = Model.calibrate(raw.value, priorRating: priorRating, gain: calibrationGain)

        // --- Confidence -------------------------------------------------------
        // Three independent things must all hold for a prediction to be worth
        // showing, so they multiply rather than average: enough sessions, a close
        // enough neighbourhood, and a history that actually varies.
        let n = Double(sessions.count)
        let countConfidence = saturating(n, halfLife: tuning.confidenceCountHalfLife)
        let supportConfidence = saturating(support, halfLife: tuning.confidenceSupportHalfLife)
        let signalConfidence = saturating(ratingSpread, halfLife: tuning.confidenceSignalHalfLife)
        let confidence = clamp(
            finite(countConfidence * supportConfidence * signalConfidence, fallback: 0), 0, 1
        )

        // --- Explanation ------------------------------------------------------
        // `neighbours` is already ordered by descending similarity, so the first
        // match that is not rated well below the prediction is both the most
        // similar qualifying session and a coherent thing to show the user.
        // See `Tuning/exemplarMaxRatingShortfall`.
        let floor = predicted - max(0, tuning.exemplarMaxRatingShortfall)
        let best = neighbours.first { sessions[$0.index].rating >= floor } ?? neighbours.first
        let factors: [String] = best.flatMap { neighbour in
            compare(query, sessions[neighbour.index].vector, tuning: tuning, collectBreakdown: true)
                .map { Model.matchFactors(for: conditions, comparisons: $0.comparisons, tuning: tuning) }
        } ?? []

        return ScoredHour(
            date: date,
            predictedRating: predicted,
            confidence: confidence,
            bestMatch: best.map { sessions[$0.index].original },
            bestMatchWeight: best?.weight ?? 0,
            matchFactors: factors
        )
    }

    // MARK: Explanation payload

    /// Picks the features that most justify the match and renders them for the UI.
    ///
    /// A feature qualifies on two counts: it must actually agree (distance under
    /// `matchFactorMaxDistance`) and it must matter (high weight). Ranking by
    /// `weight * (1 - distance)` trades those off, so "period agrees closely" beats
    /// "water temperature agrees exactly".
    static func matchFactors(
        for conditions: ConditionsSample,
        comparisons: [FeatureComparison],
        tuning: Tuning
    ) -> [String] {
        let ranked = comparisons
            .filter { $0.distance <= tuning.matchFactorMaxDistance && $0.weight > 0 }
            .map { (comparison: $0, support: $0.weight * (1 - $0.distance)) }
            .sorted { lhs, rhs in
                if lhs.support != rhs.support { return lhs.support > rhs.support }
                return lhs.comparison.feature.rawValue < rhs.comparison.feature.rawValue
            }

        var out: [String] = []
        for entry in ranked {
            guard out.count < max(0, tuning.maxMatchFactors) else { break }
            guard let text = describe(entry.comparison.feature, in: conditions) else { continue }
            if !out.contains(text) { out.append(text) }
        }
        return out
    }

    /// Renders one feature of the *forecast* hour as a phrase.
    ///
    /// Note what is deliberately absent: "offshore" / "onshore". Deciding that
    /// requires the coastline orientation of the break, which this algorithm
    /// explicitly does not model. Claiming it would be a guess dressed as a fact,
    /// so wind is described by strength and compass bearing instead.
    private static func describe(_ feature: ConditionFeature, in c: ConditionsSample) -> String? {
        switch feature {
        case .swellHeight:
            guard let v = sanitise(c.swellWaveHeightMeters, feature: feature) else { return nil }
            return "\(oneDecimal(v)) m swell"
        case .swellPeriod:
            guard let v = sanitise(c.swellWavePeriodSeconds, feature: feature) else { return nil }
            return "\(Int(v.rounded())) s period"
        case .swellDirection:
            guard let v = sanitise(c.swellWaveDirectionDegrees, feature: feature) else { return nil }
            return "\(compassPoint(v)) swell"
        case .windWaveHeight:
            guard let v = sanitise(c.windWaveHeightMeters, feature: feature) else { return nil }
            return v < 0.25 ? "little wind chop" : "\(oneDecimal(v)) m wind chop"
        case .waveHeight:
            guard let v = sanitise(c.waveHeightMeters, feature: feature) else { return nil }
            return "\(oneDecimal(v)) m surf"
        case .windSpeed:
            guard let v = sanitise(c.windSpeedKph, feature: feature) else { return nil }
            let kph = Int(v.rounded())
            if v < 5 { return "glassy (\(kph) km/h)" }
            if v < 12 { return "light wind (\(kph) km/h)" }
            if v < 25 { return "moderate wind (\(kph) km/h)" }
            return "strong wind (\(kph) km/h)"
        case .windDirection:
            guard let v = sanitise(c.windDirectionDegrees, feature: feature) else { return nil }
            return "wind from \(compassPoint(v))"
        case .seaTemperature:
            guard let v = sanitise(c.seaSurfaceTemperatureC, feature: feature) else { return nil }
            return "\(Int(v.rounded()))\u{00B0}C water"
        case .seaLevel:
            guard let v = sanitise(c.seaLevelHeightMeters, feature: feature) else { return nil }
            let sign = v >= 0 ? "+" : "\u{2212}"
            return "\(sign)\(oneDecimal(abs(v))) m tide"
        case .tideTrend:
            guard let t = c.tideTrend else { return nil }
            switch t {
            case .rising: return "rising tide"
            case .falling: return "falling tide"
            case .high: return "high tide"
            case .low: return "low tide"
            }
        }
    }

    private static func oneDecimal(_ v: Double) -> String {
        // String(format:) with no locale argument is non-localised, so the decimal
        // separator is always "." — required for deterministic output.
        String(format: "%.1f", v)
    }

    private static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalised = normaliseDegrees(degrees)
        var index = Int((normalised / 22.5).rounded()) % points.count
        if index < 0 { index += points.count }
        return points[index]
    }
}

// MARK: - Internal model types

nonisolated private struct CleanSession {
    let original: RatedSession
    let rating: Double
    let vector: FeatureVector

    init?(session: RatedSession, tuning: Tuning) {
        let vector = FeatureVector(sample: session.conditions, tuning: tuning)
        // A session that recorded almost nothing can never be a meaningful
        // neighbour, and counting it toward sample-size confidence would overstate
        // how much the user has actually told us.
        guard vector.observedCount >= tuning.minOverlappingFeatures else { return nil }
        guard vector.totalWeight > 1e-12 else { return nil }
        guard vector.observedWeight / vector.totalWeight >= tuning.minOverlapRatio else { return nil }
        self.original = session
        self.rating = clamp(Double(session.rating), 0, 5)
        self.vector = vector
    }
}

nonisolated private struct Neighbour {
    let index: Int
    /// Gaussian kernel of the imputed distance, discounted by how much of the
    /// feature vector was actually comparable.
    let weight: Double
    let distance: Double
}

/// One feature's contribution to a pairwise comparison.
nonisolated struct FeatureComparison: Sendable, Hashable {
    let feature: ConditionFeature
    /// Normalised distance, 0 = identical, clamped at `Tuning.maxFeatureDistance`.
    let distance: Double
    /// Effective weight used for this pair (wind direction is modulated by strength).
    let weight: Double
}

/// A `ConditionsSample` reduced to sanitised numeric slots plus the effective
/// weights implied by it (which depend on the sample itself for wind direction).
nonisolated private struct FeatureVector {
    /// Indexed by `ConditionFeature.rawValue`. `nil` = not comparable.
    let values: [Double?]
    let tideTrend: TideTrend?
    let windSpeed: Double?
    /// Nominal weights, before the wind-direction strength modulation which needs
    /// both samples.
    let nominalWeights: [Double]
    let observedCount: Int
    /// Sum of nominal weights of features this sample actually has.
    let observedWeight: Double
    /// Sum of all nominal weights.
    let totalWeight: Double

    init(sample: ConditionsSample, tuning: Tuning) {
        var values = [Double?](repeating: nil, count: ConditionFeature.allCases.count)
        values[ConditionFeature.swellHeight.rawValue] = sanitise(sample.swellWaveHeightMeters, feature: .swellHeight)
        values[ConditionFeature.swellPeriod.rawValue] = sanitise(sample.swellWavePeriodSeconds, feature: .swellPeriod)
        values[ConditionFeature.swellDirection.rawValue] = sanitise(sample.swellWaveDirectionDegrees, feature: .swellDirection)
        values[ConditionFeature.windWaveHeight.rawValue] = sanitise(sample.windWaveHeightMeters, feature: .windWaveHeight)
        values[ConditionFeature.waveHeight.rawValue] = sanitise(sample.waveHeightMeters, feature: .waveHeight)
        values[ConditionFeature.windSpeed.rawValue] = sanitise(sample.windSpeedKph, feature: .windSpeed)
        values[ConditionFeature.windDirection.rawValue] = sanitise(sample.windDirectionDegrees, feature: .windDirection)
        values[ConditionFeature.seaTemperature.rawValue] = sanitise(sample.seaSurfaceTemperatureC, feature: .seaTemperature)
        values[ConditionFeature.seaLevel.rawValue] = sanitise(sample.seaLevelHeightMeters, feature: .seaLevel)
        // Tide trend is categorical; its slot stays nil and it is compared separately.

        self.values = values
        self.tideTrend = sample.tideTrend
        self.windSpeed = values[ConditionFeature.windSpeed.rawValue]

        let w = tuning.weights
        self.nominalWeights = [
            max(0, w.swellHeight),
            max(0, w.swellPeriod),
            max(0, w.swellDirection),
            max(0, w.windWaveHeight),
            max(0, w.waveHeight),
            max(0, w.windSpeed),
            max(0, w.windDirection),
            max(0, w.seaTemperature),
            max(0, w.seaLevel),
            max(0, w.tideTrend)
        ]

        var count = 0
        var observed = 0.0
        for feature in ConditionFeature.allCases {
            let present = feature == .tideTrend ? (sample.tideTrend != nil) : (values[feature.rawValue] != nil)
            if present {
                count += 1
                observed += nominalWeights[feature.rawValue]
            }
        }
        self.observedCount = count
        self.observedWeight = observed
        self.totalWeight = nominalWeights.reduce(0, +)
    }
}

nonisolated private struct PairComparison {
    /// Effective normalised distance after imputing unobserved features.
    let distance: Double
    /// Fraction of total effective weight that was actually comparable.
    let overlapRatio: Double
    let comparisons: [FeatureComparison]
}

// MARK: - Distance

/// Compares two condition vectors.
///
/// Returns `nil` when the pair shares too little data to be worth using.
///
/// The distance is a weight-normalised RMS over the features present on *both*
/// sides, with unobserved features imputed at `Tuning.missingFeatureDistance`:
///
///     D^2 = r * (sum w_i d_i^2 / sum w_i)  +  (1 - r) * missingDistance^2
///
/// where `r` is the fraction of total weight that was comparable. RMS rather than
/// a plain mean because one badly-mismatched high-weight feature *should* pull the
/// pair apart faster than several small disagreements — a 30 kph wind day is not
/// "sort of like" a glassy day just because the swell matched.
nonisolated private func compare(
    _ a: FeatureVector,
    _ b: FeatureVector,
    tuning: Tuning,
    collectBreakdown: Bool
) -> PairComparison? {
    let cap = max(0, tuning.maxFeatureDistance)

    // Wind direction only matters in proportion to how strong the wind is. Using
    // max(speedA, speedB) means: if either side was windy, the bearing counts; if
    // both were glassy, the bearing is noise and its weight fades to zero. This is
    // an interaction term, not two independent features.
    let strengthFactor: Double = {
        let speeds = [a.windSpeed, b.windSpeed].compactMap { $0 }
        guard let strongest = speeds.max() else {
            return clamp(tuning.windDirectionUnknownStrengthFactor, 0, 1)
        }
        let light = tuning.windDirectionLightKph
        let strong = max(tuning.windDirectionStrongKph, light + 1e-6)
        return clamp((strongest - light) / (strong - light), 0, 1)
    }()

    func effectiveWeight(_ feature: ConditionFeature, _ vector: FeatureVector) -> Double {
        let nominal = vector.nominalWeights[feature.rawValue]
        return feature == .windDirection ? nominal * strengthFactor : nominal
    }

    var comparisons: [FeatureComparison] = []
    if collectBreakdown { comparisons.reserveCapacity(ConditionFeature.allCases.count) }

    var weightedSquares = 0.0
    var comparedWeight = 0.0
    var totalEffectiveWeight = 0.0
    var comparedCount = 0

    for feature in ConditionFeature.allCases {
        let weight = effectiveWeight(feature, a)
        totalEffectiveWeight += weight
        guard weight > 0 else { continue }

        let distance: Double?
        if feature == .tideTrend {
            distance = tideTrendDistance(a.tideTrend, b.tideTrend, tuning: tuning)
        } else if let lhs = a.values[feature.rawValue], let rhs = b.values[feature.rawValue] {
            distance = min(cap, normalisedDistance(feature, lhs, rhs, tuning: tuning))
        } else {
            distance = nil
        }

        guard let d = distance, d.isFinite else { continue }
        comparedCount += 1
        comparedWeight += weight
        weightedSquares += weight * d * d
        if collectBreakdown {
            comparisons.append(FeatureComparison(feature: feature, distance: d, weight: weight))
        }
    }

    guard comparedCount >= tuning.minOverlappingFeatures else { return nil }
    guard totalEffectiveWeight > 1e-12, comparedWeight > 1e-12 else { return nil }

    let overlapRatio = clamp(comparedWeight / totalEffectiveWeight, 0, 1)
    guard overlapRatio >= tuning.minOverlapRatio else { return nil }

    let observedMeanSquare = weightedSquares / comparedWeight
    let imputed = max(0, tuning.missingFeatureDistance)
    let blended = overlapRatio * observedMeanSquare + (1 - overlapRatio) * imputed * imputed
    let distance = finite(max(0, blended).squareRoot(), fallback: cap)

    return PairComparison(distance: distance, overlapRatio: overlapRatio, comparisons: comparisons)
}

/// Per-feature normalised distance in "scales". Circular features wrap correctly.
nonisolated private func normalisedDistance(
    _ feature: ConditionFeature,
    _ lhs: Double,
    _ rhs: Double,
    tuning: Tuning
) -> Double {
    let s = tuning.scales
    let scale: Double
    switch feature {
    case .swellHeight: scale = s.swellHeightMeters
    case .swellPeriod: scale = s.swellPeriodSeconds
    case .swellDirection: scale = s.swellDirectionDegrees
    case .windWaveHeight: scale = s.windWaveHeightMeters
    case .waveHeight: scale = s.waveHeightMeters
    case .windSpeed: scale = s.windSpeedKph
    case .windDirection: scale = s.windDirectionDegrees
    case .seaTemperature: scale = s.seaTemperatureC
    case .seaLevel: scale = s.seaLevelMeters
    case .tideTrend: scale = 1
    }
    guard scale > 1e-9, scale.isFinite else { return 0 }

    let raw = feature.isCircularDegrees ? angularDifference(lhs, rhs) : abs(lhs - rhs)
    return finite(raw / scale, fallback: 0)
}

/// Cyclic categorical distance on rising -> high -> falling -> low -> rising.
/// Adjacent states are half as far apart as opposed ones, because the tide really
/// does pass through "high" on its way from rising to falling.
nonisolated private func tideTrendDistance(_ lhs: TideTrend?, _ rhs: TideTrend?, tuning: Tuning) -> Double? {
    guard let lhs, let rhs else { return nil }
    let steps = abs(lhs.cyclePosition - rhs.cyclePosition)
    let cyclic = min(steps, TideTrend.allCases.count - steps)   // 0, 1 or 2
    let opposite = max(0, tuning.tideTrendOppositeDistance)
    return Double(cyclic) / 2.0 * opposite
}

/// Shortest angular separation in degrees, 0...180. 350 and 10 are 20 apart.
nonisolated private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
    let raw = normaliseDegrees(lhs) - normaliseDegrees(rhs)
    let wrapped = normaliseDegrees(raw + 180) - 180
    return abs(wrapped)
}

/// Maps any finite degree value into 0..<360, including negatives and multiples.
nonisolated private func normaliseDegrees(_ degrees: Double) -> Double {
    guard degrees.isFinite else { return 0 }
    let r = degrees.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

// MARK: - Numeric helpers

/// Rejects non-finite values, and negative readings for quantities that cannot be
/// negative. Corrupt data becomes missing data rather than a poisoned distance.
nonisolated private func sanitise(_ value: Double?, feature: ConditionFeature) -> Double? {
    guard let value, value.isFinite else { return nil }
    if feature.isNonNegativeMagnitude && value < 0 { return nil }
    return value
}

/// Gaussian kernel. Bandwidth is guarded so a zero or corrupt tuning value cannot
/// divide by zero.
nonisolated private func gaussianKernel(distance: Double, bandwidth: Double) -> Double {
    guard distance.isFinite else { return 0 }
    let h = bandwidth.isFinite && bandwidth > 1e-9 ? bandwidth : 1e-9
    let z = distance / h
    let value = exp(-0.5 * z * z)
    return clamp(finite(value, fallback: 0), 0, 1)
}

/// `x / (x + halfLife)` — a saturating 0...1 map reaching 0.5 at `halfLife`.
/// Used for every confidence factor so they share one shape and one intuition.
nonisolated private func saturating(_ x: Double, halfLife: Double) -> Double {
    guard x.isFinite, x > 0 else { return 0 }
    let h = halfLife.isFinite && halfLife > 1e-9 ? halfLife : 1e-9
    return clamp(finite(x / (x + h), fallback: 0), 0, 1)
}

nonisolated private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    guard value.isFinite else { return lower }
    return Swift.min(Swift.max(value, lower), upper)
}

/// Last line of defence: nothing non-finite ever escapes into a public field.
nonisolated private func finite(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? value : fallback
}

nonisolated private extension Array where Element == ScoredHour {
    /// Assumes already sorted by date. Keeps the first of each timestamp so windows
    /// cannot overlap because the caller passed a duplicate hour.
    func deduplicatedByDate() -> [ScoredHour] {
        var out: [ScoredHour] = []
        out.reserveCapacity(count)
        for item in self where out.last?.date != item.date { out.append(item) }
        return out
    }
}

nonisolated private extension Array where Element == ForecastHour {
    func deduplicatedByDate() -> [ForecastHour] {
        var out: [ForecastHour] = []
        out.reserveCapacity(count)
        for item in self where out.last?.date != item.date { out.append(item) }
        return out
    }
}

// MARK: - WHY THIS ESTIMATOR
//
// The prediction is shrunk, k-truncated Nadaraya-Watson kernel regression:
//
//     rating_hat = (sum_j K(d_j) * r_j  +  m * prior) / (sum_j K(d_j) + m)
//
// Alternatives considered and rejected:
//
// 1. Plain k-NN majority / mean vote. Discards distance entirely inside the
//    neighbourhood, so a session 0.05 away and one 1.4 away count the same, and the
//    output jumps discontinuously as the k-th neighbour changes. Also gives no
//    natural way to express "nothing in the history resembles this hour".
//
// 2. Similarity to high-rated minus similarity to low-rated. Produces an
//    uncalibrated score with no units — not comparable across spots or users, and
//    impossible to render in the UI without inventing a scale. Requirement 4 is
//    explicit that an interpretable expected rating is more useful, and it is: the
//    number the algorithm emits is in the same stars the user typed in.
//
// 3. Fitting a parametric model (linear or logistic regression on the features).
//    Needs far more data than a surf logbook holds, cannot express the non-monotone
//    preferences that dominate here (too small is bad, too big is also bad), and
//    handles missing features badly without imputation machinery.
//
// Nadaraya-Watson gets requirement 4 almost for free: high-rated neighbours pull
// the estimate up and low-rated neighbours pull it down, weighted continuously by
// how similar they actually are. Three modifications matter:
//
//   * k-truncation keeps it local. Without it, a user with 300 sessions has the
//     estimate dragged toward their global mean by hundreds of tiny kernel tails.
//
//   * Shrinkage toward the user's own mean rating fixes NW's worst failure mode:
//     when every neighbour is far, the raw weighted mean is still a confident-looking
//     number computed from irrelevant sessions. The pseudo-count makes the estimate
//     decay to "your typical session here" instead, and the support term in
//     confidence flags that it happened.
//
//   * Leave-one-out calibration undoes the shrinkage in the *reported* stars. This
//     one was not in the original design and was forced by measurement: averaging
//     neighbours compresses the predicted range, and across a forecast day the
//     model spanned only 0.58 stars where the truth spanned 1.75. Rank correlation
//     was unaffected — the squeeze is monotone — but every absolute threshold was
//     silently broken, good days barely cleared the 3.0 gate, and the whole day
//     collapsed into a single undifferentiated window. The fix measures the
//     compression from the user's own history and inverts it, restoring the range
//     to 1.45 against 1.70 without touching the ranking.
//
// One honest limitation of shrinking toward the user's mean: a user who only logs
// good sessions has a high prior, so unfamiliar conditions relax to a high rating.
// That is why confidence, not the rating, is the gate the app must enforce.
