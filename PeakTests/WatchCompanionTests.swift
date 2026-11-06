import XCTest
@testable import Peak

/// Unit coverage for the pure logic behind the 3.1 watch companion.
///
/// Everything here runs with no watch, no HealthKit and no ocean — which is the
/// point. The parts of the watch app that *can* be verified in CI are the state
/// machine, the elapsed-time accounting, the spot guess and the nudge copy;
/// wave detection quality is the part that genuinely needs real surf, and it is
/// not simulated here.
final class WatchCompanionTests: XCTestCase {

    // MARK: - SurfWorkoutTimeline

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecoveryUsesRecordedElapsedAndTimerKeepsPrePauseTime() {
        let now = t0.addingTimeInterval(500)
        var timeline = SurfWorkoutTimeline(recoveringStartDate: t0, elapsed: 300, paused: false, at: now)
        XCTAssertEqual(timeline.elapsed(at: now), 300)
        XCTAssertEqual(timeline.timerReferenceDate, now.addingTimeInterval(-300))
        timeline.apply(.pause, at: now.addingTimeInterval(10))
        timeline.apply(.resume, at: now.addingTimeInterval(40))
        XCTAssertEqual(timeline.elapsed(at: now.addingTimeInterval(50)), 320)
        XCTAssertEqual(timeline.timerReferenceDate, now.addingTimeInterval(40 - 310))
    }

    func testTimelineStartsIdle() {
        let timeline = SurfWorkoutTimeline()
        XCTAssertEqual(timeline.state, .idle)
        XCTAssertEqual(timeline.elapsed(at: t0), 0)
        XCTAssertFalse(timeline.isActive)
    }

    func testStartMovesToRunningAndRecordsStart() {
        var timeline = SurfWorkoutTimeline()
        XCTAssertTrue(timeline.apply(.start, at: t0))
        XCTAssertEqual(timeline.state, .running)
        XCTAssertEqual(timeline.startedAt, t0)
        XCTAssertTrue(timeline.isActive)
    }

    func testElapsedCountsOnlyRunningTime() {
        var timeline = SurfWorkoutTimeline()
        timeline.apply(.start, at: t0)
        // 10 minutes surfing.
        timeline.apply(.pause, at: t0.addingTimeInterval(600))
        // 30 minutes sitting on the beach — must not count.
        timeline.apply(.resume, at: t0.addingTimeInterval(2_400))
        // 5 more minutes surfing.
        timeline.apply(.end, at: t0.addingTimeInterval(2_700))

        XCTAssertEqual(timeline.state, .ended)
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(9_999)), 900)
    }

    func testElapsedIsFrozenOnceEnded() {
        var timeline = SurfWorkoutTimeline()
        timeline.apply(.start, at: t0)
        timeline.apply(.end, at: t0.addingTimeInterval(300))

        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(300)), 300)
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(86_400)), 300)
    }

    func testPausedClockDoesNotAdvance() {
        var timeline = SurfWorkoutTimeline()
        timeline.apply(.start, at: t0)
        timeline.apply(.pause, at: t0.addingTimeInterval(120))

        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(120)), 120)
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(6_000)), 120)
    }

    /// The illegal transitions are the ones watchOS can actually deliver: a
    /// duplicate End from a double-tap, a resume that was never paused.
    func testIllegalTransitionsAreRejectedWithoutChangingState() {
        var timeline = SurfWorkoutTimeline()
        XCTAssertFalse(timeline.apply(.pause, at: t0))
        XCTAssertFalse(timeline.apply(.resume, at: t0))
        XCTAssertFalse(timeline.apply(.end, at: t0))
        XCTAssertEqual(timeline.state, .idle)

        timeline.apply(.start, at: t0)
        XCTAssertFalse(timeline.apply(.start, at: t0))
        XCTAssertEqual(timeline.state, .running)

        timeline.apply(.end, at: t0.addingTimeInterval(60))
        XCTAssertFalse(timeline.apply(.end, at: t0.addingTimeInterval(61)))
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(999)), 60)
    }

    func testRepeatedPauseIsANoOpRatherThanDoubleCounting() {
        var timeline = SurfWorkoutTimeline()
        timeline.apply(.start, at: t0)
        timeline.apply(.pause, at: t0.addingTimeInterval(100))
        XCTAssertFalse(timeline.apply(.pause, at: t0.addingTimeInterval(200)))
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(500)), 100)
    }

    // MARK: - SurfWorkoutClockFormatter

    func testClockFormatsUnderAnHour() {
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: 0), "0:00")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: 5), "0:05")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: 65), "1:05")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: 3_599), "59:59")
    }

    func testClockFormatsOverAnHour() {
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: 3_600), "1:00:00")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: 4_332), "1:12:12")
    }

    func testClockClampsNonsense() {
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: -10), "0:00")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: .infinity), "0:00")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: .nan), "0:00")
        XCTAssertEqual(SurfWorkoutClockFormatter.string(from: .greatestFiniteMagnitude), "0:00")
    }

    // MARK: - NearestSpotMatcher

    private var trestles: SpotCandidate {
        SpotCandidate(key: "trestles", name: "Trestles", latitude: 33.3853, longitude: -117.5900)
    }

    private var blackies: SpotCandidate {
        SpotCandidate(key: "blackies", name: "Blackies", latitude: 33.6100, longitude: -117.9300)
    }

    func testNearestPicksTheCloserSpot() {
        let match = NearestSpotMatcher.nearest(
            toLatitude: 33.3860,
            longitude: -117.5910,
            among: [blackies, trestles]
        )
        XCTAssertEqual(match?.key, "trestles")
    }

    func testNearestReturnsNilBeyondTheRadius() {
        // Roughly 25 km up the coast from Trestles — a different break.
        let match = NearestSpotMatcher.nearest(
            toLatitude: 33.6000,
            longitude: -117.8800,
            among: [trestles]
        )
        XCTAssertNil(match)
    }

    func testNearestReturnsNilWithNoSpots() {
        XCTAssertNil(NearestSpotMatcher.nearest(toLatitude: 33.38, longitude: -117.59, among: []))
    }

    func testNearestRejectsNonFiniteCoordinates() {
        XCTAssertNil(
            NearestSpotMatcher.nearest(toLatitude: .nan, longitude: -117.59, among: [trestles])
        )
    }

    /// Two spots pinned at the same place must always resolve the same way, or
    /// the nudge flickers between them across launches.
    func testNearestBreaksTiesDeterministicallyOnKey() {
        let a = SpotCandidate(key: "aaa", name: "A", latitude: 33.3853, longitude: -117.5900)
        let z = SpotCandidate(key: "zzz", name: "Z", latitude: 33.3853, longitude: -117.5900)

        let first = NearestSpotMatcher.nearest(toLatitude: 33.3853, longitude: -117.5900, among: [z, a])
        let second = NearestSpotMatcher.nearest(toLatitude: 33.3853, longitude: -117.5900, among: [a, z])
        XCTAssertEqual(first?.key, "aaa")
        XCTAssertEqual(second?.key, "aaa")
    }

    func testDistanceIsSymmetricAndRoughlyRight() {
        // Trestles to Blackies is about 40 km up the coast.
        let distance = NearestSpotMatcher.distanceMeters(
            fromLatitude: trestles.latitude,
            longitude: trestles.longitude,
            toLatitude: blackies.latitude,
            longitude: blackies.longitude
        )
        let reverse = NearestSpotMatcher.distanceMeters(
            fromLatitude: blackies.latitude,
            longitude: blackies.longitude,
            toLatitude: trestles.latitude,
            longitude: trestles.longitude
        )
        XCTAssertEqual(distance, reverse, accuracy: 0.001)
        XCTAssertEqual(distance / 1000, 40, accuracy: 5)
    }

    /// A spot either side of the antimeridian must measure the short way round.
    func testDistanceWrapsTheAntimeridian() {
        let distance = NearestSpotMatcher.distanceMeters(
            fromLatitude: -16.8,
            longitude: 179.9,
            toLatitude: -16.8,
            longitude: -179.9
        )
        XCTAssertLessThan(distance, 30_000)
    }

    func testDistanceRejectsNonFiniteInput() {
        XCTAssertEqual(
            NearestSpotMatcher.distanceMeters(
                fromLatitude: .nan, longitude: 0, toLatitude: 0, longitude: 0
            ),
            .infinity
        )
    }

    // MARK: - SurfSessionHandoff

    func testHandoffRoundTripsThroughJSON() throws {
        let handoff = SurfSessionHandoff(
            startDate: t0,
            endDate: t0.addingTimeInterval(4_320),
            activeDuration: 4_000,
            workoutUUID: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
            totalDistanceMeters: 1_234.5,
            averageHeartRate: 132,
            routeStartLatitude: 33.3853,
            routeStartLongitude: -117.5900
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            SurfSessionHandoff.self,
            from: encoder.encode(handoff)
        )
        XCTAssertEqual(decoded, handoff)
    }

    func testHandoffActiveMinutesRounds() {
        let handoff = SurfSessionHandoff(
            startDate: t0,
            endDate: t0.addingTimeInterval(4_320),
            activeDuration: 4_310
        )
        XCTAssertEqual(handoff.activeMinutes, 72)
    }

    /// Two sessions surfed back to back must not overwrite each other in the
    /// transfer queue.
    func testHandoffFileNamesAreDistinctPerSession() {
        let first = SurfSessionHandoff(startDate: t0, endDate: t0, activeDuration: 0)
        let second = SurfSessionHandoff(
            startDate: t0.addingTimeInterval(7_200),
            endDate: t0.addingTimeInterval(7_200),
            activeDuration: 0
        )
        XCTAssertNotEqual(first.transferFileName, second.transferFileName)
        let sameSecondA = SurfSessionHandoff(startDate: t0, endDate: t0, activeDuration: 0, workoutUUID: UUID())
        let sameSecondB = SurfSessionHandoff(startDate: t0, endDate: t0, activeDuration: 0, workoutUUID: UUID())
        XCTAssertNotEqual(sameSecondA.transferFileName, sameSecondB.transferFileName)
    }

    // MARK: - SurfSessionNudgeBuilder

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    func testNudgeNamesTheNearestSpot() {
        let start = date("2026-07-18T07:00:00-07:00")
        let nudge = SurfSessionNudgeBuilder.make(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(4_320),
            routeStartLatitude: 33.3855,
            routeStartLongitude: -117.5902,
            spots: [trestles, blackies],
            now: date("2026-07-20T09:00:00-07:00"),
            calendar: calendar
        )

        XCTAssertEqual(nudge?.spotKey, "trestles")
        XCTAssertEqual(nudge?.durationMinutes, 70)
        XCTAssertEqual(nudge?.message, "Log Saturday's 1h 10m session at Trestles?")
    }

    func testNudgeWithoutACloseSpotOmitsThePlace() {
        let start = date("2026-07-20T07:00:00-07:00")
        let nudge = SurfSessionNudgeBuilder.make(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            routeStartLatitude: 20.0,
            routeStartLongitude: -155.0,
            spots: [trestles],
            now: date("2026-07-20T09:00:00-07:00"),
            calendar: calendar
        )

        XCTAssertNil(nudge?.spotKey)
        XCTAssertEqual(nudge?.message, "Log today's 1h session?")
    }

    func testNudgeWithoutRouteCoordinatesStillOffers() {
        let start = date("2026-07-19T07:00:00-07:00")
        let nudge = SurfSessionNudgeBuilder.make(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(2_700),
            routeStartLatitude: nil,
            routeStartLongitude: nil,
            spots: [trestles],
            now: date("2026-07-20T09:00:00-07:00"),
            calendar: calendar
        )

        XCTAssertNotNil(nudge)
        XCTAssertNil(nudge?.spotName)
        XCTAssertEqual(nudge?.message, "Log yesterday's 45m session?")
    }

    func testNudgeSkipsMistapLengthWorkouts() {
        let start = date("2026-07-20T07:00:00-07:00")
        XCTAssertNil(
            SurfSessionNudgeBuilder.make(
                workoutID: UUID(),
                startDate: start,
                endDate: start.addingTimeInterval(120),
                routeStartLatitude: nil,
                routeStartLongitude: nil,
                spots: [],
                now: date("2026-07-20T09:00:00-07:00"),
                calendar: calendar
            )
        )
    }

    func testNudgeSkipsStaleWorkouts() {
        let start = date("2026-06-01T07:00:00-07:00")
        XCTAssertNil(
            SurfSessionNudgeBuilder.make(
                workoutID: UUID(),
                startDate: start,
                endDate: start.addingTimeInterval(3_600),
                routeStartLatitude: nil,
                routeStartLongitude: nil,
                spots: [],
                now: date("2026-07-20T09:00:00-07:00"),
                calendar: calendar
            )
        )
    }

    /// Past six days a weekday name is ambiguous, so the copy switches to a date.
    func testDayReferenceSwitchesFromWeekdayToDate() {
        let now = date("2026-07-20T09:00:00-07:00")

        XCTAssertEqual(
            SurfSessionNudgeBuilder.dayReference(
                for: date("2026-07-20T07:00:00-07:00"), now: now, calendar: calendar
            ),
            "today's"
        )
        XCTAssertEqual(
            SurfSessionNudgeBuilder.dayReference(
                for: date("2026-07-19T07:00:00-07:00"), now: now, calendar: calendar
            ),
            "yesterday's"
        )
        XCTAssertEqual(
            SurfSessionNudgeBuilder.dayReference(
                for: date("2026-07-18T07:00:00-07:00"), now: now, calendar: calendar
            ),
            "Saturday's"
        )
        XCTAssertFalse(
            SurfSessionNudgeBuilder.dayReference(
                for: date("2026-07-10T07:00:00-07:00"), now: now, calendar: calendar
            ).hasSuffix("day's")
        )
    }

    // MARK: - Smart Stack relevance window

    func testDawnPatrolWindowIsThisMorningBeforeItCloses() {
        let now = date("2026-07-20T04:00:00-07:00")
        let window = LogSurfRelevanceWindow.dawnPatrolWindow(from: now, calendar: calendar)
        XCTAssertEqual(window?.start, date("2026-07-20T05:00:00-07:00"))
        XCTAssertEqual(window?.end, date("2026-07-20T09:00:00-07:00"))
    }

    func testDawnPatrolWindowRollsToTomorrowOnceClosed() {
        let now = date("2026-07-20T14:00:00-07:00")
        let window = LogSurfRelevanceWindow.dawnPatrolWindow(from: now, calendar: calendar)
        XCTAssertEqual(window?.start, date("2026-07-21T05:00:00-07:00"))
    }
}
