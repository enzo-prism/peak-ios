//
//  InsightsEngine.swift
//
//  On-device narrative insights over the logbook.
//
//  DESIGN THESIS
//  =============
//  A language model is used here for exactly one thing: connective language.
//  It is never used as a source of fact.
//
//  Peak's numbers are hard-won — they are the surfer's own logged sessions — and
//  a recap that says "eleven sessions" when there were nine is worse than no
//  recap at all. So the pipeline is built so that the model *cannot* contribute a
//  figure even if it tries:
//
//   1. **Aggregate first.** `StatsCalculator` / `GearInsightsCalculator` /
//      `YearInReviewCalculator` output is reduced to a small `…Facts` value.
//      Raw session rows never reach the model — the context window is ~4k tokens
//      covering input *and* output, and a logbook is unbounded.
//   2. **The prompt carries no numerals.** Facts are handed to the model as
//      qualitative descriptors ("busier than last month", "rated highly"), not as
//      digits. A model that never sees a number cannot copy one incorrectly.
//      The only digits that may appear in a prompt are those inside a name the
//      surfer themselves typed (a board called `6'2" Fish`).
//   3. **Output is screened.** `InsightsSanitizer` discards any generated text
//      containing a digit, a number word, or a capitalised word that is not in
//      the allow-list built from the facts. A discarded field is dropped; a
//      discarded headline drops the whole draft.
//   4. **Figures are interpolated by us.** Every number the surfer reads on
//      screen comes from `…Facts`, rendered by `plain…` properties in this file.
//      Those same properties are the non-AI fallback, so the surfaces render
//      identically-truthful content with or without Apple Intelligence.
//
//  Everything in this file is pure Foundation and compiles on iOS 17. The model
//  boundary is the `InsightsGenerating` protocol; the FoundationModels
//  implementation lives in `FoundationModelsInsights.swift` behind
//  `#if canImport(FoundationModels)` + `if #available(iOS 26, *)`, and CI never
//  touches it.
//

import Foundation

// MARK: - Availability

/// Why on-device insight generation is or is not possible right now.
///
/// Deliberately mirrors `SystemLanguageModel.Availability` without depending on
/// it, so the engine, its fallbacks and its tests all exist on iOS 17 where
/// FoundationModels does not.
nonisolated enum InsightsAvailability: Equatable, Sendable {
    case available
    /// Running below iOS 26, or built against an SDK without FoundationModels.
    case unsupportedOS
    /// Apple-Intelligence-capable hardware is required and this isn't it.
    case deviceNotEligible
    /// Capable device, but the user has Apple Intelligence turned off.
    case appleIntelligenceNotEnabled
    /// Enabled, but the assets are still downloading or the device is too hot /
    /// too low on battery. Transient — worth retrying later, never worth a
    /// message.
    case modelNotReady

    var isAvailable: Bool { self == .available }
}

// MARK: - Facts

/// A name with the number of sessions behind it.
nonisolated struct InsightsNamedCount: Sendable, Equatable {
    let name: String
    let count: Int
}

/// What one board did this period. `averageRating` and `conditionsPhrase` are
/// `nil` below `GearInsightsCalculator.minimumBucketSessions`, because a single
/// good session is not a pattern and printing it as one is misinformation.
nonisolated struct InsightsBoardFact: Sendable, Equatable {
    let name: String
    let sessionCount: Int
    let averageRating: Double?
    /// e.g. "short-period waist-high".
    let conditionsPhrase: String?
}

/// How this month compares with the one before it.
nonisolated enum InsightsActivityTrend: String, Sendable, Equatable {
    /// Nothing logged before this month.
    case firstMonth
    case busier
    case quieter
    case steady
}

/// Rating tone, bucketed. The model gets the bucket, never the average.
nonisolated enum InsightsRatingTone: String, Sendable, Equatable {
    case unrated
    case poor
    case mixed
    case good
    case excellent
}

/// How concentrated the month was on one break.
nonisolated enum InsightsSpotSpread: String, Sendable, Equatable {
    case none
    case single
    case dominant
    case varied
}

/// Everything the monthly recap is allowed to say, pre-aggregated.
///
/// This is the entire input to the model. It is bounded: a surfer with ten
/// thousand sessions produces exactly the same number of bytes here as a surfer
/// with ten.
nonisolated struct MonthlyRecapFacts: Sendable, Equatable {
    let monthName: String
    let year: Int
    let sessionCount: Int
    let surfDays: Int
    let totalMinutes: Int
    let averageRating: Double?
    let topSpot: InsightsNamedCount?
    let distinctSpotCount: Int
    let topBoard: InsightsBoardFact?
    let previousMonthSessionCount: Int
    let hasEarlierHistory: Bool
    /// Set only when this month beat every earlier month on record; carries the
    /// month it beat, so the surface can say "your best since March".
    let previousBestMonthName: String?

    var isEmpty: Bool { sessionCount == 0 }

    var activityTrend: InsightsActivityTrend {
        guard hasEarlierHistory else { return .firstMonth }
        // A single session either way is noise, not a trend.
        if sessionCount > previousMonthSessionCount + 1 { return .busier }
        if sessionCount + 1 < previousMonthSessionCount { return .quieter }
        return .steady
    }

    var ratingTone: InsightsRatingTone {
        guard let averageRating else { return .unrated }
        if averageRating >= 4.2 { return .excellent }
        if averageRating >= 3.4 { return .good }
        if averageRating >= 2.5 { return .mixed }
        return .poor
    }

    var spotSpread: InsightsSpotSpread {
        guard let topSpot, sessionCount > 0 else { return .none }
        if distinctSpotCount <= 1 { return .single }
        return Double(topSpot.count) / Double(sessionCount) >= 0.6 ? .dominant : .varied
    }

    /// Every proper noun the model is permitted to use. Anything else in its
    /// output is treated as invented and the field is dropped.
    var allowedNames: [String] {
        var names: [String] = [monthName]
        if let topSpot { names.append(topSpot.name) }
        if let topBoard { names.append(topBoard.name) }
        if let previousBestMonthName { names.append(previousBestMonthName) }
        return names
    }
}

/// Everything the year-recap narrative is allowed to say. Built from an already
/// computed `YearInReview` so the recap screen and the narrative can never
/// disagree about a figure.
nonisolated struct YearNarrativeFacts: Sendable, Equatable {
    let year: Int
    let sessionCount: Int
    let surfDays: Int
    let totalMinutes: Int
    let averageRating: Double?
    let topSpot: InsightsNamedCount?
    let topGear: InsightsNamedCount?
    let bestMonthName: String?
    let bestMonthCount: Int
    let longestWeekStreak: Int
    /// The wave-height band that appeared most often, e.g. "Waist high".
    let dominantWaveBandLabel: String?

    var isEmpty: Bool { sessionCount == 0 }

    var ratingTone: InsightsRatingTone {
        guard let averageRating else { return .unrated }
        if averageRating >= 4.2 { return .excellent }
        if averageRating >= 3.4 { return .good }
        if averageRating >= 2.5 { return .mixed }
        return .poor
    }

    var allowedNames: [String] {
        var names: [String] = []
        if let topSpot { names.append(topSpot.name) }
        if let topGear { names.append(topGear.name) }
        if let bestMonthName { names.append(bestMonthName) }
        if let dominantWaveBandLabel { names.append(dominantWaveBandLabel) }
        return names
    }
}

// MARK: - Model output

/// Raw prose from the model, before screening. Deliberately a plain value type
/// with no FoundationModels types in it, so the sanitiser, the fallback path and
/// every test compile on iOS 17.
nonisolated struct InsightsDraft: Sendable, Equatable {
    var headline: String
    var highlights: [String]
    var suggestion: String
    /// The model hit its token ceiling. The tail of the response is then assumed
    /// unfinished rather than merely terse — see `InsightsSanitizer.repair`.
    var wasTruncated: Bool

    init(headline: String = "", highlights: [String] = [], suggestion: String = "", wasTruncated: Bool = false) {
        self.headline = headline
        self.highlights = highlights
        self.suggestion = suggestion
        self.wasTruncated = wasTruncated
    }
}

/// What a surface renders. `figures` and `plainHighlights` are always populated
/// from the aggregates; `narrative` and `suggestion` are the model's connective
/// language and are `nil` whenever the model is unavailable, declined, or said
/// something that failed screening.
nonisolated struct MonthlyRecap: Sendable, Equatable {
    let facts: MonthlyRecapFacts
    let narrative: String?
    let suggestion: String?

    var isModelWritten: Bool { narrative != nil }
}

// MARK: - Model boundary

/// The single seam between Peak and any language model.
///
/// Async by construction: the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, under which a synchronous call
/// would run on the UI thread. Implementations must hop off main themselves.
nonisolated protocol InsightsGenerating: Sendable {
    func draft(prompt: String, instructions: String) async throws -> InsightsDraft
}

/// Raised when there is no model to ask. Kept separate from a generation failure
/// so callers can stay silent for the former and (optionally) retry the latter.
nonisolated struct InsightsUnavailableError: Error, Equatable {
    let availability: InsightsAvailability
}

// MARK: - Prompt building

/// Builds the model's instructions and prompt from facts.
///
/// The invariant this type exists to hold: **no numerals reach the model except
/// inside names the surfer typed themselves.** `InsightsEngineTests` asserts it
/// directly by masking the allow-listed names out of a built prompt and checking
/// what remains is digit-free.
nonisolated enum InsightsPromptBuilder {

    /// Shared house style. Sent as `Instructions` (a privileged channel the
    /// model weights above prompt text) precisely because these are the rules
    /// that keep the output honest.
    static let instructions = """
        You write one or two sentences of plain, calm commentary for a surfer's \
        own logbook. You are a caption writer, not an analyst.

        Rules you must never break:
        - Never write a digit or a number word. Counts, hours, averages and dates \
        are printed next to your text by the app; repeating them is wrong.
        - Never name a place, break, board, brand or person unless that exact \
        name appears in the facts below. Never invent one.
        - Never state anything the facts do not say. Do not guess at weather, \
        crowds, travel, injuries or the future.
        - Write in second person, present or past tense. No emoji, no hashtags, \
        no exclamation marks, no greetings.
        - Keep it short. A headline is one clause. A suggestion is one sentence.
        """

    /// The monthly recap prompt.
    static func monthlyRecapPrompt(facts: MonthlyRecapFacts) -> String {
        var lines: [String] = []
        lines.append("Facts about the surfer's month of \(facts.monthName):")
        lines.append("- how much they surfed: \(volumePhrase(facts))")
        lines.append("- compared with the month before: \(trendPhrase(facts.activityTrend))")
        lines.append("- how they rated the sessions: \(tonePhrase(facts.ratingTone))")
        lines.append("- where: \(spotPhrase(facts))")
        if let board = facts.topBoard {
            lines.append("- board they reached for most: \(board.name)\(boardSuffix(board))")
        }
        if facts.previousBestMonthName != nil {
            lines.append("- this was their biggest month since \(facts.previousBestMonthName ?? "")")
        }
        lines.append("")
        lines.append("Write a headline clause, up to three short highlight clauses, and one suggestion for next month.")
        return lines.joined(separator: "\n")
    }

    /// The year-recap prompt.
    static func yearNarrativePrompt(facts: YearNarrativeFacts) -> String {
        var lines: [String] = []
        // The year itself is four digits, so it is described rather than named.
        // The surface prints it in the heading immediately above the narrative.
        lines.append("Facts about the surfer's year:")
        lines.append("- how much they surfed: \(yearVolumePhrase(facts))")
        lines.append("- how they rated the sessions: \(tonePhrase(facts.ratingTone))")
        if let spot = facts.topSpot {
            lines.append("- the break they surfed most: \(spot.name)")
        }
        if let gear = facts.topGear {
            lines.append("- the gear they used most: \(gear.name)")
        }
        if let month = facts.bestMonthName {
            lines.append("- their busiest month: \(month)")
        }
        if let band = facts.dominantWaveBandLabel {
            lines.append("- the size they surfed most often: \(band)")
        }
        if facts.longestWeekStreak >= 4 {
            lines.append("- they kept a long unbroken run of weeks in the water")
        }
        lines.append("")
        lines.append("Write a headline clause and one short paragraph of up to three clauses looking back on the year. Leave the suggestion empty.")
        return lines.joined(separator: "\n")
    }

    /// Rough token estimate (~4 characters per token) used to keep prompts far
    /// below the shared ~4k input+output window. Not exact and does not need to
    /// be — the point is to fail a test loudly if a prompt ever starts growing
    /// with the size of the logbook.
    static func approximateTokenCount(_ text: String) -> Int {
        (text.count + 3) / 4
    }

    // MARK: Phrases (all numeral-free by construction)

    private static func volumePhrase(_ facts: MonthlyRecapFacts) -> String {
        if facts.sessionCount == 0 { return "they did not get in the water" }
        if facts.sessionCount == 1 { return "a single session" }
        if facts.sessionCount <= 3 { return "a handful of sessions" }
        if facts.sessionCount <= 8 { return "a steady run of sessions" }
        if facts.sessionCount <= 15 { return "a busy month of sessions" }
        return "an unusually heavy month of sessions"
    }

    private static func yearVolumePhrase(_ facts: YearNarrativeFacts) -> String {
        if facts.sessionCount == 0 { return "they logged nothing" }
        if facts.sessionCount == 1 { return "a single logged session" }
        if facts.sessionCount <= 10 { return "an occasional year in the water" }
        if facts.sessionCount <= 40 { return "a regular year in the water" }
        if facts.sessionCount <= 100 { return "a committed year in the water" }
        return "a relentless year in the water"
    }

    private static func trendPhrase(_ trend: InsightsActivityTrend) -> String {
        switch trend {
        case .firstMonth: return "there is no earlier month to compare with"
        case .busier: return "busier"
        case .quieter: return "quieter"
        case .steady: return "about the same"
        }
    }

    private static func tonePhrase(_ tone: InsightsRatingTone) -> String {
        switch tone {
        case .unrated: return "they did not rate them"
        case .poor: return "mostly disappointing"
        case .mixed: return "mixed"
        case .good: return "good"
        case .excellent: return "excellent"
        }
    }

    private static func spotPhrase(_ facts: MonthlyRecapFacts) -> String {
        guard let spot = facts.topSpot else { return "no break was recorded" }
        switch facts.spotSpread {
        case .none, .single:
            return "every session at \(spot.name)"
        case .dominant:
            return "mostly at \(spot.name)"
        case .varied:
            return "spread across several breaks, most often at \(spot.name)"
        }
    }

    private static func boardSuffix(_ board: InsightsBoardFact) -> String {
        guard let phrase = board.conditionsPhrase else { return "" }
        return ", which suited \(phrase) conditions"
    }
}

// MARK: - Screening

/// Screens model output for anything it was not given.
///
/// This is the load-bearing safety component. It is deliberately blunt: a field
/// that trips any rule is dropped rather than repaired, because a *partially*
/// corrected sentence is exactly the kind of plausible-sounding wrongness this
/// whole design exists to avoid. Dropping everything falls back to the plain
/// figures, which are always correct.
nonisolated enum InsightsSanitizer {

    /// Number words, spelled out. Digits are caught separately.
    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty",
        "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
        "thousand", "dozen", "half", "quarter", "third", "twice", "thrice",
        "once", "double", "triple", "percent",
        "first", "second", "fourth", "fifth", "sixth", "seventh", "eighth",
        "ninth", "tenth"
    ]

    /// Capitalised words that are never a claim about the world.
    private static let safeCapitalisedWords: Set<String> = ["i", "i'm", "i've", "i'll"]

    /// Hard ceilings. A model that runs long has stopped writing a caption.
    static let maximumHeadlineCharacters = 110
    static let maximumHighlightCharacters = 140
    static let maximumSuggestionCharacters = 160
    static let maximumHighlights = 3

    /// Screens a whole draft. Returns `nil` when nothing survived that is worth
    /// showing — the caller then renders plain figures only.
    static func sanitize(_ draft: InsightsDraft, allowedNames: [String]) -> InsightsDraft? {
        let repaired = repair(draft)
        let allowed = allowedTokens(from: allowedNames)

        guard let headline = clean(
            repaired.headline,
            limit: maximumHeadlineCharacters,
            allowedNames: allowedNames,
            allowedTokens: allowed
        ) else {
            return nil
        }

        let highlights = repaired.highlights
            .compactMap {
                clean($0, limit: maximumHighlightCharacters, allowedNames: allowedNames, allowedTokens: allowed)
            }
            .prefix(maximumHighlights)

        let suggestion = clean(
            repaired.suggestion,
            limit: maximumSuggestionCharacters,
            allowedNames: allowedNames,
            allowedTokens: allowed
        )

        return InsightsDraft(
            headline: headline,
            highlights: Array(highlights),
            suggestion: suggestion ?? "",
            wasTruncated: repaired.wasTruncated
        )
    }

    /// Undoes the damage of a response that hit the token ceiling.
    ///
    /// A truncated response's last field is mid-sentence. Guided generation fills
    /// the struct in declaration order, so the tail is the untrustworthy part: we
    /// drop a suggestion that never finished and the final highlight, which the
    /// model had no chance to complete. The headline is written first and is
    /// almost always intact — but it is still checked for a terminator, and a
    /// headline that stops mid-word is discarded by `clean`.
    static func repair(_ draft: InsightsDraft) -> InsightsDraft {
        guard draft.wasTruncated else { return draft }
        var repaired = draft

        if !endsCleanly(repaired.suggestion) {
            repaired.suggestion = ""
        }
        if let last = repaired.highlights.last, !endsCleanly(last) {
            repaired.highlights.removeLast()
        }
        if !endsCleanly(repaired.headline) && !repaired.headline.isEmpty {
            // A headline is a clause and may legitimately lack punctuation, so
            // only an obviously severed one (no trailing terminator *and* the
            // suggestion also unfinished, i.e. it was the truncation point) goes.
            if repaired.highlights.isEmpty && draft.suggestion.isEmpty {
                repaired.headline = ""
            }
        }
        return repaired
    }

    /// `true` when the text ends at a sentence boundary rather than mid-thought.
    static func endsCleanly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return true }
        return ".!?".contains(last)
    }

    /// `true` when `text` contains a figure the model was never given.
    /// Occurrences of allow-listed names are masked out first, so a board named
    /// `6'2" Fish` does not trip the digit rule.
    static func containsForbiddenFigure(_ text: String, allowedNames: [String]) -> Bool {
        let masked = mask(text, names: allowedNames)
        if masked.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        if masked.contains("★") || masked.contains("%") { return true }
        for token in words(in: masked) where numberWords.contains(token) {
            return true
        }
        return false
    }

    /// `true` when `text` uses a proper noun that is not in the allow-list.
    ///
    /// Sentence-initial capitals are exempt (every sentence starts with one).
    /// Everything else capitalised mid-sentence is treated as a name, and a name
    /// the facts did not supply is by definition invented.
    static func containsUnknownProperNoun(_ text: String, allowedTokens: Set<String>) -> Bool {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        var atSentenceStart = true
        for raw in tokens {
            let bare = String(raw).trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'’")))
            let terminates = raw.last.map { ".!?:;—".contains($0) } ?? false
            defer { atSentenceStart = terminates }

            guard let first = bare.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { continue }
            if atSentenceStart { continue }
            let folded = bare.lowercased()
            if safeCapitalisedWords.contains(folded) { continue }
            if allowedTokens.contains(folded) { continue }
            // "July's" is the same name as "July"; a possessive or a contraction
            // is not a different proper noun.
            let stem = String(folded.split(whereSeparator: { $0 == "'" || $0 == "\u{2019}" }).first ?? "")
            if allowedTokens.contains(stem) || safeCapitalisedWords.contains(stem) { continue }
            return true
        }
        return false
    }

    /// The set of lower-cased word tokens the model may capitalise.
    static func allowedTokens(from names: [String]) -> Set<String> {
        var tokens: Set<String> = []
        for name in names {
            for token in words(in: name) {
                tokens.insert(token)
            }
        }
        return tokens
    }

    // MARK: Private

    /// Trims, then applies every rule. `nil` means "drop this field".
    private static func clean(
        _ text: String,
        limit: Int,
        allowedNames: [String],
        allowedTokens: Set<String>
    ) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models like to wrap a single field in quotes or lead with a bullet.
        while let first = trimmed.first, "\"'“‘-–—*•".contains(first) {
            trimmed.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }
        while let last = trimmed.last, "\"'”’".contains(last) {
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }

        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= limit else { return nil }
        guard !containsForbiddenFigure(trimmed, allowedNames: allowedNames) else { return nil }
        guard !containsUnknownProperNoun(trimmed, allowedTokens: allowedTokens) else { return nil }
        return trimmed
    }

    /// Removes every occurrence of every allow-listed name, case-insensitively.
    private static func mask(_ text: String, names: [String]) -> String {
        var masked = text
        // Longest first, so "Ocean Beach" is removed before "Ocean" would be.
        for name in names.sorted(by: { $0.count > $1.count }) where !name.isEmpty {
            masked = masked.replacingOccurrences(of: name, with: " ", options: [.caseInsensitive])
        }
        return masked
    }

    /// Lower-cased alphanumeric word tokens.
    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}

// MARK: - Plain rendering (the non-AI form of everything above)

/// Deterministic, figure-only renderings of the facts.
///
/// These are not a consolation prize. They are the primary content of both
/// surfaces: the model's prose is layered *on top* of them, never instead of
/// them. That is what makes the feature safe to hide entirely on a device
/// without Apple Intelligence — nothing factual is lost, only phrasing.
// Main-actor by default (the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION`), like
// `StatsFormat` which these lean on. They are view-layer strings; nothing off the
// main actor needs them.
extension MonthlyRecapFacts {
    /// "July recap".
    var title: String { "\(monthName) recap" }

    /// "9 sessions · 11h 20m · 4.2★ avg". Only figures that exist are shown.
    var plainFigures: String {
        var parts = ["\(sessionCount) session\(sessionCount == 1 ? "" : "s")"]
        if totalMinutes > 0 {
            parts.append(StatsFormat.duration(totalMinutes))
        }
        if let averageRating {
            parts.append("\(StatsFormat.rating(averageRating))★ avg")
        }
        return parts.joined(separator: " · ")
    }

    /// The figure-bearing lines. Every one of these is an aggregate, never a
    /// generated claim, so the card reads the same on any device.
    var plainHighlights: [String] {
        guard !isEmpty else { return [] }
        var lines: [String] = []

        if surfDays > 0, surfDays != sessionCount {
            lines.append("\(surfDays) surf day\(surfDays == 1 ? "" : "s")")
        }
        if let topSpot {
            lines.append("Most days at \(topSpot.name) (\(topSpot.count))")
        }
        if let board = topBoard {
            if let phrase = board.conditionsPhrase, let rating = board.averageRating {
                lines.append("\(board.name) averaged \(StatsFormat.rating(rating))★ in \(phrase)")
            } else {
                lines.append("\(board.name) on \(board.sessionCount) session\(board.sessionCount == 1 ? "" : "s")")
            }
        }
        if let previousBestMonthName {
            lines.append("Your biggest month since \(previousBestMonthName)")
        } else {
            switch activityTrend {
            case .firstMonth:
                break
            case .busier, .quieter, .steady:
                lines.append(
                    "\(previousMonthSessionCount) session\(previousMonthSessionCount == 1 ? "" : "s") the month before"
                )
            }
        }
        return lines
    }

    /// VoiceOver reads the card as one sentence rather than a list of fragments.
    var accessibilitySummary: String {
        ([plainFigures] + plainHighlights).joined(separator: ", ")
    }
}

extension YearNarrativeFacts {
    /// The recap paragraph in plain-stats form. This is what renders when no
    /// model wrote one — same facts, flatter prose.
    var plainNarrative: String {
        guard !isEmpty else {
            return "Nothing logged this year yet."
        }
        var sentences: [String] = []

        var opening = "You logged \(sessionCount) session\(sessionCount == 1 ? "" : "s")"
        if surfDays > 0 {
            opening += " across \(surfDays) day\(surfDays == 1 ? "" : "s")"
        }
        if totalMinutes > 0 {
            opening += ", \(StatsFormat.duration(totalMinutes)) in the water"
        }
        sentences.append(opening + ".")

        if let topSpot {
            sentences.append("Most days at \(topSpot.name) (\(topSpot.count)).")
        }
        if let bestMonthName, bestMonthCount > 0 {
            sentences.append(
                "\(bestMonthName) was your busiest month with \(bestMonthCount) session\(bestMonthCount == 1 ? "" : "s")."
            )
        }
        if let topGear {
            sentences.append("You reached for your \(topGear.name) most (\(topGear.count)).")
        }
        if let dominantWaveBandLabel {
            sentences.append("Most of it was \(dominantWaveBandLabel.lowercased()).")
        }
        if let averageRating {
            sentences.append("You rated the year \(StatsFormat.rating(averageRating))★ on average.")
        }
        return sentences.joined(separator: " ")
    }
}

// MARK: - Engine

/// Turns a logbook into facts, and facts into an insight — with or without a
/// model. Stateless, like every other calculator in `Supporting/`.
///
/// Main-actor isolated on purpose: fact building walks already-loaded SwiftData
/// models, which belong on the main actor. Only `Sendable` value types cross to
/// the generator, and the generator's own `draft` is `@concurrent`, so the
/// expensive part — inference — never touches this actor.
enum InsightsEngine {

    /// How far back the "biggest month since…" comparison looks. Two years is
    /// enough to be meaningful and short enough that a decade-old month does not
    /// haunt every recap.
    static let comparisonMonths = 24

    /// How many earlier months must exist before "your biggest month since X" is
    /// a claim worth making.
    static let minimumComparisonMonths = 3

    // MARK: Facts

    /// Aggregates one calendar month. Touches SwiftData models, so it stays on
    /// the caller's actor; the output is `Sendable` and is all that crosses.
    static func monthlyFacts(
        sessions: [SurfSession],
        boards: [Gear],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyRecapFacts {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ) ?? referenceDate
        let monthSessions = self.sessions(sessions, inMonth: monthStart, calendar: calendar)

        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)
        let previousCount = previousMonthStart
            .map { self.sessions(sessions, inMonth: $0, calendar: calendar).count } ?? 0

        let summary = StatsCalculator.summarize(sessions: monthSessions, topLimit: 1)
        let time = StatsCalculator.timeInWater(sessions: monthSessions)
        let ratings = monthSessions.map(\.rating).filter { $0 > 0 }

        let topSpotItem = summary.topSpots.first
        let distinctSpots = Set(monthSessions.compactMap { $0.spot?.key }).count

        return MonthlyRecapFacts(
            monthName: monthName(monthStart, calendar: calendar),
            year: calendar.component(.year, from: monthStart),
            sessionCount: monthSessions.count,
            surfDays: Set(monthSessions.map { calendar.startOfDay(for: $0.date) }).count,
            totalMinutes: time.totalMinutes,
            averageRating: ratings.isEmpty
                ? nil
                : Double(ratings.reduce(0, +)) / Double(ratings.count),
            topSpot: topSpotItem.map { InsightsNamedCount(name: $0.name, count: $0.count) },
            distinctSpotCount: distinctSpots,
            topBoard: topBoardFact(boards: boards, monthSessions: monthSessions),
            previousMonthSessionCount: previousCount,
            hasEarlierHistory: sessions.contains { $0.date < monthStart },
            previousBestMonthName: previousBestMonthName(
                sessions: sessions,
                monthStart: monthStart,
                monthCount: monthSessions.count,
                calendar: calendar
            )
        )
    }

    /// Reduces an already-computed `YearInReview` to narrative facts, so the
    /// recap screen's numbers and its paragraph can never drift apart.
    static func yearFacts(review: YearInReview, calendar: Calendar = .current) -> YearNarrativeFacts {
        let dominant = review.waveHeightDistribution.max { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs.height.label > rhs.height.label
        }
        return YearNarrativeFacts(
            year: review.year,
            sessionCount: review.sessionCount,
            surfDays: review.surfDays,
            totalMinutes: review.totalMinutes,
            averageRating: review.averageRating,
            topSpot: review.topSpot.map { InsightsNamedCount(name: $0.name, count: $0.count) },
            topGear: review.topGear.map { InsightsNamedCount(name: $0.name, count: $0.count) },
            bestMonthName: review.bestMonth.map { monthName($0.month, calendar: calendar) },
            bestMonthCount: review.bestMonth?.count ?? 0,
            longestWeekStreak: review.longestWeekStreak,
            dominantWaveBandLabel: dominant?.height.label
        )
    }

    // MARK: Generation

    /// Asks the model for a monthly recap, screens what comes back, and returns
    /// a recap either way.
    ///
    /// Never throws and never returns `nil`: a missing, refusing or rambling
    /// model degrades to the plain figures, which is what the surface renders
    /// when Apple Intelligence is not on the device at all. Failure here is
    /// silent by design — an error banner about an optional caption would be
    /// worse than no caption.
    static func recap(
        facts: MonthlyRecapFacts,
        generator: InsightsGenerating?
    ) async -> MonthlyRecap {
        guard let generator, !facts.isEmpty else {
            return MonthlyRecap(facts: facts, narrative: nil, suggestion: nil)
        }
        do {
            let raw = try await generator.draft(
                prompt: InsightsPromptBuilder.monthlyRecapPrompt(facts: facts),
                instructions: InsightsPromptBuilder.instructions
            )
            guard let clean = InsightsSanitizer.sanitize(raw, allowedNames: facts.allowedNames) else {
                return MonthlyRecap(facts: facts, narrative: nil, suggestion: nil)
            }
            return MonthlyRecap(
                facts: facts,
                narrative: narrative(from: clean),
                suggestion: clean.suggestion.isEmpty ? nil : clean.suggestion
            )
        } catch {
            return MonthlyRecap(facts: facts, narrative: nil, suggestion: nil)
        }
    }

    /// Asks the model for the year-recap paragraph. Same contract as `recap`:
    /// `nil` means "render the plain paragraph instead".
    static func yearNarrative(
        facts: YearNarrativeFacts,
        generator: InsightsGenerating?
    ) async -> String? {
        guard let generator, !facts.isEmpty else { return nil }
        do {
            let raw = try await generator.draft(
                prompt: InsightsPromptBuilder.yearNarrativePrompt(facts: facts),
                instructions: InsightsPromptBuilder.instructions
            )
            guard let clean = InsightsSanitizer.sanitize(raw, allowedNames: facts.allowedNames) else {
                return nil
            }
            return narrative(from: clean)
        } catch {
            return nil
        }
    }

    /// Joins the surviving clauses into one paragraph. Sentence terminators are
    /// added rather than assumed, because a clause is what the model was asked
    /// for.
    static func narrative(from draft: InsightsDraft) -> String? {
        let parts = ([draft.headline] + draft.highlights)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                guard let last = part.last, ".!?".contains(last) else { return part + "." }
                return part
            }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    // MARK: Private

    private static func sessions(
        _ sessions: [SurfSession],
        inMonth monthStart: Date,
        calendar: Calendar
    ) -> [SurfSession] {
        guard let interval = calendar.dateInterval(of: .month, for: monthStart) else { return [] }
        return sessions.filter { interval.contains($0.date) }
    }

    /// The board used most this month, with its conditions highlight when one
    /// cleared `GearInsightsCalculator`'s sample floor. Boards only: a wetsuit's
    /// average rating says more about the season than about the wetsuit.
    private static func topBoardFact(boards: [Gear], monthSessions: [SurfSession]) -> InsightsBoardFact? {
        guard !boards.isEmpty, !monthSessions.isEmpty else { return nil }
        let reports = GearInsightsCalculator.reports(
            for: boards.filter { $0.kind == .board },
            sessions: monthSessions
        )
        guard let report = reports.first else { return nil }
        return InsightsBoardFact(
            name: report.gearName,
            sessionCount: report.sessionCount,
            averageRating: report.highlight?.averageRating ?? report.averageRating,
            conditionsPhrase: report.highlight?.phrase
        )
    }

    /// The best earlier month this one beat, or `nil` when it did not beat them
    /// all. Requires a strict win — tying your own record is not news — and a
    /// record book of at least `minimumComparisonMonths` to beat.
    private static func previousBestMonthName(
        sessions: [SurfSession],
        monthStart: Date,
        monthCount: Int,
        calendar: Calendar
    ) -> String? {
        guard monthCount > 0 else { return nil }

        var counts: [Date: Int] = [:]
        for session in sessions where session.date < monthStart {
            guard let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: session.date)
            ) else { continue }
            guard let months = calendar.dateComponents([.month], from: start, to: monthStart).month,
                  months <= comparisonMonths else { continue }
            counts[start, default: 0] += 1
        }
        // A record needs something to be a record against. Over a single earlier
        // month "your biggest since June" is just "more than last month" wearing
        // a bigger hat, and last month is already its own line.
        guard counts.count >= minimumComparisonMonths else { return nil }

        // Strictly better than every earlier month in the window.
        guard counts.values.allSatisfy({ $0 < monthCount }) else { return nil }
        // Name the closest month that came nearest, so "biggest since X" points
        // at something the surfer remembers rather than at the oldest row.
        let best = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }
        return best.map { monthName($0.key, calendar: calendar) }
    }

    /// Month names are formatted through the *supplied* calendar, not the
    /// ambient one. A month boundary computed in one time zone and printed in
    /// another lands a day out, and "June recap" over July's figures is exactly
    /// the kind of quiet wrongness this feature must never produce.
    static func monthName(_ date: Date, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                calendar: calendar,
                timeZone: calendar.timeZone
            ).month(.wide)
        )
    }
}
