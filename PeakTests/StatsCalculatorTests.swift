import XCTest

@testable import Peak

final class StatsCalculatorTests: XCTestCase {
    func testSummaryCalculatesAverageAndTopItems() {
        let spotA = TestFixture.spot(name: "Trestles")
        let spotB = TestFixture.spot(name: "Ocean Beach")
        let gear = TestFixture.gear(name: "6'2\" Fish")
        let buddy = TestFixture.buddy(name: "Kai")

        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: spotA, gear: [gear], buddies: [buddy], rating: 5),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2), spot: spotA, gear: [], buddies: [], rating: 0),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 3), spot: spotB, gear: [], buddies: [], rating: 3)
        ]

        let summary = StatsCalculator.summarize(sessions: sessions, topLimit: 3)

        XCTAssertEqual(summary.totalSessions, 3)
        XCTAssertEqual(summary.averageRating, 4.0)
        XCTAssertEqual(summary.topSpots.first?.name, "Trestles")
    }

    func testTopItemsSortByNameOnTies() {
        let gearA = TestFixture.gear(name: "Alpha", kind: .board)
        let gearB = TestFixture.gear(name: "Beta", kind: .board)

        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 5), spot: nil, gear: [gearB]),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 6), spot: nil, gear: [gearA])
        ]

        let summary = StatsCalculator.summarize(sessions: sessions, topLimit: 2)

        XCTAssertEqual(summary.topGear.map(\.name), ["Alpha", "Beta"])
    }
}

/// Anniversary windowing. The interesting cases are the ones a naive
/// "same month and day" match gets wrong: year boundaries and Feb 29.
final class OnThisDayProviderTests: XCTestCase {
    private let calendar = TestCalendar.gmt

    private func session(year: Int, month: Int, day: Int, rating: Int = 0) -> SurfSession {
        TestFixture.session(
            date: TestCalendar.makeDate(year: year, month: month, day: day, hour: 7),
            rating: rating
        )
    }

    func testMemoriesMatchPriorYearsInsideTheWindow() {
        let inWindowExact = session(year: 2025, month: 7, day: 20)
        let inWindowEdge = session(year: 2025, month: 7, day: 17)
        let outsideWindow = session(year: 2025, month: 7, day: 16)
        let twoYearsAgo = session(year: 2024, month: 7, day: 22)
        let thisYear = session(year: 2026, month: 7, day: 19)

        let memories = OnThisDayProvider.memories(
            sessions: [inWindowExact, inWindowEdge, outsideWindow, twoYearsAgo, thisYear],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 7, day: 20, hour: 12),
            calendar: calendar,
            limit: 10
        )

        XCTAssertEqual(memories.count, 3)
        XCTAssertEqual(memories.map(\.yearsAgo), [1, 1, 2])
        XCTAssertTrue(memories.contains { $0.session === inWindowExact && $0.isExactAnniversary })
        XCTAssertTrue(memories.contains { $0.session === inWindowEdge && !$0.isExactAnniversary })
        XCTAssertFalse(memories.contains { $0.session === outsideWindow })
        XCTAssertFalse(memories.contains { $0.session === thisYear })
    }

    func testWindowSpansTheYearBoundary() {
        let lateDecember = session(year: 2024, month: 12, day: 30)
        let earlyJanuary = session(year: 2025, month: 1, day: 2)

        let memories = OnThisDayProvider.memories(
            sessions: [lateDecember, earlyJanuary],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 1, day: 1, hour: 12),
            calendar: calendar,
            limit: 10
        )

        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(Set(memories.map(\.yearsAgo)), [1])
    }

    func testLeapDaySessionSurfacesInACommonYear() {
        let leapDay = session(year: 2024, month: 2, day: 29)

        let memories = OnThisDayProvider.memories(
            sessions: [leapDay],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 2, day: 28, hour: 12),
            calendar: calendar,
            limit: 10
        )

        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.yearsAgo, 2)
        XCTAssertEqual(memories.first?.isExactAnniversary, false)
    }

    func testEmptyAndCurrentYearOnlyHistoriesProduceNothing() {
        XCTAssertTrue(OnThisDayProvider.memories(
            sessions: [],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 7, day: 20),
            calendar: calendar
        ).isEmpty)

        XCTAssertTrue(OnThisDayProvider.memories(
            sessions: [session(year: 2026, month: 7, day: 19), session(year: 2026, month: 7, day: 21)],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 7, day: 20),
            calendar: calendar
        ).isEmpty)
    }

    func testMemoriesRankBestSessionFirstWithinTheSameYear() {
        let good = session(year: 2025, month: 7, day: 19, rating: 5)
        let mediocre = session(year: 2025, month: 7, day: 21, rating: 2)

        let memories = OnThisDayProvider.memories(
            sessions: [mediocre, good],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 7, day: 20, hour: 12),
            calendar: calendar,
            limit: 10
        )

        XCTAssertEqual(memories.map { $0.session.rating }, [5, 2])
        XCTAssertEqual(memories.first?.label, "1 year ago this week")
    }

    func testLimitTrimsTheResult() {
        let sessions = (17...23).map { session(year: 2025, month: 7, day: $0, rating: 3) }

        let memories = OnThisDayProvider.memories(
            sessions: sessions,
            referenceDate: TestCalendar.makeDate(year: 2026, month: 7, day: 20, hour: 12),
            calendar: calendar,
            limit: 2
        )

        XCTAssertEqual(memories.count, 2)
    }
}

/// Recap aggregates. A one-session library has to produce a sane recap — that
/// is the case a year-in-review screen most often ships broken.
final class YearInReviewCalculatorTests: XCTestCase {
    private let calendar = TestCalendar.gmt

    private func richLibrary() -> [SurfSession] {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")
        let fish = TestFixture.gear(name: "Fish")

        let a = TestFixture.session(
            date: TestCalendar.makeDate(year: 2025, month: 3, day: 2, hour: 7),
            spot: trestles,
            gear: [fish],
            rating: 5,
            durationMinutes: 90
        )
        a.waveHeight = .shoulderHigh

        let b = TestFixture.session(
            date: TestCalendar.makeDate(year: 2025, month: 3, day: 9, hour: 7),
            spot: trestles,
            gear: [fish],
            rating: 3,
            durationMinutes: 60
        )
        b.waveHeight = .waistHigh

        let c = TestFixture.session(
            date: TestCalendar.makeDate(year: 2025, month: 3, day: 16, hour: 7),
            spot: oceanBeach,
            gear: [fish],
            rating: 4,
            durationMinutes: 120
        )
        c.waveHeightMeters = 1.8

        let d = TestFixture.session(
            date: TestCalendar.makeDate(year: 2025, month: 8, day: 4, hour: 7),
            spot: trestles,
            rating: 0
        )

        let previousYear = TestFixture.session(
            date: TestCalendar.makeDate(year: 2024, month: 5, day: 5, hour: 7),
            spot: trestles,
            rating: 5,
            durationMinutes: 300
        )

        return [a, b, c, d, previousYear]
    }

    func testRichLibraryAggregates() {
        let review = YearInReviewCalculator.summary(
            sessions: richLibrary(),
            year: 2025,
            calendar: calendar
        )

        XCTAssertEqual(review.sessionCount, 4)
        XCTAssertEqual(review.surfDays, 4)
        XCTAssertEqual(review.totalMinutes, 270)
        XCTAssertEqual(review.hoursInWater, 4.5, accuracy: 0.0001)
        XCTAssertEqual(review.averageRating ?? 0, 4.0, accuracy: 0.0001)
        XCTAssertEqual(review.topSpot, YearInReviewLeader(name: "Trestles", count: 3))
        XCTAssertEqual(review.topGear, YearInReviewLeader(name: "Fish", count: 3))
        XCTAssertEqual(review.bestMonth?.count, 3)
        XCTAssertEqual(
            review.bestMonth?.month,
            TestCalendar.makeDate(year: 2025, month: 3, day: 1)
        )
        XCTAssertEqual(review.longestWeekStreak, 3)
        // Measured-only sessions still land in the distribution (1.8 m == overhead).
        XCTAssertEqual(
            review.waveHeightDistribution.map(\.height),
            [.waistHigh, .shoulderHigh, .overhead]
        )
        XCTAssertEqual(review.waveHeightDistribution.map(\.count), [1, 1, 1])
        XCTAssertFalse(review.isEmpty)
    }

    func testSingleSessionLibraryStillProducesASensibleRecap() {
        let spot = TestFixture.spot(name: "Trestles")
        let only = TestFixture.session(
            date: TestCalendar.makeDate(year: 2025, month: 6, day: 6, hour: 7),
            spot: spot,
            rating: 4,
            durationMinutes: 45
        )

        let review = YearInReviewCalculator.summary(sessions: [only], year: 2025, calendar: calendar)

        XCTAssertEqual(review.sessionCount, 1)
        XCTAssertEqual(review.surfDays, 1)
        XCTAssertEqual(review.totalMinutes, 45)
        XCTAssertEqual(review.averageRating ?? 0, 4.0, accuracy: 0.0001)
        XCTAssertEqual(review.topSpot, YearInReviewLeader(name: "Trestles", count: 1))
        XCTAssertNil(review.topGear)
        XCTAssertEqual(review.bestMonth?.count, 1)
        XCTAssertEqual(review.longestWeekStreak, 1)
        XCTAssertTrue(review.waveHeightDistribution.isEmpty)
        XCTAssertFalse(review.isEmpty)
    }

    func testEmptyYearIsEmptyNotZeroed() {
        let review = YearInReviewCalculator.summary(
            sessions: richLibrary(),
            year: 2023,
            calendar: calendar
        )

        XCTAssertTrue(review.isEmpty)
        XCTAssertEqual(review.sessionCount, 0)
        XCTAssertNil(review.averageRating)
        XCTAssertNil(review.topSpot)
        XCTAssertNil(review.bestMonth)
        XCTAssertEqual(review.longestWeekStreak, 0)
    }

    func testAvailableYearsAreNewestFirst() {
        XCTAssertEqual(
            YearInReviewCalculator.availableYears(sessions: richLibrary(), calendar: calendar),
            [2025, 2024]
        )
        XCTAssertTrue(YearInReviewCalculator.availableYears(sessions: [], calendar: calendar).isEmpty)
    }
}

/// Monthly goal progress. Goals must read honestly at both ends: an untouched
/// month and a month that blew past the target.
final class MonthlyGoalCalculatorTests: XCTestCase {
    private let calendar = TestCalendar.gmt
    private let reference = TestCalendar.makeDate(year: 2026, month: 7, day: 20, hour: 12)

    private func sessions(count: Int, durationMinutes: Int? = nil) -> [SurfSession] {
        (1...max(count, 1)).prefix(count).map { day in
            TestFixture.session(
                date: TestCalendar.makeDate(year: 2026, month: 7, day: day, hour: 7),
                durationMinutes: durationMinutes
            )
        }
    }

    func testZeroSessionsProducesAnEmptyRing() {
        let progress = MonthlyGoalCalculator.progress(
            sessions: [],
            metric: .sessions,
            target: 8,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(progress.achieved, 0)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertFalse(progress.isMet)
        XCTAssertTrue(progress.isActive)
        XCTAssertEqual(progress.remaining, 8)
        XCTAssertEqual(progress.summaryLabel, "0 of 8 sessions")
    }

    func testPartialProgress() {
        let progress = MonthlyGoalCalculator.progress(
            sessions: sessions(count: 3),
            metric: .sessions,
            target: 8,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(progress.achieved, 3)
        XCTAssertEqual(progress.fraction, 0.375, accuracy: 0.0001)
        XCTAssertFalse(progress.isMet)
        XCTAssertEqual(progress.remaining, 5)
    }

    func testGoalMetExactly() {
        let progress = MonthlyGoalCalculator.progress(
            sessions: sessions(count: 8),
            metric: .sessions,
            target: 8,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertTrue(progress.isMet)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remaining, 0)
    }

    func testGoalExceededClampsTheRingButNotTheCount() {
        let progress = MonthlyGoalCalculator.progress(
            sessions: sessions(count: 12),
            metric: .sessions,
            target: 8,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertTrue(progress.isMet)
        XCTAssertEqual(progress.fraction, 1, "The ring never runs past full")
        XCTAssertEqual(progress.achieved, 12)
        XCTAssertEqual(progress.summaryLabel, "12 of 8 sessions")
    }

    func testHoursMetricUsesLoggedDurations() {
        var monthSessions = sessions(count: 3, durationMinutes: 90)
        // Sessions without a duration contribute nothing to an hours goal.
        monthSessions.append(TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 7, day: 9, hour: 7)
        ))

        let progress = MonthlyGoalCalculator.progress(
            sessions: monthSessions,
            metric: .hours,
            target: 9,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(progress.achieved, 4.5, accuracy: 0.0001)
        XCTAssertEqual(progress.achievedLabel, "4.5")
        XCTAssertFalse(progress.isMet)
    }

    func testOtherMonthsAreExcluded() {
        let lastMonth = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 6, day: 30, hour: 7)
        )
        let nextMonth = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 8, day: 1, hour: 7)
        )

        let progress = MonthlyGoalCalculator.progress(
            sessions: sessions(count: 2) + [lastMonth, nextMonth],
            metric: .sessions,
            target: 8,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(progress.achieved, 2)
    }

    func testZeroTargetTurnsTheGoalOff() {
        let progress = MonthlyGoalCalculator.progress(
            sessions: sessions(count: 4),
            metric: .sessions,
            target: 0,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertFalse(progress.isActive)
        XCTAssertFalse(progress.isMet)
        XCTAssertEqual(progress.fraction, 0)
    }
}
