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

    func testTopItemsAreDeterministicWhenNameAndCountTie() {
        // Same display name, different kind → same name + count but distinct keys.
        // The final `key` tiebreak must give a stable order across runs.
        let fishBoard = TestFixture.gear(name: "Fish", kind: .board)
        let fishFins = TestFixture.gear(name: "Fish", kind: .fins)

        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 5), gear: [fishBoard]),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 6), gear: [fishFins])
        ]

        let keys = StatsCalculator.summarize(sessions: sessions, topLimit: 2).topGear.map(\.key)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys, keys.sorted(), "Ties must resolve deterministically by key")
    }

    func testSpotMixOtherBucketUsesSingularForOneSpot() {
        // Six spots, topLimit 5 → exactly one spot lands in the Other bucket.
        let sessions = (1...6).map { index in
            TestFixture.session(
                date: TestCalendar.makeDate(year: 2026, month: 2, day: index),
                spot: TestFixture.spot(name: "Spot \(index)")
            )
        }
        let mix = StatsCalculator.spotMix(sessions: sessions, topLimit: 5)
        let other = mix.first { $0.key == "stats.spot-mix.other" }
        XCTAssertEqual(other?.detail, "1 spot")
    }

    func testSpotMixOtherBucketUsesPluralForMultipleSpots() {
        let sessions = (1...7).map { index in
            TestFixture.session(
                date: TestCalendar.makeDate(year: 2026, month: 2, day: index),
                spot: TestFixture.spot(name: "Spot \(index)")
            )
        }
        let mix = StatsCalculator.spotMix(sessions: sessions, topLimit: 5)
        let other = mix.first { $0.key == "stats.spot-mix.other" }
        XCTAssertEqual(other?.detail, "2 spots")
    }

    func testWaveHeightRatingSamplesKeepChronologyAndCapToMostRecent() {
        func rated(_ day: Int) -> SurfSession {
            let session = TestFixture.session(
                date: TestCalendar.makeDate(year: 2026, month: 2, day: day, hour: 7),
                rating: 4
            )
            session.waveHeightMeters = Double(day)
            return session
        }

        let small = StatsCalculator.waveHeightRatingSamples(
            sessions: [rated(3), rated(1), rated(2)]
        )
        XCTAssertEqual(small.map(\.waveHeightMeters), [1, 2, 3])

        let many = (1...12).map(rated)
        let capped = StatsCalculator.waveHeightRatingSamples(sessions: many, limit: 5)
        XCTAssertEqual(capped.count, 5)
        XCTAssertEqual(capped.map(\.waveHeightMeters), [8, 9, 10, 11, 12])
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

    func testLimitPrefersCloserYearOverAHigherOlderRating() {
        let closer = session(year: 2025, month: 7, day: 20, rating: 2)
        let olderBetter = session(year: 2024, month: 7, day: 20, rating: 5)

        let memories = OnThisDayProvider.memories(
            sessions: [olderBetter, closer],
            referenceDate: TestCalendar.makeDate(year: 2026, month: 7, day: 20, hour: 12),
            calendar: calendar,
            limit: 1
        )

        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.yearsAgo, 1)
        XCTAssertEqual(memories.first?.session.rating, 2)
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

// MARK: - Wave stats (3.0)

/// `WaveStatsCalculator` has to be correct in the presence of a logbook where
/// most sessions carry no wave data at all — the common case for a user who
/// logs by hand and only sometimes wears a watch.
final class WaveStatsCalculatorTests: XCTestCase {

    private func session(
        day: Int,
        spot: String = "Trestles",
        waves: Int? = nil,
        topSpeedKph: Double? = nil,
        longestRideSeconds: Double? = nil,
        source: WaveStatsSource? = nil,
        month: Int = 3
    ) -> SurfSession {
        let session = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: month, day: day, hour: 7),
            spot: TestFixture.spot(name: spot)
        )
        session.waveCount = waves
        session.topSpeedKph = topSpeedKph
        session.longestRideSeconds = longestRideSeconds
        session.waveStats = source
        return session
    }

    // MARK: Records

    /// The headline guarantee: a logbook with no wave data anywhere produces no
    /// records at all, so the Stats card can suppress itself entirely rather than
    /// showing three dashes.
    func testNoWaveStatsProducesNoRecords() {
        let records = WaveStatsCalculator.records(sessions: [
            session(day: 1), session(day: 2), session(day: 3)
        ])
        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(records.mostWaves)
        XCTAssertNil(records.fastestWave)
        XCTAssertNil(records.longestRide)
    }

    func testEmptyLogbookProducesNoRecords() {
        XCTAssertTrue(WaveStatsCalculator.records(sessions: []).isEmpty)
    }

    func testRecordsPickTheBestSessionPerStatistic() {
        let sessions = [
            session(day: 1, spot: "Malibu", waves: 4, topSpeedKph: 30.0, longestRideSeconds: 8),
            session(day: 2, spot: "Trestles", waves: 14, topSpeedKph: 21.0, longestRideSeconds: 11),
            session(day: 3, spot: "Pipeline", waves: 7, topSpeedKph: 25.0, longestRideSeconds: 26)
        ]
        let records = WaveStatsCalculator.records(sessions: sessions)

        XCTAssertEqual(records.mostWaves?.spotName, "Trestles")
        XCTAssertEqual(records.fastestWave?.spotName, "Malibu")
        XCTAssertEqual(records.longestRide?.spotName, "Pipeline")
        XCTAssertFalse(records.isEmpty)
    }

    /// Each statistic is resolved independently: a logbook where only top speed
    /// was ever recorded gets exactly one record, not three.
    func testRecordsAreResolvedIndependently() {
        let records = WaveStatsCalculator.records(sessions: [
            session(day: 1, topSpeedKph: 24.0),
            session(day: 2)
        ])
        XCTAssertNil(records.mostWaves)
        XCTAssertNotNil(records.fastestWave)
        XCTAssertNil(records.longestRide)
        XCTAssertFalse(records.isEmpty)
    }

    /// Zero is stored for a skunked session but is not a personal record — "your
    /// best day: 0 waves" is a bug, not a stat.
    func testZeroWaveSessionsDoNotSetRecords() {
        let records = WaveStatsCalculator.records(sessions: [
            session(day: 1, waves: 0), session(day: 2, waves: 0)
        ])
        XCTAssertNil(records.mostWaves)
    }

    /// Ties resolve to the more recent session, so the record keeps moving as the
    /// user keeps surfing.
    func testTiedRecordsPreferTheMoreRecentSession() {
        let records = WaveStatsCalculator.records(sessions: [
            session(day: 1, spot: "Old Break", waves: 9),
            session(day: 20, spot: "New Break", waves: 9)
        ])
        XCTAssertEqual(records.mostWaves?.spotName, "New Break")
    }

    /// A record built on an unreviewed estimate is flagged, so the card can say
    /// so rather than presenting a guess as an achievement.
    func testRecordCarriesEstimateFlagFromItsSession() {
        let auto = WaveStatsCalculator.records(sessions: [
            session(day: 1, waves: 9, source: .auto)
        ])
        XCTAssertEqual(auto.mostWaves?.isEstimate, true)

        for source in [WaveStatsSource.edited, .manual] {
            let records = WaveStatsCalculator.records(sessions: [
                session(day: 1, waves: 9, source: source)
            ])
            XCTAssertEqual(records.mostWaves?.isEstimate, false, "\(source.rawValue) flagged as estimate")
        }
    }

    func testRecordIdentityIsStableAcrossRecomputes() {
        let sessions = [session(day: 1, waves: 9)]
        XCTAssertEqual(
            WaveStatsCalculator.records(sessions: sessions).mostWaves?.id,
            WaveStatsCalculator.records(sessions: sessions).mostWaves?.id
        )
    }

    // MARK: Waves-per-session trend

    func testWavesPerSessionAveragesWithinEachMonth() {
        let trend = WaveStatsCalculator.wavesPerSession(
            sessions: [
                session(day: 2, waves: 4, month: 3),
                session(day: 20, waves: 8, month: 3),
                session(day: 5, waves: 10, month: 4)
            ],
            calendar: TestCalendar.gmt
        )

        XCTAssertEqual(trend.count, 2)
        XCTAssertEqual(trend[0].averageWaves, 6, accuracy: 0.0001)
        XCTAssertEqual(trend[0].sessionCount, 2)
        XCTAssertEqual(trend[1].averageWaves, 10, accuracy: 0.0001)
        XCTAssertEqual(trend[1].sessionCount, 1)
    }

    func testWavesPerSessionIsOldestFirst() {
        let trend = WaveStatsCalculator.wavesPerSession(
            sessions: [
                session(day: 1, waves: 5, month: 6),
                session(day: 1, waves: 5, month: 2),
                session(day: 1, waves: 5, month: 4)
            ],
            calendar: TestCalendar.gmt
        )
        XCTAssertEqual(trend.count, 3)
        for (previous, next) in zip(trend, trend.dropFirst()) {
            XCTAssertLessThan(previous.month, next.month)
        }
    }

    /// Months where nobody recorded a wave count are absent, not zero: plotting a
    /// flat zero line across a year before the user owned a watch would read as
    /// "you caught nothing", which is false rather than merely unknown.
    func testMonthsWithoutWaveCountsAreOmittedRatherThanZeroed() {
        let trend = WaveStatsCalculator.wavesPerSession(
            sessions: [
                session(day: 1, month: 1),
                session(day: 1, month: 2),
                session(day: 1, waves: 6, month: 3)
            ],
            calendar: TestCalendar.gmt
        )
        XCTAssertEqual(trend.count, 1)
        XCTAssertEqual(trend[0].averageWaves, 6, accuracy: 0.0001)
    }

    /// A skunked month IS data and must appear at zero — distinct from a month
    /// with no data at all, which must not.
    func testSkunkedMonthAppearsAtZero() {
        let trend = WaveStatsCalculator.wavesPerSession(
            sessions: [session(day: 1, waves: 0, month: 3)],
            calendar: TestCalendar.gmt
        )
        XCTAssertEqual(trend.count, 1)
        XCTAssertEqual(trend[0].averageWaves, 0, accuracy: 0.0001)
        XCTAssertEqual(trend[0].sessionCount, 1)
    }

    func testEmptySessionsProduceEmptyTrend() {
        XCTAssertTrue(WaveStatsCalculator.wavesPerSession(sessions: [], calendar: TestCalendar.gmt).isEmpty)
    }

    // MARK: Totals

    func testTotalWavesSumsOnlySessionsThatHaveThem() {
        let total = WaveStatsCalculator.totalWaves(sessions: [
            session(day: 1, waves: 4),
            session(day: 2),
            session(day: 3, waves: 7),
            session(day: 4, waves: 0)
        ])
        XCTAssertEqual(total, 11)
    }

    func testSessionsWithWaveStatsCountsAnyStatistic() {
        XCTAssertEqual(
            WaveStatsCalculator.sessionsWithWaveStats([
                session(day: 1, waves: 4),
                session(day: 2),
                session(day: 3, topSpeedKph: 20),
                session(day: 4, longestRideSeconds: 12)
            ]),
            3
        )
    }

    func testRecordsTakeTheLaterSessionOnATiedValue() {
        let earlier = session(day: 1, waves: 10, topSpeedKph: 20, longestRideSeconds: 15)
        let later = session(day: 8, waves: 10, topSpeedKph: 20, longestRideSeconds: 15)
        let records = WaveStatsCalculator.records(sessions: [earlier, later])

        XCTAssertEqual(records.mostWaves?.date, later.date)
        XCTAssertEqual(records.fastestWave?.date, later.date)
        XCTAssertEqual(records.longestRide?.date, later.date)
    }
}

// MARK: - Wave stats formatting

final class WaveStatsFormatterTests: XCTestCase {
    // NOTE: en_GB is deliberately NOT used as the metric locale. Foundation
    // reports its measurement system as `.uk`, not `.metric`, so it takes the
    // same feet branch as the US — which matches how British surfers actually
    // talk about wave height, and matches `SurfConditionsFormatter`.
    private let metric = Locale(identifier: "fr_FR")
    private let imperial = Locale(identifier: "en_US")

    func testWaveCountPluralizes() {
        XCTAssertEqual(WaveStatsFormatter.waveCount(0), "0 waves")
        XCTAssertEqual(WaveStatsFormatter.waveCount(1), "1 wave")
        XCTAssertEqual(WaveStatsFormatter.waveCount(12), "12 waves")
    }

    func testRideDurationFormatsSecondsAndMinutes() {
        XCTAssertEqual(WaveStatsFormatter.rideDuration(0), "0s")
        XCTAssertEqual(WaveStatsFormatter.rideDuration(9), "9s")
        XCTAssertEqual(WaveStatsFormatter.rideDuration(59), "59s")
        XCTAssertEqual(WaveStatsFormatter.rideDuration(64), "1m 04s")
        XCTAssertEqual(WaveStatsFormatter.rideDuration(120), "2m 00s")
    }

    /// A NaN must never reach a label. The analyzer promises finite output, but
    /// stored values come back through SwiftData and the editor too.
    func testRideDurationRejectsNonFiniteInput() {
        XCTAssertEqual(WaveStatsFormatter.rideDuration(.nan), "0s")
        XCTAssertEqual(WaveStatsFormatter.rideDuration(.infinity), "0s")
        XCTAssertEqual(WaveStatsFormatter.rideDuration(-5), "0s")
        XCTAssertEqual(WaveStatsFormatter.spokenRideDuration(.nan), "0 seconds")
    }

    func testSpokenRideDurationIsPronounceable() {
        XCTAssertEqual(WaveStatsFormatter.spokenRideDuration(1), "1 second")
        XCTAssertEqual(WaveStatsFormatter.spokenRideDuration(18), "18 seconds")
        XCTAssertEqual(WaveStatsFormatter.spokenRideDuration(64), "1 minute 4 seconds")
        XCTAssertEqual(WaveStatsFormatter.spokenRideDuration(120), "2 minutes")
    }

    /// Values are stored metric and converted at the display boundary, so a US
    /// surfer must not be shown metres.
    func testDistanceConvertsForImperialLocales() {
        let metres = WaveStatsFormatter.distance(100, locale: metric)
        XCTAssertTrue(metres.contains("100"), "expected 100 m, got \(metres)")
        let feet = WaveStatsFormatter.distance(100, locale: imperial)
        XCTAssertTrue(feet.contains("328") || feet.contains("329"), "expected ~328 ft, got \(feet)")
    }

    /// Foundation classifies the UK as `.uk` rather than `.metric`, so it takes
    /// the imperial branch. Pinned because it looks like a bug at a glance and is
    /// in fact the same behaviour the 2.8 conditions formatter already ships.
    func testUnitedKingdomUsesFeetLikeTheConditionsFormatter() {
        let uk = Locale(identifier: "en_GB")
        XCTAssertNotEqual(uk.measurementSystem, .metric)
        let value = WaveStatsFormatter.distance(100, locale: uk)
        XCTAssertTrue(value.contains("328") || value.contains("329"), "expected feet, got \(value)")
    }

    func testSummaryOmitsMissingParts() {
        XCTAssertNil(WaveStatsFormatter.summary(waveCount: nil, topSpeedKph: nil, longestRideSeconds: nil))
        XCTAssertEqual(
            WaveStatsFormatter.summary(waveCount: 5, topSpeedKph: nil, longestRideSeconds: nil, locale: metric),
            "5 waves"
        )
        // A stored zero for speed or ride length means "no ride", not "0 km/h".
        XCTAssertEqual(
            WaveStatsFormatter.summary(waveCount: 0, topSpeedKph: 0, longestRideSeconds: 0, locale: metric),
            "0 waves"
        )
        XCTAssertTrue(
            WaveStatsFormatter.summary(waveCount: 5, topSpeedKph: 24, longestRideSeconds: 18, locale: metric)?
                .contains("longest 18s") ?? false
        )
    }

    /// The estimate microcopy is a product requirement, not decoration: it must
    /// name the source and offer the correction.
    func testEstimateCaptionStatesUncertaintyAndTheFix() {
        let caption = WaveStatsFormatter.estimateCaption
        XCTAssertTrue(caption.localizedCaseInsensitiveContains("estimat"))
        XCTAssertTrue(caption.localizedCaseInsensitiveContains("correct"))
        XCTAssertEqual(WaveStatsSource.auto.caption, caption)
        XCTAssertTrue(WaveStatsSource.auto.isEstimate)
        XCTAssertFalse(WaveStatsSource.edited.isEstimate)
        XCTAssertFalse(WaveStatsSource.manual.isEstimate)
    }
}
