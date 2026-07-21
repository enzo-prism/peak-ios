import XCTest

@testable import Peak

final class GearUsageCalculatorTests: XCTestCase {
    func testGearUsageSummaryAndTopSpots() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let janDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 8))!
        let febDate1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5, hour: 8))!
        let febDate2 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 8))!

        let gear = Gear(name: "6'2\" Fish", kind: .board)
        let spotA = Spot(name: "Trestles")
        let spotB = Spot(name: "Ocean Beach")

        let session1 = SurfSession(date: janDate, spot: spotA, gear: [gear], rating: 5)
        let session2 = SurfSession(date: febDate1, spot: spotA, gear: [gear], rating: 3)
        let session3 = SurfSession(date: febDate2, spot: spotB, gear: [gear], rating: 0)

        let summary = GearUsageCalculator.summary(
            for: gear,
            sessions: [session1, session2, session3],
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(summary.totalUses, 3)
        XCTAssertEqual(summary.firstUsed, janDate)
        XCTAssertEqual(summary.lastUsed, febDate2)
        XCTAssertEqual(summary.averageRating, 4.0)
        XCTAssertEqual(summary.topSpots.first?.name, "Trestles")
        XCTAssertEqual(summary.topSpots.first?.count, 2)
        XCTAssertEqual(summary.topSpots.count, 2)

        let january = calendar.date(from: DateComponents(year: 2026, month: 1))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2))!
        let janCount = summary.monthlyCounts.first(where: { $0.month == january })?.count
        let febCount = summary.monthlyCounts.first(where: { $0.month == february })?.count

        XCTAssertEqual(janCount, 1)
        XCTAssertEqual(febCount, 2)
    }

    func testGearPolicyRequiresArchiveWhenUsed() {
        let gear = Gear(name: "Step-Up", kind: .board)
        let session = SurfSession(date: Date(), spot: nil, gear: [gear], rating: 4)

        let policy = GearUsageCalculator.policy(for: gear, sessions: [session])

        XCTAssertFalse(policy.canDelete)
        XCTAssertTrue(policy.canArchive)
    }

    func testGearPolicyAllowsDeleteWhenUnused() {
        let gear = Gear(name: "Spare Leash", kind: .leash)
        let policy = GearUsageCalculator.policy(for: gear, sessions: [])

        XCTAssertTrue(policy.canDelete)
        XCTAssertFalse(policy.canArchive)
    }

    func testSummaryHandlesUnknownSpot() {
        let gear = Gear(name: "Step-Up", kind: .board)
        let date = TestCalendar.makeDate(year: 2026, month: 2, day: 8, hour: 7)
        let sessions = [
            SurfSession(date: date, spot: nil, gear: [gear], rating: 4)
        ]

        let summary = GearUsageCalculator.summary(
            for: gear,
            sessions: sessions,
            calendar: TestCalendar.gmt,
            referenceDate: date
        )

        XCTAssertEqual(summary.topSpots.first?.name, "Unknown spot")
        XCTAssertEqual(summary.totalUses, 1)
    }

    func testSummarySortsTopSpotsByNameOnTie() {
        let gear = Gear(name: "Groveler", kind: .board)
        let spotA = Spot(name: "A Spot")
        let spotB = Spot(name: "B Spot")
        let sessions = [
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 10), spot: spotB, gear: [gear], rating: 3),
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 11), spot: spotA, gear: [gear], rating: 4)
        ]

        let summary = GearUsageCalculator.summary(
            for: gear,
            sessions: sessions,
            calendar: TestCalendar.gmt,
            referenceDate: TestCalendar.makeDate(year: 2026, month: 2, day: 12)
        )

        XCTAssertEqual(summary.topSpots.map(\.name), ["A Spot", "B Spot"])
    }

    func testUsageCountMatchesSessions() {
        let gear = Gear(name: "Twin Pin", kind: .board)
        let sessions = [
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: nil, gear: [gear]),
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2), spot: nil, gear: [])
        ]

        XCTAssertEqual(GearUsageCalculator.usageCount(for: gear, sessions: sessions), 1)
    }
}

/// Board report aggregates. The n<3 suppression rule is the important part:
/// a one-session bucket claiming an average is misinformation, not an insight.
final class GearInsightsCalculatorTests: XCTestCase {
    private func session(
        day: Int,
        gear: [Gear],
        rating: Int,
        waveHeight: WaveHeight? = nil,
        waveHeightMeters: Double? = nil,
        periodSeconds: Double? = nil
    ) -> SurfSession {
        let session = SurfSession(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: day, hour: 7),
            spot: nil,
            gear: gear,
            rating: rating
        )
        session.waveHeight = waveHeight
        session.waveHeightMeters = waveHeightMeters
        session.swellWavePeriodSeconds = periodSeconds
        return session
    }

    func testPeriodBandThresholds() {
        XCTAssertEqual(SwellPeriodBand.band(forSeconds: 9.9), .short)
        XCTAssertEqual(SwellPeriodBand.band(forSeconds: 10), .mid)
        XCTAssertEqual(SwellPeriodBand.band(forSeconds: 12.9), .mid)
        XCTAssertEqual(SwellPeriodBand.band(forSeconds: 13), .long)
        XCTAssertEqual(SwellPeriodBand.band(forSeconds: 20), .long)
    }

    func testWaveBandFallsBackToMeasuredHeight() {
        let fish = Gear(name: "Fish", kind: .board)
        let logged = session(day: 1, gear: [fish], rating: 4, waveHeight: .overhead, waveHeightMeters: 0.5)
        let measuredOnly = session(day: 2, gear: [fish], rating: 4, waveHeightMeters: 0.8)
        let neither = session(day: 3, gear: [fish], rating: 4)

        // A logged band always wins over the measured number.
        XCTAssertEqual(GearInsightsCalculator.waveBand(for: logged), .overhead)
        XCTAssertEqual(GearInsightsCalculator.waveBand(for: measuredOnly), .waistHigh)
        XCTAssertNil(GearInsightsCalculator.waveBand(for: neither))
    }

    func testBucketAveragesAcrossHeightAndPeriod() {
        let fish = Gear(name: "Fish", kind: .board)
        let sessions = [
            session(day: 1, gear: [fish], rating: 5, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 2, gear: [fish], rating: 4, waveHeight: .waistHigh, periodSeconds: 9),
            session(day: 3, gear: [fish], rating: 3, waveHeight: .waistHigh, periodSeconds: 8.5),
            session(day: 4, gear: [fish], rating: 1, waveHeight: .overhead, periodSeconds: 14)
        ]

        let report = GearInsightsCalculator.report(for: fish, sessions: sessions)

        XCTAssertEqual(report.sessionCount, 4)
        XCTAssertEqual(report.ratedSessionCount, 4)
        XCTAssertEqual(report.averageRating ?? 0, 3.25, accuracy: 0.0001)

        let waist = report.waveHeightBuckets.first { $0.label == WaveHeight.waistHigh.label }
        XCTAssertEqual(waist?.sessionCount, 3)
        XCTAssertEqual(waist?.averageRating ?? 0, 4.0, accuracy: 0.0001)

        let short = report.periodBuckets.first { $0.label == SwellPeriodBand.short.label }
        XCTAssertEqual(short?.sessionCount, 3)
        XCTAssertEqual(short?.averageRating ?? 0, 4.0, accuracy: 0.0001)

        XCTAssertEqual(report.highlight?.phrase, "short-period waist-high")
        XCTAssertEqual(report.highlight?.sessionCount, 3)
        XCTAssertEqual(report.highlight?.averageRating ?? 0, 4.0, accuracy: 0.0001)
    }

    func testBucketsBelowMinimumSuppressTheirAverage() {
        let fish = Gear(name: "Fish", kind: .board)
        let sessions = [
            session(day: 1, gear: [fish], rating: 5, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 2, gear: [fish], rating: 5, waveHeight: .overhead, periodSeconds: 14),
            session(day: 3, gear: [fish], rating: 5, waveHeight: .overhead, periodSeconds: 15)
        ]

        let report = GearInsightsCalculator.report(for: fish, sessions: sessions)

        let waist = report.waveHeightBuckets.first { $0.label == WaveHeight.waistHigh.label }
        XCTAssertEqual(waist?.sessionCount, 1)
        XCTAssertNil(waist?.averageRating, "A one-session bucket must never publish an average")
        XCTAssertEqual(waist?.hasEnoughData, false)

        let overhead = report.waveHeightBuckets.first { $0.label == WaveHeight.overhead.label }
        XCTAssertEqual(overhead?.sessionCount, 2)
        XCTAssertNil(overhead?.averageRating, "Two sessions is still below the floor")

        XCTAssertNil(report.highlight, "No combination cleared the floor")
        XCTAssertFalse(report.hasBucketInsights)
        // The overall average is not a bucket and stays visible.
        XCTAssertEqual(report.averageRating ?? 0, 5.0, accuracy: 0.0001)
    }

    func testUnratedSessionsAreExcludedFromBuckets() {
        let fish = Gear(name: "Fish", kind: .board)
        let sessions = [
            session(day: 1, gear: [fish], rating: 0, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 2, gear: [fish], rating: 0, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 3, gear: [fish], rating: 4, waveHeight: .waistHigh, periodSeconds: 8)
        ]

        let report = GearInsightsCalculator.report(for: fish, sessions: sessions)

        XCTAssertEqual(report.sessionCount, 3)
        XCTAssertEqual(report.ratedSessionCount, 1)
        let waist = report.waveHeightBuckets.first { $0.label == WaveHeight.waistHigh.label }
        XCTAssertEqual(waist?.sessionCount, 1)
        XCTAssertNil(waist?.averageRating)
    }

    func testHighlightPicksTheBestQualifyingCombination() {
        let stepUp = Gear(name: "Step-up", kind: .board)
        let sessions = [
            session(day: 1, gear: [stepUp], rating: 3, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 2, gear: [stepUp], rating: 3, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 3, gear: [stepUp], rating: 3, waveHeight: .waistHigh, periodSeconds: 8),
            session(day: 4, gear: [stepUp], rating: 5, waveHeight: .overhead, periodSeconds: 14),
            session(day: 5, gear: [stepUp], rating: 5, waveHeight: .overhead, periodSeconds: 15),
            session(day: 6, gear: [stepUp], rating: 4, waveHeight: .overhead, periodSeconds: 16)
        ]

        let report = GearInsightsCalculator.report(for: stepUp, sessions: sessions)

        XCTAssertEqual(report.highlight?.phrase, "long-period overhead")
        XCTAssertEqual(report.highlight?.averageRating ?? 0, 14.0 / 3, accuracy: 0.0001)
        XCTAssertTrue(report.hasBucketInsights)
    }

    func testReportsDropUnusedGearAndSortByUsage() {
        let fish = Gear(name: "Fish", kind: .board)
        let log = Gear(name: "Log", kind: .board)
        let unused = Gear(name: "Gun", kind: .board)
        let sessions = [
            session(day: 1, gear: [fish], rating: 4),
            session(day: 2, gear: [fish], rating: 4),
            session(day: 3, gear: [log], rating: 4)
        ]

        let reports = GearInsightsCalculator.reports(for: [log, unused, fish], sessions: sessions)

        XCTAssertEqual(reports.map(\.gearName), ["Fish", "Log"])
    }

    func testEmptyLibraryProducesEmptyReport() {
        let fish = Gear(name: "Fish", kind: .board)
        let report = GearInsightsCalculator.report(for: fish, sessions: [])

        XCTAssertEqual(report.sessionCount, 0)
        XCTAssertNil(report.averageRating)
        XCTAssertTrue(report.waveHeightBuckets.isEmpty)
        XCTAssertTrue(report.periodBuckets.isEmpty)
        XCTAssertFalse(report.hasBucketInsights)
    }
}
