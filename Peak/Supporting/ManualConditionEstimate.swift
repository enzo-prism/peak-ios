import Foundation

/// Numeric stand-ins for the session editor's coarse Wind and Wave pickers.
///
/// `SurfSession` carries two parallel descriptions of the same two quantities:
/// the numeric `windSpeedKph` / `waveHeightMeters` that auto-fill writes, and the
/// `WindCondition` / `WaveHeight` enums the editor's pickers bind to. Until 3.0
/// only the numeric pair ever reached `WindowScorer`, so a surfer who filled in
/// both pickers on every session contributed *nothing* to their own model: with
/// zero observed features every session was rejected by `CleanSession.init?`,
/// which needs at least `Tuning.minOverlappingFeatures` (2), and the card told
/// them to "log a few more sessions" no matter how many they logged.
///
/// These two functions are the exact inverse of `SurfConditionsMapping`, which is
/// the app's own definition of what each band means: auto-fill classifies 10 km/h
/// as `.breezy`, so `.breezy` maps back to 10 km/h. Round-tripping a value
/// through both directions is therefore an identity, and
/// `ManualConditionEstimateTests` pins that — if anyone re-bands the classifier
/// without re-banding this, the suite says so.
///
/// **Why no extra weight penalty for these values.** They are coarser than a
/// measured reading (a `.breezy` session is somewhere in 5...15 km/h, and the
/// wind-speed scale is 8 km/h, so the band midpoint can be up to ~0.6 "scales"
/// wrong), which is a real argument for discounting them. It is not applied,
/// because the scorer *already* discounts exactly this sparsity twice over and a
/// third discount would be double counting:
///
/// 1. A picker-only session observes 2 of 10 features, so its overlap ratio is
///    1.3 / 6.05 = 0.215 and its neighbour weight is multiplied by
///    0.215^`overlapReliabilityExponent` = 0.41.
/// 2. `compare` imputes the eight unobserved features at
///    `missingFeatureDistance`, which floors the pair distance at
///    sqrt(1 - 0.215) = 0.886 even on a perfect match — a Gaussian kernel value
///    of 0.14 against 1.0 for a fully-observed exact match.
///
/// Net: a picker-only session enters the model at roughly 6% of the pull of a
/// fully auto-filled one. That is already a far heavier penalty than the ~0.6
/// scales of quantisation error justifies, and it is applied by the same
/// mechanism that handles every other kind of sparse session rather than by a
/// special case. What these values change is not how loudly a session speaks but
/// *whether it is in the room at all*.
nonisolated enum ManualConditionEstimate {

    /// Representative wind speed for a picker choice, in km/h.
    ///
    /// Midpoint of each closed band from `SurfConditionsMapping.windCondition`.
    /// `.strong` is open-ended (25 km/h and up) so there is no midpoint: 30 km/h
    /// is used, one wind-speed scale (8 km/h) short of double the band floor —
    /// unambiguously "super windy" without inventing a storm the surfer never
    /// described.
    static func windSpeedKph(for condition: WindCondition) -> Double {
        switch condition {
        case .calm: return 2.5      // 0...5
        case .breezy: return 10     // 5...15
        case .windy: return 20      // 15...25
        case .strong: return 30     // 25+
        }
    }

    /// Representative significant wave height for a picker choice, in metres.
    ///
    /// Midpoint of each closed band from
    /// `SurfConditionsMapping.waveHeightCategory`. `.wayOverhead` is open-ended
    /// (2.4 m and up): 2.9 m sits about one and a quarter wave-height scales
    /// (0.40 m) above the floor, which reads as clearly bigger than `.overhead`
    /// without claiming a size the surfer did not.
    ///
    /// Note this is *significant wave height*, matching the field it fills and
    /// the classifier it inverts — not the face height a surfer would quote.
    static func waveHeightMeters(for height: WaveHeight) -> Double {
        switch height {
        case .kneeHigh: return 0.3          // 0...0.6
        case .waistHigh: return 0.9         // 0.6...1.2
        case .shoulderHigh: return 1.5      // 1.2...1.8
        case .overhead: return 2.1          // 1.8...2.4
        case .wayOverhead: return 2.9       // 2.4+
        }
    }
}
