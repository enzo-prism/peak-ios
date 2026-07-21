import Foundation
import XCTest

@testable import Peak

// MARK: - Test doubles

/// Stands in for the on-device model. CI has no Apple Intelligence and never
/// will, so every test in this file drives the pipeline through this seam. No
/// test asserts anything about a real model response.
private struct FakeGenerator: InsightsGenerating {
    let result: Result<InsightsDraft, any Error>

    init(_ draft: InsightsDraft) { self.result = .success(draft) }
    init(error: any Error) { self.result = .failure(error) }

    func draft(prompt: String, instructions: String) async throws -> InsightsDraft {
        try result.get()
    }
}

private struct GenerationBlewUp: Error {}

// MARK: - Fixtures

private enum InsightsFixture {
    static let calendar = TestCalendar.gmt

    /// Mid-July 2026, so "this month" is July and "last month" is June.
    static let july = TestCalendar.makeDate(year: 2026, month: 7, day: 20, hour: 9)

    static func session(
        month: Int,
        day: Int,
        year: Int = 2026,
        spot: Spot? = nil,
        gear: [Gear] = [],
        rating: Int = 0,
        durationMinutes: Int? = nil,
        periodSeconds: Double? = nil,
        waveHeightMeters: Double? = nil
    ) -> SurfSession {
        let made = TestFixture.session(
            date: TestCalendar.makeDate(year: year, month: month, day: day, hour: 7),
            spot: spot,
            gear: gear,
            rating: rating,
            durationMinutes: durationMinutes
        )
        made.swellWavePeriodSeconds = periodSeconds
        made.waveHeightMeters = waveHeightMeters
        return made
    }

    /// A month with a clear story: nine sessions, one dominant spot, one board
    /// that clears the bucket floor, busier than June.
    static func richJuly() -> (sessions: [SurfSession], boards: [Gear]) {
        let ocean = TestFixture.spot(name: "Ocean Beach")
        let linda = TestFixture.spot(name: "Linda Mar")
        let fish = TestFixture.gear(name: "6'2\" Fish", kind: .board)
        let suit = TestFixture.gear(name: "Yulex 4/3", kind: .wetsuit)

        var sessions: [SurfSession] = []
        // Six at Ocean Beach on the fish, all short-period waist-high, all 5s.
        for day in 1...6 {
            sessions.append(session(
                month: 7, day: day, spot: ocean, gear: [fish, suit], rating: 5,
                durationMinutes: 90, periodSeconds: 8, waveHeightMeters: 0.8
            ))
        }
        // Three elsewhere.
        for day in 10...12 {
            sessions.append(session(
                month: 7, day: day, spot: linda, gear: [suit], rating: 3, durationMinutes: 60
            ))
        }
        // June: four sessions, so July is "busier".
        for day in 1...4 {
            sessions.append(session(month: 6, day: day, spot: ocean, rating: 4, durationMinutes: 60))
        }
        return (sessions, [fish, suit])
    }
}

// MARK: - Aggregation

final class InsightsEngineFactsTests: XCTestCase {

    func testMonthlyFactsCoverOnlyTheReferenceMonth() {
        let (sessions, boards) = InsightsFixture.richJuly()

        let facts = InsightsEngine.monthlyFacts(
            sessions: sessions,
            boards: boards,
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )

        XCTAssertEqual(facts.monthName, "July")
        XCTAssertEqual(facts.year, 2026)
        XCTAssertEqual(facts.sessionCount, 9)
        XCTAssertEqual(facts.surfDays, 9)
        XCTAssertEqual(facts.totalMinutes, 6 * 90 + 3 * 60)
        XCTAssertEqual(facts.previousMonthSessionCount, 4)
        XCTAssertTrue(facts.hasEarlierHistory)
    }

    func testMonthlyFactsNameTheDominantSpotAndBoard() {
        let (sessions, boards) = InsightsFixture.richJuly()

        let facts = InsightsEngine.monthlyFacts(
            sessions: sessions,
            boards: boards,
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )

        XCTAssertEqual(facts.topSpot?.name, "Ocean Beach")
        XCTAssertEqual(facts.topSpot?.count, 6)
        XCTAssertEqual(facts.distinctSpotCount, 2)
        XCTAssertEqual(facts.spotSpread, .dominant)
        // Wetsuits are excluded: a wetsuit's average rating describes the season.
        XCTAssertEqual(facts.topBoard?.name, "6'2\" Fish")
        XCTAssertEqual(facts.topBoard?.conditionsPhrase, "short-period waist-high")
        XCTAssertEqual(facts.topBoard?.averageRating, 5.0)
    }

    func testTrendNeedsMoreThanOneSessionOfDifference() {
        let base = (1...5).map { InsightsFixture.session(month: 6, day: $0) }

        func trend(julyCount: Int) -> InsightsActivityTrend {
            let july = (1...max(julyCount, 1)).prefix(julyCount)
                .map { InsightsFixture.session(month: 7, day: $0) }
            return InsightsEngine.monthlyFacts(
                sessions: base + july,
                boards: [],
                referenceDate: InsightsFixture.july,
                calendar: InsightsFixture.calendar
            ).activityTrend
        }

        XCTAssertEqual(trend(julyCount: 9), .busier)
        XCTAssertEqual(trend(julyCount: 6), .steady, "One session more is noise, not a trend")
        XCTAssertEqual(trend(julyCount: 4), .steady)
        XCTAssertEqual(trend(julyCount: 2), .quieter)
    }

    func testFirstEverMonthHasNothingToCompareWith() {
        let july = (1...3).map { InsightsFixture.session(month: 7, day: $0) }

        let facts = InsightsEngine.monthlyFacts(
            sessions: july,
            boards: [],
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )

        XCTAssertEqual(facts.activityTrend, .firstMonth)
        XCTAssertNil(facts.previousBestMonthName)
        XCTAssertFalse(facts.hasEarlierHistory)
    }

    func testBiggestMonthSinceRequiresBeatingEveryEarlierMonth() {
        let march = (1...7).map { InsightsFixture.session(month: 3, day: $0) }
        let may = (1...2).map { InsightsFixture.session(month: 5, day: $0) }
        let june = (1...4).map { InsightsFixture.session(month: 6, day: $0) }

        func bestSince(julyCount: Int) -> String? {
            let july = (1...julyCount).map { InsightsFixture.session(month: 7, day: $0) }
            return InsightsEngine.monthlyFacts(
                sessions: march + may + june + july,
                boards: [],
                referenceDate: InsightsFixture.july,
                calendar: InsightsFixture.calendar
            ).previousBestMonthName
        }

        XCTAssertEqual(bestSince(julyCount: 8), "March", "Beat every earlier month")
        XCTAssertNil(bestSince(julyCount: 7), "Tying your own record is not news")
        XCTAssertNil(bestSince(julyCount: 5))
    }

    /// One earlier month is not a record book. "Your biggest since June" when
    /// June is simply last month says nothing the next line does not already say.
    func testBiggestMonthSinceNeedsARecordBookToBeat() {
        let june = (1...4).map { InsightsFixture.session(month: 6, day: $0) }
        let july = (1...9).map { InsightsFixture.session(month: 7, day: $0) }

        let facts = InsightsEngine.monthlyFacts(
            sessions: june + july,
            boards: [],
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )

        XCTAssertNil(facts.previousBestMonthName)
        XCTAssertTrue(facts.plainHighlights.contains("4 sessions the month before"))
    }

    func testEmptyMonthProducesEmptyFacts() {
        let facts = InsightsEngine.monthlyFacts(
            sessions: [InsightsFixture.session(month: 3, day: 1)],
            boards: [],
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )

        XCTAssertTrue(facts.isEmpty)
        XCTAssertTrue(facts.plainHighlights.isEmpty)
        XCTAssertEqual(facts.spotSpread, .none)
    }

    func testRatingToneBuckets() {
        func tone(_ average: Double?) -> InsightsRatingTone {
            MonthlyRecapFacts(
                monthName: "July", year: 2026, sessionCount: 4, surfDays: 4,
                totalMinutes: 240, averageRating: average, topSpot: nil,
                distinctSpotCount: 0, topBoard: nil, previousMonthSessionCount: 0,
                hasEarlierHistory: false, previousBestMonthName: nil
            ).ratingTone
        }

        XCTAssertEqual(tone(nil), .unrated)
        XCTAssertEqual(tone(1.5), .poor)
        XCTAssertEqual(tone(3.0), .mixed)
        XCTAssertEqual(tone(3.8), .good)
        XCTAssertEqual(tone(4.6), .excellent)
    }

    func testYearFactsMirrorTheRecapTheUserAlreadySees() {
        let ocean = TestFixture.spot(name: "Ocean Beach")
        let fish = TestFixture.gear(name: "6'2\" Fish", kind: .board)
        var sessions = (1...5).map {
            InsightsFixture.session(
                month: 8, day: $0, spot: ocean, gear: [fish], rating: 4,
                durationMinutes: 60, waveHeightMeters: 0.8
            )
        }
        sessions.append(InsightsFixture.session(month: 2, day: 1, spot: ocean, rating: 2))

        let review = YearInReviewCalculator.summary(
            sessions: sessions,
            year: 2026,
            calendar: InsightsFixture.calendar
        )
        let facts = InsightsEngine.yearFacts(review: review, calendar: InsightsFixture.calendar)

        XCTAssertEqual(facts.year, review.year)
        XCTAssertEqual(facts.sessionCount, review.sessionCount)
        XCTAssertEqual(facts.totalMinutes, review.totalMinutes)
        XCTAssertEqual(facts.averageRating, review.averageRating)
        XCTAssertEqual(facts.topSpot?.name, "Ocean Beach")
        XCTAssertEqual(facts.topGear?.name, "6'2\" Fish")
        XCTAssertEqual(facts.bestMonthName, "August")
        XCTAssertEqual(facts.bestMonthCount, 5)
        XCTAssertEqual(facts.dominantWaveBandLabel, WaveHeight.waistHigh.label)
    }
}

// MARK: - Prompt building

final class InsightsPromptBuilderTests: XCTestCase {

    private func richFacts() -> MonthlyRecapFacts {
        let (sessions, boards) = InsightsFixture.richJuly()
        return InsightsEngine.monthlyFacts(
            sessions: sessions,
            boards: boards,
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )
    }

    /// The central anti-hallucination invariant: the model is never shown a
    /// figure, so it cannot copy one — correctly or otherwise. The only digits
    /// permitted anywhere in a prompt are those inside a name the surfer typed.
    func testMonthlyPromptContainsNoNumeralsOutsideUserSuppliedNames() {
        let facts = richFacts()
        let prompt = InsightsPromptBuilder.monthlyRecapPrompt(facts: facts)

        XCTAssertTrue(prompt.contains("6'2\" Fish"), "Precondition: the fixture board name has digits in it")

        var masked = prompt
        for name in facts.allowedNames {
            masked = masked.replacingOccurrences(of: name, with: " ")
        }
        XCTAssertNil(
            masked.rangeOfCharacter(from: .decimalDigits),
            "A numeral reached the prompt from somewhere other than a user-typed name:\n\(masked)"
        )
    }

    func testYearPromptContainsNoNumeralsOutsideUserSuppliedNames() {
        let ocean = TestFixture.spot(name: "Ocean Beach")
        let fish = TestFixture.gear(name: "6'2\" Fish", kind: .board)
        let sessions = (1...20).map {
            InsightsFixture.session(
                month: 8, day: ($0 % 28) + 1, spot: ocean, gear: [fish],
                rating: 5, durationMinutes: 75, waveHeightMeters: 1.2
            )
        }
        let review = YearInReviewCalculator.summary(
            sessions: sessions, year: 2026, calendar: InsightsFixture.calendar
        )
        let facts = InsightsEngine.yearFacts(review: review, calendar: InsightsFixture.calendar)
        var masked = InsightsPromptBuilder.yearNarrativePrompt(facts: facts)
        for name in facts.allowedNames {
            masked = masked.replacingOccurrences(of: name, with: " ")
        }

        XCTAssertNil(masked.rangeOfCharacter(from: .decimalDigits), masked)
        XCTAssertFalse(masked.contains("2026"), "The year is four digits and must not be handed to the model")
    }

    /// Raw session rows must never reach the model: the window is ~4k tokens for
    /// input *and* output, and a logbook has no upper bound. If someone ever
    /// starts appending per-session detail, the prompt starts growing and this
    /// fails.
    func testPromptSizeIsBoundedAndNamesOnlyTheTopSpot() {
        // 800 sessions across 40 differently named breaks. If any per-session
        // detail were leaking into the prompt this would be enormous, and the
        // also-ran spot names would be in it.
        let spots = (0..<40).map { TestFixture.spot(name: "Break \($0) Point") }
        let ocean = TestFixture.spot(name: "Ocean Beach")
        var sessions = (0..<800).map { index in
            InsightsFixture.session(
                month: 7, day: (index % 28) + 1, spot: spots[index % spots.count],
                rating: 4, durationMinutes: 60
            )
        }
        // Make one spot the clear leader so there is a name to mention at all.
        sessions += (0..<400).map { index in
            InsightsFixture.session(
                month: 7, day: (index % 28) + 1, spot: ocean, rating: 5, durationMinutes: 60
            )
        }

        let facts = InsightsEngine.monthlyFacts(
            sessions: sessions,
            boards: [],
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )
        let prompt = InsightsPromptBuilder.monthlyRecapPrompt(facts: facts)

        XCTAssertEqual(facts.topSpot?.name, "Ocean Beach")
        XCTAssertLessThan(
            InsightsPromptBuilder.approximateTokenCount(prompt), 400,
            "Prompt must stay a small fraction of the shared ~4k input+output window"
        )
        for spot in spots {
            XCTAssertFalse(
                prompt.contains(spot.name),
                "A spot the surfer barely used reached the model: \(spot.name)"
            )
        }
    }

    func testInstructionsStateTheRulesThatKeepOutputHonest() {
        let instructions = InsightsPromptBuilder.instructions.lowercased()

        XCTAssertTrue(instructions.contains("never write a digit"))
        XCTAssertTrue(instructions.contains("never name a place"))
        XCTAssertTrue(instructions.contains("never invent"))
        XCTAssertLessThan(InsightsPromptBuilder.approximateTokenCount(instructions), 300)
    }

    func testPromptDescribesTheMonthQualitatively() {
        let prompt = InsightsPromptBuilder.monthlyRecapPrompt(facts: richFacts())

        XCTAssertTrue(prompt.contains("July"))
        XCTAssertTrue(prompt.contains("busier"))
        XCTAssertTrue(prompt.contains("excellent"))
        XCTAssertTrue(prompt.contains("mostly at Ocean Beach"))
        XCTAssertTrue(prompt.contains("short-period waist-high"))
    }

    func testPromptForAnEmptySpotSaysSoRatherThanInventingOne() {
        let facts = MonthlyRecapFacts(
            monthName: "July", year: 2026, sessionCount: 2, surfDays: 2,
            totalMinutes: 120, averageRating: nil, topSpot: nil,
            distinctSpotCount: 0, topBoard: nil, previousMonthSessionCount: 0,
            hasEarlierHistory: false, previousBestMonthName: nil
        )
        let prompt = InsightsPromptBuilder.monthlyRecapPrompt(facts: facts)

        XCTAssertTrue(prompt.contains("no break was recorded"))
        XCTAssertTrue(prompt.contains("they did not rate them"))
    }
}

// MARK: - Screening

final class InsightsSanitizerTests: XCTestCase {

    private let names = ["July", "Ocean Beach", "6'2\" Fish"]
    private func draft(_ headline: String, highlights: [String] = [], suggestion: String = "") -> InsightsDraft {
        InsightsDraft(headline: headline, highlights: highlights, suggestion: suggestion)
    }

    func testCleanProseSurvives() {
        let result = InsightsSanitizer.sanitize(
            draft(
                "A strong month in the water",
                highlights: ["You kept going back to the same stretch of coast."],
                suggestion: "Keep rating sessions and the picture sharpens."
            ),
            allowedNames: names
        )

        XCTAssertEqual(result?.headline, "A strong month in the water")
        XCTAssertEqual(result?.highlights.count, 1)
        XCTAssertFalse(result?.suggestion.isEmpty ?? true)
    }

    func testDigitsAreRejected() {
        XCTAssertNil(
            InsightsSanitizer.sanitize(draft("You surfed 11 times this month"), allowedNames: names),
            "A generated count must never reach the screen"
        )
    }

    func testSpelledOutNumbersAreRejected() {
        for phrase in [
            "You surfed eleven times",
            "Your best of the three breaks",
            "Twice the sessions of last month",
            "Your first month back",
            "Half your sessions were early"
        ] {
            XCTAssertNil(
                InsightsSanitizer.sanitize(draft(phrase), allowedNames: names),
                "Spelled-out figure slipped through: \(phrase)"
            )
        }
    }

    func testStarsAndPercentagesAreRejected() {
        XCTAssertNil(InsightsSanitizer.sanitize(draft("You averaged ★ ratings"), allowedNames: names))
        XCTAssertNil(InsightsSanitizer.sanitize(draft("Up a good % on last month"), allowedNames: names))
    }

    /// The exact failure this design exists to prevent: a plausible-sounding
    /// break the surfer has never logged.
    func testInventedPlaceNamesAreRejected() {
        XCTAssertNil(
            InsightsSanitizer.sanitize(draft("Your best sessions were at Pipeline"), allowedNames: names),
            "A break the surfer never logged must never appear"
        )

        let result = InsightsSanitizer.sanitize(
            draft("A strong month", suggestion: "Try Mavericks next."),
            allowedNames: names
        )
        XCTAssertEqual(result?.headline, "A strong month")
        XCTAssertEqual(result?.suggestion, "", "The invented break drops the suggestion, not the card")
    }

    func testSuppliedNamesAreAllowedIncludingOnesWithDigits() {
        let result = InsightsSanitizer.sanitize(
            draft(
                "Ocean Beach carried the month",
                highlights: ["Your 6'2\" Fish did the heavy lifting."],
                suggestion: "Give July's rhythm another go."
            ),
            allowedNames: names
        )

        XCTAssertEqual(result?.headline, "Ocean Beach carried the month")
        XCTAssertEqual(result?.highlights, ["Your 6'2\" Fish did the heavy lifting."])
        XCTAssertEqual(result?.suggestion, "Give July's rhythm another go.")
    }

    func testSentenceInitialCapitalsAreNotTreatedAsNames() {
        XCTAssertNotNil(
            InsightsSanitizer.sanitize(
                draft("Consistent work. Steady conditions rewarded you."),
                allowedNames: names
            )
        )
    }

    func testAHeadlineThatFailsScreeningDropsTheWholeDraft() {
        XCTAssertNil(
            InsightsSanitizer.sanitize(
                draft("You logged 9 sessions", highlights: ["Perfectly fine clause."]),
                allowedNames: names
            ),
            "Without a headline there is nothing worth layering over the figures"
        )
    }

    func testOverlongFieldsAreDroppedRatherThanTruncated() {
        let rambling = String(repeating: "words and more words ", count: 20)
        XCTAssertNil(InsightsSanitizer.sanitize(draft(rambling), allowedNames: names))

        let result = InsightsSanitizer.sanitize(
            draft("A fine month", highlights: [rambling, "Short and clean."]),
            allowedNames: names
        )
        XCTAssertEqual(result?.highlights, ["Short and clean."])
    }

    func testHighlightsAreCappedAtThree() {
        let result = InsightsSanitizer.sanitize(
            draft(
                "A fine month",
                highlights: ["Alpha clause.", "Bravo clause.", "Charlie clause.", "Delta clause."]
            ),
            allowedNames: names + ["Alpha", "Bravo", "Charlie", "Delta"]
        )

        XCTAssertEqual(result?.highlights.count, InsightsSanitizer.maximumHighlights)
        XCTAssertEqual(result?.highlights.last, "Charlie clause.")
    }

    func testLeadingBulletsAndQuotesAreStripped() {
        let result = InsightsSanitizer.sanitize(
            draft("\"A quiet, honest month\"", highlights: ["- You still showed up."]),
            allowedNames: names
        )

        XCTAssertEqual(result?.headline, "A quiet, honest month")
        XCTAssertEqual(result?.highlights, ["You still showed up."])
    }
}

// MARK: - Truncation

final class InsightsTruncationTests: XCTestCase {

    func testUnfinishedSuggestionIsDroppedWhenTruncated() {
        let repaired = InsightsSanitizer.repair(
            InsightsDraft(
                headline: "A strong month",
                highlights: ["You showed up often."],
                suggestion: "Next month try to keep the same rhy",
                wasTruncated: true
            )
        )

        XCTAssertEqual(repaired.suggestion, "")
        XCTAssertEqual(repaired.highlights, ["You showed up often."])
        XCTAssertEqual(repaired.headline, "A strong month")
    }

    func testUnfinishedFinalHighlightIsDroppedWhenTruncated() {
        let repaired = InsightsSanitizer.repair(
            InsightsDraft(
                headline: "A strong month",
                highlights: ["You showed up often.", "The board you picked kept"],
                suggestion: "",
                wasTruncated: true
            )
        )

        XCTAssertEqual(repaired.highlights, ["You showed up often."])
    }

    func testAHeadlineSeveredMidThoughtLeavesNothingToShow() {
        let draft = InsightsDraft(headline: "A month that", highlights: [], suggestion: "", wasTruncated: true)

        XCTAssertEqual(InsightsSanitizer.repair(draft).headline, "")
        XCTAssertNil(InsightsSanitizer.sanitize(draft, allowedNames: ["July"]))
    }

    func testUntruncatedDraftsAreNeverRepaired() {
        let draft = InsightsDraft(
            headline: "A strong month",
            highlights: ["A clause with no terminator"],
            suggestion: "Another one",
            wasTruncated: false
        )

        XCTAssertEqual(InsightsSanitizer.repair(draft), draft)
    }

    func testTruncatedDraftStillYieldsItsFinishedPrefix() async {
        let facts = MonthlyRecapFacts(
            monthName: "July", year: 2026, sessionCount: 9, surfDays: 8,
            totalMinutes: 680, averageRating: 4.4,
            topSpot: InsightsNamedCount(name: "Ocean Beach", count: 6),
            distinctSpotCount: 2, topBoard: nil, previousMonthSessionCount: 4,
            hasEarlierHistory: true, previousBestMonthName: nil
        )
        let recap = await InsightsEngine.recap(
            facts: facts,
            generator: FakeGenerator(
                InsightsDraft(
                    headline: "A strong month at Ocean Beach.",
                    highlights: ["You kept going back.", "The swell held for a while and th"],
                    suggestion: "Keep the same rou",
                    wasTruncated: true
                )
            )
        )

        XCTAssertEqual(recap.narrative, "A strong month at Ocean Beach. You kept going back.")
        XCTAssertNil(recap.suggestion)
        XCTAssertEqual(recap.facts.plainFigures, "9 sessions · 11h 20m · 4.4★ avg", "Figures are untouched by truncation")
    }
}

// MARK: - Unavailable model

final class InsightsUnavailableModelTests: XCTestCase {

    private let facts = MonthlyRecapFacts(
        monthName: "July", year: 2026, sessionCount: 9, surfDays: 8,
        totalMinutes: 680, averageRating: 4.2,
        topSpot: InsightsNamedCount(name: "Ocean Beach", count: 6),
        distinctSpotCount: 2,
        topBoard: InsightsBoardFact(
            name: "6'2\" Fish", sessionCount: 6, averageRating: 4.6,
            conditionsPhrase: "short-period waist-high"
        ),
        previousMonthSessionCount: 4, hasEarlierHistory: true,
        previousBestMonthName: "March"
    )

    func testNoGeneratorStillProducesACorrectRecap() async {
        let recap = await InsightsEngine.recap(facts: facts, generator: nil)

        XCTAssertNil(recap.narrative)
        XCTAssertNil(recap.suggestion)
        XCTAssertFalse(recap.isModelWritten)
        XCTAssertEqual(recap.facts, facts)
    }

    func testAThrowingGeneratorDegradesSilently() async {
        let recap = await InsightsEngine.recap(
            facts: facts,
            generator: FakeGenerator(error: GenerationBlewUp())
        )

        XCTAssertNil(recap.narrative)
        XCTAssertEqual(recap.facts.plainFigures, "9 sessions · 11h 20m · 4.2★ avg")
    }

    func testAnUnavailableModelErrorDegradesSilently() async {
        let recap = await InsightsEngine.recap(
            facts: facts,
            generator: FakeGenerator(error: InsightsUnavailableError(availability: .deviceNotEligible))
        )

        XCTAssertNil(recap.narrative)
    }

    func testAHallucinatingGeneratorIsIndistinguishableFromNoModel() async {
        let honest = await InsightsEngine.recap(facts: facts, generator: nil)
        let liar = await InsightsEngine.recap(
            facts: facts,
            generator: FakeGenerator(
                InsightsDraft(headline: "You surfed 14 times at Pipeline", highlights: ["Best since 2019."])
            )
        )

        XCTAssertEqual(liar, honest, "Unusable output must fall all the way back to the figures")
    }

    func testAnEmptyMonthNeverAsksTheModel() async {
        let empty = MonthlyRecapFacts(
            monthName: "July", year: 2026, sessionCount: 0, surfDays: 0,
            totalMinutes: 0, averageRating: nil, topSpot: nil, distinctSpotCount: 0,
            topBoard: nil, previousMonthSessionCount: 0, hasEarlierHistory: false,
            previousBestMonthName: nil
        )
        let recap = await InsightsEngine.recap(
            facts: empty,
            generator: FakeGenerator(InsightsDraft(headline: "What a month"))
        )

        XCTAssertNil(recap.narrative, "There is nothing to narrate and nothing to spend a model on")
    }

    func testYearNarrativeDegradesToNilWithoutAGenerator() async {
        let facts = YearNarrativeFacts(
            year: 2026, sessionCount: 40, surfDays: 33, totalMinutes: 2400,
            averageRating: 3.9, topSpot: InsightsNamedCount(name: "Ocean Beach", count: 20),
            topGear: nil, bestMonthName: "August", bestMonthCount: 9,
            longestWeekStreak: 6, dominantWaveBandLabel: "Waist high"
        )

        let narrative = await InsightsEngine.yearNarrative(facts: facts, generator: nil)
        XCTAssertNil(narrative)
    }

    func testEveryUnavailabilityReasonIsTreatedAsUnavailable() {
        for reason: InsightsAvailability in [
            .unsupportedOS, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady
        ] {
            XCTAssertFalse(reason.isAvailable, "\(reason) must hide the feature entirely")
        }
        XCTAssertTrue(InsightsAvailability.available.isAvailable)
    }

    /// CI runs on a simulator, which has no Apple Intelligence. If this ever
    /// starts reporting `.available` the suite must still not depend on a model,
    /// so this only asserts the gate answers at all — never what it answers.
    func testAvailabilityAndGeneratorAgree() {
        let availability = InsightsModel.availability
        if !availability.isAvailable {
            XCTAssertNil(
                InsightsModel.makeGenerator(),
                "An unavailable model must never hand back a generator"
            )
        }
    }
}

// MARK: - Fallback rendering

final class InsightsFallbackRenderingTests: XCTestCase {

    private func richFacts() -> MonthlyRecapFacts {
        let (sessions, boards) = InsightsFixture.richJuly()
        return InsightsEngine.monthlyFacts(
            sessions: sessions,
            boards: boards,
            referenceDate: InsightsFixture.july,
            calendar: InsightsFixture.calendar
        )
    }

    func testPlainFiguresReadTheSameWithOrWithoutAModel() {
        let facts = richFacts()

        XCTAssertEqual(facts.title, "July recap")
        XCTAssertEqual(facts.plainFigures, "9 sessions · 12h · 4.3★ avg")
    }

    func testPlainFiguresOmitWhatWasNeverLogged() {
        let facts = MonthlyRecapFacts(
            monthName: "July", year: 2026, sessionCount: 1, surfDays: 1,
            totalMinutes: 0, averageRating: nil, topSpot: nil, distinctSpotCount: 0,
            topBoard: nil, previousMonthSessionCount: 0, hasEarlierHistory: false,
            previousBestMonthName: nil
        )

        XCTAssertEqual(facts.plainFigures, "1 session", "No zero-hour or dash filler")
    }

    func testPlainHighlightsAreAllAggregates() {
        let facts = richFacts()
        let highlights = facts.plainHighlights

        XCTAssertTrue(highlights.contains("Most days at Ocean Beach (6)"))
        XCTAssertTrue(highlights.contains("6'2\" Fish averaged 5.0★ in short-period waist-high"))
        XCTAssertTrue(highlights.contains("4 sessions the month before"))
    }

    func testAFirstEverMonthDoesNotCompareItselfWithNothing() {
        let july = (1...3).map { InsightsFixture.session(month: 7, day: $0) }
        let facts = InsightsEngine.monthlyFacts(
            sessions: july, boards: [],
            referenceDate: InsightsFixture.july, calendar: InsightsFixture.calendar
        )

        XCTAssertFalse(
            facts.plainHighlights.contains { $0.contains("the month before") },
            "There is no month before"
        )
    }

    func testAccessibilitySummaryLeadsWithTheFigures() {
        let summary = richFacts().accessibilitySummary

        XCTAssertTrue(summary.hasPrefix("9 sessions · 12h · 4.3★ avg"))
        XCTAssertTrue(summary.contains("Ocean Beach"))
    }

    func testYearPlainNarrativeCarriesEveryFigureTheModelWouldNotBeAllowedTo() {
        let facts = YearNarrativeFacts(
            year: 2026, sessionCount: 84, surfDays: 71, totalMinutes: 7_560,
            averageRating: 3.9,
            topSpot: InsightsNamedCount(name: "Ocean Beach", count: 31),
            topGear: InsightsNamedCount(name: "6'2\" Fish", count: 40),
            bestMonthName: "August", bestMonthCount: 12,
            longestWeekStreak: 9, dominantWaveBandLabel: "Waist high"
        )
        let narrative = facts.plainNarrative

        XCTAssertTrue(narrative.contains("84 sessions"))
        XCTAssertTrue(narrative.contains("71 days"))
        XCTAssertTrue(narrative.contains("126h"))
        XCTAssertTrue(narrative.contains("Most days at Ocean Beach (31)."))
        XCTAssertTrue(narrative.contains("August was your busiest month with 12 sessions."))
        XCTAssertTrue(narrative.contains("6'2\" Fish"))
        XCTAssertTrue(narrative.contains("waist high"))
        XCTAssertTrue(narrative.contains("3.9★"))
    }

    func testYearPlainNarrativeStaysHonestOnAnEmptyYear() {
        let facts = YearNarrativeFacts(
            year: 2026, sessionCount: 0, surfDays: 0, totalMinutes: 0,
            averageRating: nil, topSpot: nil, topGear: nil, bestMonthName: nil,
            bestMonthCount: 0, longestWeekStreak: 0, dominantWaveBandLabel: nil
        )

        XCTAssertEqual(facts.plainNarrative, "Nothing logged this year yet.")
    }

    func testYearPlainNarrativeSingularisesASingleSession() {
        let facts = YearNarrativeFacts(
            year: 2026, sessionCount: 1, surfDays: 1, totalMinutes: 60,
            averageRating: nil, topSpot: nil, topGear: nil, bestMonthName: nil,
            bestMonthCount: 0, longestWeekStreak: 0, dominantWaveBandLabel: nil
        )

        XCTAssertEqual(facts.plainNarrative, "You logged 1 session across 1 day, 1h in the water.")
    }

    /// The model contributes phrasing on top of the plain rendering; it never
    /// replaces a figure.
    func testModelProseIsAdditiveNotSubstitutive() async {
        let facts = richFacts()
        let plain = await InsightsEngine.recap(facts: facts, generator: nil)
        let written = await InsightsEngine.recap(
            facts: facts,
            generator: FakeGenerator(
                InsightsDraft(
                    headline: "A month that finally clicked",
                    highlights: ["You kept going back to what worked."],
                    suggestion: "Ride the same rhythm while it lasts."
                )
            )
        )

        XCTAssertEqual(written.facts.plainFigures, plain.facts.plainFigures)
        XCTAssertEqual(written.facts.plainHighlights, plain.facts.plainHighlights)
        XCTAssertEqual(
            written.narrative,
            "A month that finally clicked. You kept going back to what worked."
        )
        XCTAssertTrue(written.isModelWritten)
        XCTAssertFalse(plain.isModelWritten)
    }
}
