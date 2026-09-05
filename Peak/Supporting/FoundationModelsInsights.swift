//
//  FoundationModelsInsights.swift
//
//  The only place in Peak that touches Apple's on-device language model.
//
//  Everything here is doubly gated: `#if canImport(FoundationModels)` so the app
//  still compiles against an SDK without the framework, and `if #available(iOS
//  26, *)` so it still *runs* on the iOS 17 deployment target. On any device or
//  OS where either gate fails, `InsightsModel.makeGenerator()` returns nil and
//  the surfaces render their plain-stats form — which is the whole content, just
//  without the connective prose.
//
//  Nothing in this file is exercised by CI. The engine, the prompt builder, the
//  screening and the fallbacks all live in `InsightsEngine.swift` behind the
//  `InsightsGenerating` seam, and the test suite injects its own generator.
//
//  PRIVACY
//  =======
//  `SystemLanguageModel` runs entirely on the device. There is no network call
//  here — no URLSession, no host, no key — and there must never be one. That is
//  what makes the on-screen copy ("stays on your iPhone") a statement of fact
//  rather than a marketing claim.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Resolves whether on-device generation is possible, and vends a generator when
/// it is.
nonisolated enum InsightsModel {

    /// Why the feature is or is not available right now.
    ///
    /// Every unavailable case is silent at the UI layer. A surfer on an iPhone 14
    /// has not failed at anything and does not need to be told about a feature
    /// their phone cannot run; a surfer whose model assets are still downloading
    /// will simply see the prose appear one day.
    static var availability: InsightsAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceNotEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    // A reason added in a later OS is treated as "not now",
                    // which is the safe read: hide the prose, keep the figures.
                    return .modelNotReady
                }
            }
        }
        return .unsupportedOS
        #else
        return .unsupportedOS
        #endif
    }

    /// `nil` whenever there is nothing to ask. Callers must treat that as normal.
    static func makeGenerator() -> (any InsightsGenerating)? {
        // UI tests explicitly cover both states: no model by default, and the
        // model-written layout only when the stub scenario is requested. Do not
        // let a simulator runtime that reports a transiently available system
        // model make those two contracts nondeterministic.
        if TestingDefaults.isUITest {
            return stubGenerator()
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability.isAvailable {
            return FoundationModelsInsightsGenerator()
        }
        #endif
        return nil
    }

    /// UI-test seam, mirroring `UITESTS_SURF_CONDITIONS_SCENARIO`.
    ///
    /// The simulator has no Apple Intelligence, so without this the AI layout
    /// would be unreachable from the UI suite and could rot unnoticed. `stub`
    /// makes the *layout* testable with a canned draft; it is not a model and no
    /// test asserts anything about model quality. Only set under `UITESTS`.
    private static func stubGenerator() -> (any InsightsGenerating)? {
        guard TestingDefaults.isUITest, let scenario = TestingDefaults.insightsScenario else {
            return nil
        }
        return scenario == "stub" ? StubInsightsGenerator() : nil
    }
}

/// A fixed, screening-passing draft for UI tests. Deliberately numeral-free and
/// name-free so it survives `InsightsSanitizer` on any fixture.
nonisolated struct StubInsightsGenerator: InsightsGenerating {
    func draft(prompt: String, instructions: String) async throws -> InsightsDraft {
        InsightsDraft(
            headline: "A solid stretch in the water",
            highlights: ["You kept showing up when it was worth it."],
            suggestion: "Keep rating sessions and the picture gets sharper.",
            wasTruncated: false
        )
    }
}

#if canImport(FoundationModels)

/// The shape guided generation fills in.
///
/// Every field is prose. There is no `Int`, no `Double` and no date anywhere in
/// this type, and that is the point: the schema itself makes it impossible for
/// the model to hand back a figure that could be mistaken for one of Peak's.
/// Figures are interpolated by `MonthlyRecapFacts` / `YearNarrativeFacts`.
@available(iOS 26.0, *)
@Generable
struct GeneratedInsight {
    @Guide(description: "One short clause summing up the period. No numbers, no place names, no punctuation at the end.")
    var headline: String

    @Guide(description: "Up to three very short clauses adding colour. No numbers. Only names that appear in the facts.", .maximumCount(3))
    var highlights: [String]

    @Guide(description: "One short, gentle suggestion. No numbers. Empty string if the facts do not support one.")
    var suggestion: String
}

/// Bridges `GeneratedInsight` to the plain `InsightsDraft` the rest of the app
/// speaks, and turns a model that ran out of room into a draft flagged as
/// truncated rather than an error.
@available(iOS 26.0, *)
nonisolated struct FoundationModelsInsightsGenerator: InsightsGenerating {

    /// Output ceiling.
    ///
    /// The window is roughly four thousand tokens covering the prompt *and* the
    /// response, so a generous ceiling here is a bill the prompt pays. Two or
    /// three clauses is all either surface renders; anything longer would be
    /// trimmed by `InsightsSanitizer` anyway.
    static let maximumResponseTokens = 220

    /// Low temperature: this is a caption over fixed facts, not a creative brief.
    /// Variation between launches would read as instability, not personality.
    static let temperature = 0.4

    /// `@concurrent` rather than plain `nonisolated`: the target builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
    /// `SWIFT_APPROACHABLE_CONCURRENCY`, under which a nonisolated async function
    /// inherits the caller's actor. Inference takes seconds; it must not inherit
    /// the main actor.
    @concurrent
    func draft(prompt: String, instructions: String) async throws -> InsightsDraft {
        let session = LanguageModelSession(instructions: Instructions(instructions))
        let options = GenerationOptions(
            temperature: Self.temperature,
            maximumResponseTokens: Self.maximumResponseTokens
        )

        // Streamed rather than awaited whole, purely so a response that runs out
        // of room still yields its finished prefix. `respond(to:)` would throw
        // and discard a headline the model had already written perfectly well.
        var latest: GeneratedInsight.PartiallyGenerated?
        var truncated = false

        do {
            let stream = session.streamResponse(
                to: prompt,
                generating: GeneratedInsight.self,
                options: options
            )
            for try await snapshot in stream {
                latest = snapshot.content
            }
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                // The prompt is fixed-size and small, so this means the *response*
                // hit the ceiling. Keep the prefix and let the sanitiser decide
                // how much of it survives.
                truncated = true
            default:
                throw error
            }
        }

        guard let latest else {
            throw InsightsUnavailableError(availability: InsightsModel.availability)
        }

        let headline = latest.headline ?? ""
        let highlights = latest.highlights ?? []
        let suggestion = latest.suggestion ?? ""

        // A partially generated struct with a missing tail is the other face of
        // truncation: the stream ended before the schema was filled.
        let incomplete = latest.headline == nil || latest.highlights == nil || latest.suggestion == nil

        return InsightsDraft(
            headline: headline,
            highlights: highlights,
            suggestion: suggestion,
            wasTruncated: truncated || incomplete
        )
    }
}

#endif
