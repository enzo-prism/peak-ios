import CoreGraphics
import SwiftData
import XCTest

@testable import Peak

final class SessionDraftTests: XCTestCase {
    func testNameOnlySpotSharesSessionTransactionAndPreservesDuplicatesAndLimit() throws {
        let container = try TestModelContainer.make()
        let library = container.mainContext
        let stage = try SessionPersistence.stagingContext(from: library)
        let pending = try SessionPersistence.spot(selection: nil, name: "  First reef  ", in: stage)
        XCTAssertEqual(pending.name, "First reef")
        XCTAssertEqual(try library.spotCount(), 0, "Typing and staging must not save an orphan spot")
        stage.rollback()
        XCTAssertEqual(try library.spotCount(), 0)
        let committed = try SessionPersistence.stagingContext(from: library)
        let spot = try SessionPersistence.spot(selection: nil, name: "First reef", in: committed)
        let duplicate = try SessionPersistence.spot(selection: nil, name: "FIRST REEF", in: committed)
        XCTAssertEqual(spot.persistentModelID, duplicate.persistentModelID)
        committed.insert(SurfSession(date: Date(), spot: spot))
        try committed.save()
        XCTAssertEqual(try library.spotCount(), 1)
        XCTAssertEqual(try library.fetchCount(FetchDescriptor<SurfSession>()), 1)
        for index in 1..<Spot.maxCount { committed.insert(Spot(name: "Reef \(index)")) }
        try committed.save()
        XCTAssertEqual(try committed.spotCount(), Spot.maxCount)
        XCTAssertNoThrow(try SessionPersistence.spot(selection: nil, name: "First reef", in: committed))
        XCTAssertThrowsError(try SessionPersistence.spot(selection: nil, name: "One more reef", in: committed))
        XCTAssertThrowsError(try SessionPersistence.spot(selection: nil, name: "  ", in: committed))
    }

    func testNameOnlySpotDoesNotOverwriteExistingCoordinates() throws {
        let container = try TestModelContainer.make()
        let library = container.mainContext
        let pinned = Spot(name: "Pipeline", latitude: 21.664, longitude: -158.054)
        library.insert(pinned)
        try library.save()
        let stage = try SessionPersistence.stagingContext(from: library)
        let resolved = try SessionPersistence.spot(selection: nil, name: "  PIPELINE  ", in: stage)
        XCTAssertEqual(resolved.latitude, 21.664)
        XCTAssertEqual(resolved.longitude, -158.054)
        let colliding = try library.createSpot(name: "Pipeline", locationName: nil, latitude: nil, longitude: nil)
        XCTAssertEqual(colliding.latitude, 21.664)
        XCTAssertEqual(colliding.longitude, -158.054)
        try library.save()
        let readback = try XCTUnwrap(library.existingSpot(named: "Pipeline"))
        XCTAssertEqual(readback.latitude, 21.664)
        XCTAssertEqual(readback.longitude, -158.054)
    }

    @MainActor
    func testHealthRequestFailurePreservesPreferenceAndSuccessEnablesOnlyAfterRequest() async throws {
        enum Failure: Error { case rejected }
        var enabled = false
        do {
            try await HealthAccessFlow.enable(request: { throw Failure.rejected }, setEnabled: { enabled = $0 })
            XCTFail("Failure must propagate")
        } catch { XCTAssertFalse(enabled) }
        try await HealthAccessFlow.enable(request: { XCTAssertFalse(enabled) }, setEnabled: { enabled = $0 })
        XCTAssertTrue(enabled, "This is an integration preference, not a read authorization claim")
        do {
            try await HealthAccessFlow.enable(request: { throw Failure.rejected }, setEnabled: { enabled = $0 })
        } catch { XCTAssertTrue(enabled, "Review failure must preserve the previous preference") }
    }

    func testQuiverDefaultUsesRecentSpotThenReadyComparison() {
        let alphabetical = TestFixture.spot(name: "Alpha")
        let recent = TestFixture.spot(name: "Recent")
        let a = TestFixture.gear(name: "Fish")
        let b = TestFixture.gear(name: "Egg")
        let now = Date()
        var sessions = [TestFixture.session(date: now, spot: recent, gear: [a], rating: 4)]
        XCTAssertEqual(QuiverAdvisor.preferredSpot(spots: [alphabetical, recent], sessions: sessions)?.key, recent.key)
        sessions += (0..<3).map { _ in TestFixture.session(date: now.addingTimeInterval(-100), spot: alphabetical, gear: [a], rating: 4) }
        sessions += (0..<3).map { _ in TestFixture.session(date: now.addingTimeInterval(-100), spot: alphabetical, gear: [b], rating: 2) }
        XCTAssertEqual(QuiverAdvisor.preferredSpot(spots: [alphabetical, recent], sessions: sessions)?.key, alphabetical.key)
        b.isArchived = true
        XCTAssertEqual(QuiverAdvisor.preferredSpot(spots: [alphabetical, recent], sessions: sessions)?.key, recent.key)
    }

    func testQuiverSparseCoverageKeepsMissingAndMixedBoardSourcesWithoutAveragingThem() {
        let spot = TestFixture.spot()
        let a = TestFixture.gear(name: "Fish")
        let b = TestFixture.gear(name: "Egg")
        let sessions = [TestFixture.session(spot: spot, gear: [a], rating: 4),
                        TestFixture.session(spot: spot, gear: [a], rating: 0),
                        TestFixture.session(spot: spot, gear: [a,b], rating: 5)]
        let report = QuiverAdvisor.compare(spot: spot, height: nil, period: nil, gear: [a,b], sessions: sessions)
        XCTAssertTrue(report.comparisons.isEmpty)
        XCTAssertNil(report.suggestedBoard)
        XCTAssertEqual(report.coverage.first { $0.id == a.key }?.qualifyingCount, 1)
        XCTAssertEqual(report.coverage.first { $0.id == a.key }?.sessions.count, 3)
        XCTAssertEqual(report.coverage.first { $0.id == b.key }?.qualifyingCount, 0)
    }

    func testExactRecentDatesAndTimeTotalsKeepCoverageAndRejectUnknownCriteria() {
        let now = TestCalendar.makeDate(year: 2026, month: 3, day: 15)
        let yesterday = TestCalendar.gmt.date(byAdding: .day, value: -1, to: now)!
        let a = TestFixture.session(date: yesterday)
        a.durationMinutes = 90
        let b = TestFixture.session(date: yesterday)
        let c = TestFixture.session(date: now)
        c.durationMinutes = 60
        let answer = LogbookQuery.answer("How many hours yesterday?", sessions: [a,b,c], now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(answer.sessions.count, 2)
        XCTAssertTrue(answer.explanation.contains("1 of 2"))
        XCTAssertFalse(answer.needsFilters)
        XCTAssertEqual(LogbookQuery.answer("Time in water yesterday", sessions: [a,b,c], now: now, calendar: TestCalendar.gmt).sessions.count, 2)
        XCTAssertTrue(LogbookQuery.answer("How many hours with a broken board?", sessions: [a,b,c], now: now).needsFilters)
        XCTAssertTrue(LogbookQuery.answer("Count sessions today and yesterday", sessions: [a,b,c], now: now).needsFilters)
    }

    func testLastWeekFilterHasExclusiveEndAndUsesCalendarWeek() {
        let now = TestCalendar.makeDate(year: 2026, month: 3, day: 18)
        let previous = TestCalendar.gmt.date(byAdding: .weekOfYear, value: -1, to: now)!
        let interval = TestCalendar.gmt.dateInterval(of: .weekOfYear, for: previous)!
        XCTAssertTrue(HistoryFilters.DateRange.lastWeek.contains(interval.start, now: now, calendar: TestCalendar.gmt))
        XCTAssertTrue(HistoryFilters.DateRange.lastWeek.contains(interval.end.addingTimeInterval(-1), now: now, calendar: TestCalendar.gmt))
        XCTAssertFalse(HistoryFilters.DateRange.lastWeek.contains(interval.end, now: now, calendar: TestCalendar.gmt))
        let result = LogbookQuery.answer("Count sessions last week", sessions: [TestFixture.session(date: interval.start), TestFixture.session(date: interval.end)], now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(result.sessions.count, 1)
    }

    func testUnsupportedQuerySuggestsOnlyKnownFilters() {
        let spot = TestFixture.spot(name: "Mar")
        let board = TestFixture.gear(name: "Fish")
        let sessions = [TestFixture.session(spot: spot, gear: [board])]
        let filters = LogbookQuery.suggestedFilters("Find fastest surf at Mar with Fish last week", sessions: sessions)
        XCTAssertEqual(filters.spots, [spot])
        XCTAssertEqual(filters.gear, [board])
        XCTAssertEqual(filters.dateRange, .lastWeek)
        XCTAssertTrue(LogbookQuery.suggestedFilters("at Mars", sessions: sessions).spots.isEmpty)
    }

    func testBackupProtectionCountsEditsByModificationDate() {
        let backup = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(BackupProtection.changedCount(dates: [backup.addingTimeInterval(-10), backup, backup.addingTimeInterval(1)], since: backup), 1)
        XCTAssertEqual(BackupProtection.changedCount(dates: [backup, backup], since: nil), 2)
        XCTAssertFalse(BackupProtection.shouldOffer(sessionCount: 0))
        XCTAssertTrue(BackupProtection.shouldOffer(sessionCount: 5))
    }

    func testWindowCoverageExcludesUnratedAndOtherSpots() {
        let spot = TestFixture.spot()
        let rated = TestFixture.session(spot: spot, rating: 4)
        rated.swellWaveHeightMeters = 1.5
        let unrated = TestFixture.session(spot: spot, rating: 0)
        unrated.swellWaveHeightMeters = 1.5
        let missing = TestFixture.session(spot: spot, rating: 3)
        let elsewhere = TestFixture.session(spot: TestFixture.spot(name: "Elsewhere"), rating: 5)
        let coverage = TodayWindowService.historyCoverage(sessions: [rated,unrated,missing,elsewhere], at: spot)
        XCTAssertEqual(coverage.total, 3)
        XCTAssertEqual(coverage.rated, 2)
        XCTAssertEqual(coverage.ratedWithConditions, 1)
        XCTAssertEqual(TodayWindowService.ratedHistory(sessions: [rated,unrated,missing,elsewhere], at: spot).count, 2)
    }

    func testChronologicalWindowValidationCannotLearnFromSameTimeOrFutureSurfs() {
        let base = Date(timeIntervalSince1970: 1000)
        let conditions = ConditionsSample(swellWaveHeightMeters: 1.2, swellWavePeriodSeconds: 12, waveHeightMeters: 1.4, windSpeedKph: 5, windDirectionDegrees: 90)
        let history = (0..<12).map { index in RatedSession(date: base.addingTimeInterval(Double(index) * 86400), rating: index % 2 == 0 ? 5 : 2, conditions: conditions) }
        let report = WindowValidation.evaluate(history: history)
        XCTAssertEqual(report.observations.count, 4)
        XCTAssertEqual(report.observations.map(\.trainingCount), [8,9,10,11])
        let future = RatedSession(date: base.addingTimeInterval(20 * 86400), rating: 1, conditions: conditions)
        let withFuture = WindowValidation.evaluate(history: history + [future])
        XCTAssertEqual(Array(withFuture.observations.prefix(4)), report.observations)
        let simultaneous = WindowValidation.evaluate(history: Array(repeating: history[0], count: 10))
        XCTAssertTrue(simultaneous.observations.isEmpty)
        XCTAssertEqual(report.acceptedCount + report.abstainedCount, report.observations.count)
    }

    func testNewMediaDraftItemDefaultsToFullFrameCrop() {
        let item = SessionMediaDraftItem.newPhoto(photoData: Data([0x01]), thumbnailData: nil)
        XCTAssertEqual(item.cropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testSetCropUpdatesStagedRect() {
        var draft = SessionDraft()
        let item = SessionMediaDraftItem.newPhoto(photoData: Data([0x01]), thumbnailData: nil)
        draft.mediaItems = [item]

        let rect = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        draft.setCrop(rect, for: item.id)

        XCTAssertEqual(draft.mediaItems.first?.cropRect, rect)
    }

    func testReorderingMediaItemsPreservesNewOrder() {
        var draft = SessionDraft()
        let a = SessionMediaDraftItem.newPhoto(photoData: Data([0x0A]), thumbnailData: nil)
        let b = SessionMediaDraftItem.newPhoto(photoData: Data([0x0B]), thumbnailData: nil)
        draft.mediaItems = [a, b]

        draft.mediaItems.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        XCTAssertEqual(draft.mediaItems.map(\.id), [b.id, a.id])
    }

    func testSelectSpotUpdatesNameAndSelection() {
        var draft = SessionDraft()
        let spot = TestFixture.spot(name: "Ocean Beach")

        draft.selectSpot(spot)

        XCTAssertEqual(draft.selectedSpot?.name, "Ocean Beach")
        XCTAssertEqual(draft.spotName, "Ocean Beach")
    }

    func testToggleGearAddsAndRemoves() {
        var draft = SessionDraft()
        let gear = TestFixture.gear(name: "Twin Pin")

        draft.toggleGear(gear)
        XCTAssertEqual(draft.selectedGear.count, 1)

        draft.toggleGear(gear)
        XCTAssertTrue(draft.selectedGear.isEmpty)
    }

    func testToggleBuddyAddsAndRemoves() {
        var draft = SessionDraft()
        let buddy = TestFixture.buddy(name: "Sam")

        draft.toggleBuddy(buddy)
        XCTAssertEqual(draft.selectedBuddies.count, 1)

        draft.toggleBuddy(buddy)
        XCTAssertTrue(draft.selectedBuddies.isEmpty)
    }

    func testApplySurfConditionsPopulatesFields() {
        var draft = SessionDraft()
        let snapshot = SurfConditionsSnapshot(
            source: "Open-Meteo",
            fetchedAt: TestCalendar.makeDate(year: 2026, month: 2, day: 5, hour: 8),
            latitude: 33.3,
            longitude: -117.6,
            windSpeedKph: 12,
            windDirectionDegrees: 280,
            waveHeightMeters: 1.4,
            swellWaveHeightMeters: 1.2,
            swellWavePeriodSeconds: 12,
            swellWaveDirectionDegrees: 265,
            windWaveHeightMeters: 0.6,
            windWavePeriodSeconds: 6,
            windWaveDirectionDegrees: 300,
            seaSurfaceTemperatureC: 17.5,
            seaLevelHeightMeters: -0.35,
            tideTrend: .falling
        )

        draft.applySurfConditions(snapshot)

        XCTAssertEqual(draft.windSpeedKph, 12)
        XCTAssertEqual(draft.waveHeightMeters, 1.4)
        XCTAssertEqual(draft.conditionsSource, "Open-Meteo")
        XCTAssertEqual(draft.conditionsLatitude, 33.3)
        XCTAssertEqual(draft.conditionsLongitude, -117.6)
        XCTAssertEqual(draft.seaLevelHeightM, -0.35)
        XCTAssertEqual(draft.tideTrend, .falling)
        XCTAssertTrue(draft.hasSurfConditions)
    }

    /// A snapshot carrying nothing but tide still counts as conditions worth
    /// keeping — the editor uses `hasSurfConditions` to decide whether to warn
    /// before overwriting.
    func testTideAloneCountsAsSurfConditions() {
        var draft = SessionDraft()
        XCTAssertFalse(draft.hasSurfConditions)
        draft.tideTrend = .rising
        XCTAssertTrue(draft.hasSurfConditions)

        var other = SessionDraft()
        other.seaLevelHeightM = 0.2
        XCTAssertTrue(other.hasSurfConditions)
    }

    // MARK: - Quick log: time anchoring

    /// A blank draft is logged just after the surf, so the duration chips walk
    /// the *start* back from now — which is what lets a manual log overlap (and
    /// so suppress) the Watch workout for the same surf.
    func testAnchoredDraftCountsBackFromNow() {
        var draft = SessionDraft()
        draft.isAnchoredToNow = true
        let now = TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 8).addingTimeInterval(30)

        draft.setDuration(90, now: now)

        XCTAssertEqual(draft.durationMinutes, 90)
        XCTAssertEqual(draft.date, TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 6).addingTimeInterval(30 * 60))
        XCTAssertEqual(draft.endDate, TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 8))

        draft.setDuration(0, now: now)
        XCTAssertEqual(draft.date, TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 8))
        XCTAssertNil(draft.endDate)
    }

    /// Once the surfer sets the start time, the clock is theirs.
    func testSettingTheStartReleasesTheAnchor() {
        var draft = SessionDraft()
        draft.isAnchoredToNow = true
        let start = TestCalendar.makeDate(year: 2026, month: 3, day: 6, hour: 16)

        draft.setStartDate(start)
        draft.setDuration(120, now: TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 9))

        XCTAssertFalse(draft.isAnchoredToNow)
        XCTAssertEqual(draft.date, start)
        XCTAssertEqual(draft.durationMinutes, 120)
    }

    /// Prefilled drafts (timer, Watch) and edits carry real times.
    func testUnanchoredDraftKeepsItsStart() {
        var draft = SessionDraft()
        let start = TestCalendar.makeDate(year: 2026, month: 3, day: 6, hour: 6)
        draft.date = start

        draft.setDuration(60, now: TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 9))

        XCTAssertEqual(draft.date, start)
    }

    // MARK: - Quick log: history defaults

    func testDefaultsTakeTheLastSpotAndTheGearLastRiddenThere() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()

        let changed = QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)

        XCTAssertTrue(changed)
        XCTAssertEqual(draft.selectedSpot?.name, "Trestles")
        XCTAssertEqual(Set(draft.selectedGear.map(\.name)), ["6'2\" Fish", "3/2 Full"])
        XCTAssertTrue(draft.gearIsSuggested)
        XCTAssertTrue(draft.isReadyToSave)
    }

    /// Only the setup is guessed. A rating, notes, buddies or a swell reading
    /// belong to one day; carrying them over would put a stale number on today.
    func testDefaultsNeverCarryConditionsRatingNotesOrBuddies() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()

        QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)

        XCTAssertEqual(draft.rating, 0)
        XCTAssertEqual(draft.notes, "")
        XCTAssertTrue(draft.selectedBuddies.isEmpty)
        XCTAssertEqual(draft.durationMinutes, 0)
        XCTAssertFalse(draft.hasSurfConditions)
        XCTAssertFalse(draft.hasWaveStats)
    }

    /// An imported Watch surf can have no spot; the guess skips it.
    func testDefaultSpotSkipsSessionsWithoutASpot() throws {
        let fixture = try QuickLogFixture()
        let unknown = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 3, day: 9, hour: 7))
        fixture.context.insert(unknown)

        XCTAssertEqual(QuickLogDefaults.suggestedSpot(sessions: [unknown] + fixture.sessions)?.name, "Trestles")
    }

    /// A spot the draft already carries (timer, nearest to a Watch route) wins,
    /// and the gear follows that spot rather than the most recent session.
    func testDefaultsKeepAPrefilledSpotAndMatchItsGear() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()
        draft.selectSpot(fixture.oceanBeach)

        QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)

        XCTAssertEqual(draft.selectedSpot?.name, "Ocean Beach")
        XCTAssertEqual(draft.selectedGear.map(\.name), ["9'1\" Log"])
    }

    /// A typed name with no library match (a timer spot deleted mid-session)
    /// must not be replaced by a guess.
    func testDefaultsKeepATypedSpotName() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()
        draft.spotName = "Secret Reef"

        QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)

        XCTAssertNil(draft.selectedSpot)
        XCTAssertEqual(draft.spotName, "Secret Reef")
    }

    func testArchivedGearIsNeverSuggested() throws {
        let fixture = try QuickLogFixture()
        fixture.fish.isArchived = true

        let gear = QuickLogDefaults.suggestedGear(for: fixture.trestles, sessions: fixture.sessions)

        XCTAssertEqual(gear.map(\.name), ["3/2 Full"])
    }

    /// Switching spots swaps a *suggested* setup for the one last used there…
    func testSpotChangeSwapsSuggestedGear() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()
        QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)

        draft.selectSpot(fixture.oceanBeach)
        let changed = QuickLogDefaults.spotDidChange(in: &draft, sessions: fixture.sessions)

        XCTAssertTrue(changed)
        XCTAssertEqual(draft.selectedGear.map(\.name), ["9'1\" Log"])
        XCTAssertTrue(draft.gearIsSuggested)
    }

    /// …but never touches gear the surfer picked by hand.
    func testSpotChangeLeavesHandPickedGearAlone() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()
        QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)
        draft.toggleGear(fixture.wetsuit)

        draft.selectSpot(fixture.oceanBeach)
        let changed = QuickLogDefaults.spotDidChange(in: &draft, sessions: fixture.sessions)

        XCTAssertFalse(changed)
        XCTAssertFalse(draft.gearIsSuggested)
        XCTAssertEqual(draft.selectedGear.map(\.name), ["6'2\" Fish"])
    }

    /// "Same setup as last session" copies spot, gear and buddies only.
    func testSameSetupCopiesOnlyTheSetup() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()

        QuickLogDefaults.applySameSetup(from: fixture.latest, to: &draft)

        XCTAssertEqual(draft.selectedSpot?.name, "Trestles")
        XCTAssertEqual(Set(draft.selectedGear.map(\.name)), ["6'2\" Fish", "3/2 Full"])
        XCTAssertEqual(draft.selectedBuddies.map(\.name), ["Kai"])
        XCTAssertFalse(draft.gearIsSuggested)
        XCTAssertEqual(draft.rating, 0)
        XCTAssertEqual(draft.notes, "")
        XCTAssertFalse(draft.hasSurfConditions)
    }

    // MARK: - Quick log: discard guard

    func testChangeSignatureTracksEditsButNotRebuilds() throws {
        let fixture = try QuickLogFixture()
        var draft = SessionDraft()
        QuickLogDefaults.apply(to: &draft, sessions: fixture.sessions)
        let baseline = draft.changeSignature

        XCTAssertEqual(draft.changeSignature, baseline)

        draft.rating = 4
        XCTAssertNotEqual(draft.changeSignature, baseline)
        draft.rating = 0
        XCTAssertEqual(draft.changeSignature, baseline)

        draft.notes = "Glassy"
        XCTAssertNotEqual(draft.changeSignature, baseline)
        draft.notes = ""

        draft.mediaItems = [.newPhoto(photoData: Data([0x01]), thumbnailData: nil)]
        XCTAssertNotEqual(draft.changeSignature, baseline)
    }

    // MARK: - Quick log: Apple Watch surfs

    /// A Watch surf opens the editor with the workout's own times (never "now"),
    /// its route-derived stats marked as estimates, and the workout link that
    /// stops a save from writing a second workout to Health. No placeholder note.
    func testWatchDraftUsesWorkoutTimesAndEstimatedStats() {
        let workoutID = UUID()
        let start = TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 6)
        let workout = HealthKitLogic.WorkoutSummary(
            id: workoutID,
            start: start,
            end: start.addingTimeInterval(92 * 60),
            sourceName: "Apple Watch",
            isFromPeak: false
        )
        let stats = WaveStats(
            waveCount: 9,
            topSpeedKph: 26,
            longestRideSeconds: 0,
            longestRideMeters: 0,
            paddleDistanceMeters: 1_100,
            totalDistanceMeters: 1_500,
            waves: []
        )

        let draft = UnloggedSurfImporter.makeDraft(workout: workout, samples: [], stats: stats, spots: [])

        XCTAssertEqual(draft.date, start)
        XCTAssertEqual(draft.durationMinutes, 90)
        XCTAssertFalse(draft.isAnchoredToNow)
        XCTAssertEqual(draft.linkedWorkoutID, workoutID.uuidString)
        XCTAssertEqual(draft.waveCount, 9)
        XCTAssertEqual(draft.waveStatsSource, .auto)
        XCTAssertNil(draft.longestRideSeconds, "a zero ride is not a fact worth showing")
        XCTAssertEqual(draft.notes, "")
        XCTAssertFalse(HealthKitLogic.shouldWriteWorkout(linkedWorkoutID: draft.linkedWorkoutID))
    }

    func testWatchDraftWithoutStatsStillLinksTheWorkout() {
        let workoutID = UUID()
        let start = TestCalendar.makeDate(year: 2026, month: 3, day: 7, hour: 6)
        let workout = HealthKitLogic.WorkoutSummary(
            id: workoutID, start: start, end: start.addingTimeInterval(60 * 60),
            sourceName: "Apple Watch", isFromPeak: false
        )

        let draft = UnloggedSurfImporter.makeDraft(workout: workout, samples: [], stats: nil, spots: [])

        XCTAssertEqual(draft.linkedWorkoutID, workoutID.uuidString)
        XCTAssertNil(draft.waveStatsSource)
        XCTAssertFalse(draft.hasWaveStats)
    }
}

/// Three sessions, newest first: Trestles on the fish + wetsuit with a buddy,
/// a rating, notes and conditions; Ocean Beach on the log; an older Trestles.
private struct QuickLogFixture {
    let container: ModelContainer
    let context: ModelContext
    let trestles: Spot
    let oceanBeach: Spot
    let fish: Gear
    let wetsuit: Gear
    let log: Gear
    let latest: SurfSession
    let sessions: [SurfSession]

    @MainActor
    init() throws {
        container = try TestModelContainer.make()
        context = container.mainContext
        trestles = TestFixture.spot(name: "Trestles")
        oceanBeach = TestFixture.spot(name: "Ocean Beach")
        fish = TestFixture.gear(name: "6'2\" Fish")
        wetsuit = TestFixture.gear(name: "3/2 Full", kind: .wetsuit)
        log = TestFixture.gear(name: "9'1\" Log")
        let kai = TestFixture.buddy(name: "Kai")
        [trestles, oceanBeach].forEach(context.insert)
        [fish, wetsuit, log].forEach(context.insert)
        context.insert(kai)

        latest = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 3, day: 6, hour: 7),
            spot: trestles, gear: [fish, wetsuit], buddies: [kai],
            rating: 5, durationMinutes: 120, notes: "Overhead and glassy"
        )
        latest.windSpeedKph = 8
        latest.waveHeightMeters = 1.8
        latest.conditionsSource = "Open-Meteo"
        let middle = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 3, day: 4, hour: 7),
            spot: oceanBeach, gear: [log], rating: 3, durationMinutes: 60
        )
        let oldest = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 3, day: 1, hour: 7),
            spot: trestles, gear: [log], rating: 2, durationMinutes: 90
        )
        [latest, middle, oldest].forEach(context.insert)
        try context.save()
        sessions = [latest, middle, oldest]
    }
}


@MainActor
final class PeakExperienceTests: XCTestCase {
    func testVoiceLogParsesOnlyExplicitFieldsAndKnownEntities() {
        let spot = TestFixture.spot(name: "Linda Mar")
        let fish = TestFixture.gear(name: "Fish")
        let fields = VoiceLogParser.parse("Linda Mar, Fish, ninety minutes, four stars, clean early", spots: [spot], gear: [fish])
        XCTAssertEqual(fields.spot?.key, spot.key)
        XCTAssertEqual(fields.gear.map(\.key), [fish.key])
        XCTAssertEqual(fields.durationMinutes, 90)
        XCTAssertEqual(fields.rating, 4)
        XCTAssertEqual(fields.transcript, "Linda Mar, Fish, ninety minutes, four stars, clean early")
    }

    func testVoiceLogRejectsAmbiguousRatingsAndDurations() {
        let fields = VoiceLogParser.parse("60 minutes or 90 minutes, four stars or five stars", spots: [], gear: [])
        XCTAssertNil(fields.durationMinutes)
        XCTAssertNil(fields.rating)
        let correction = VoiceLogParser.parse("not four stars, actually two stars", spots: [], gear: [])
        XCTAssertNil(correction.rating)
    }

    func testVoiceLogDoesNotMatchPartOfNameOrArchivedGear() {
        let fish = TestFixture.gear(name: "Fish", isArchived: true)
        let fields = VoiceLogParser.parse("Fishing for ninety minutes", spots: [], gear: [fish])
        XCTAssertTrue(fields.gear.isEmpty)
        XCTAssertNil(fields.rating)
    }

    func testVoiceLogSupportsCompoundTimeAndRejectsOutOfRange() {
        XCTAssertEqual(VoiceLogParser.parse("one hour and thirty minutes", spots: [], gear: []).durationMinutes, 90)
        XCTAssertNil(VoiceLogParser.parse("900 minutes, 9 stars", spots: [], gear: []).durationMinutes)
        XCTAssertNil(VoiceLogParser.parse("900 minutes, 9 stars", spots: [], gear: []).rating)
    }

    func testVoiceCompoundNumbersNeverBecomeNumericSuffixes() {
        for (phrase, expected) in [("twenty five minutes", 25), ("forty five minutes", 45),
                                   ("forty-five minutes", 45), ("one hour and twenty five minutes", 85)] {
            XCTAssertEqual(VoiceLogParser.parse(phrase, spots: [], gear: []).durationMinutes, expected, phrase)
        }
        for phrase in ["one hundred and twenty five minutes", "one hundred minutes and five minutes",
                       "two point five minutes", "one hour and a half", "half an hour and five minutes",
                       "1,005 minutes", "minus five minutes", "twenty‑five minutes", "forty–five minutes", "twenty, five minutes"] {
            XCTAssertNil(VoiceLogParser.parse(phrase, spots: [], gear: []).durationMinutes, phrase)
        }
        XCTAssertNil(VoiceLogParser.parse("twenty five stars", spots: [], gear: []).rating)
        XCTAssertNil(VoiceLogParser.parse("four stars or twenty five stars", spots: [], gear: []).rating)
    }

    func testLogbookRejectsConflictingDateScopes() {
        let now = TestCalendar.makeDate(year: 2026, month: 7, day: 15)
        let sessions = [TestFixture.session(date: now),
                        TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 6, day: 15))]
        for question in ["Count sessions this month and last month", "How many sessions this month and this year?",
                         "Which board did I use most last month and this year?", "Find sessions this month and last month"] {
            let answer = LogbookQuery.answer(question, sessions: sessions, now: now, calendar: TestCalendar.gmt)
            XCTAssertEqual(answer.title, "Choose one date range", question)
            XCTAssertTrue(answer.sessions.isEmpty, "No partial answer may be presented as exact")
        }
    }

    func testDraftAutosaveReconcilesBaselineAndCancelsOlderDebounce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionDraftStore(directory: directory)
        var older = SessionDraft()
        older.notes = "Earlier interrupted surf"
        try await store.save(SavedSessionDraft(older), videos: [:])
        let autosave = SessionDraftAutosave(store: store)
        XCTAssertNil(autosave.update(nil))
        var draft = SessionDraft()
        draft.notes = "Erase this note"
        let pending = autosave.update(SavedSessionDraft(draft))
        await autosave.update(nil, immediately: true)?.value
        await pending?.value
        let untouchedOlder = try await store.load()
        XCTAssertEqual(untouchedOlder?.notes, older.notes, "Undo before debounce must not erase another interrupted surf")
        await autosave.update(SavedSessionDraft(draft), immediately: true)?.value
        let saved = try await store.load()
        XCTAssertEqual(saved?.notes, draft.notes)
        await autosave.update(nil, immediately: true)?.value
        let cleared = try await store.load()
        XCTAssertNil(cleared, "Undo to a blank baseline must retire the already persisted note")

        try await store.save(SavedSessionDraft(older), videos: [:])
        let recoveredValue = try await store.load()
        let recovered = try XCTUnwrap(recoveredValue).restore(spots: [], gear: [], buddies: [])
        XCTAssertTrue(recovered.isRecoveredDraft)
        var edited = recovered
        edited.notes = "Temporary edit"
        let resumed = SessionDraftAutosave(store: store)
        await resumed.update(SavedSessionDraft(edited), immediately: true)?.value
        await resumed.update(SavedSessionDraft(recovered), immediately: true)?.value
        let restoredBaseline = try await store.load()
        XCTAssertEqual(restoredBaseline?.notes, older.notes, "A resumed surf's baseline is still an unsaved surf")

        let encoded = try JSONEncoder().encode(SavedSessionDraft(older))
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "draftID")
        let legacy = try JSONDecoder().decode(SavedSessionDraft.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        try await store.save(legacy, videos: [:])
        let legacyDraft = try legacy.restore(spots: [], gear: [], buddies: [])
        await resumed.clear(draftID: legacyDraft.recoveryID, allowLegacy: true).value
        let removedLegacy = try await store.load()
        XCTAssertNil(removedLegacy, "Explicit discard must also remove a resumed file from the older format")

        // A failed durable write must report failure and retain picker media
        // for the still-open editor to retry, rather than retiring it on close.
        let blockedDirectory = directory.appendingPathComponent("not-a-directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1]).write(to: blockedDirectory)
        let temporaryVideo = directory.appendingPathComponent("picker.mov")
        try Data([2, 3]).write(to: temporaryVideo)
        let failedAutosave = SessionDraftAutosave(store: SessionDraftStore(directory: blockedDirectory))
        var reportedFailure = false
        await failedAutosave.update(SavedSessionDraft(draft), immediately: true,
                                    retiringFiles: [temporaryVideo]) { error in
            reportedFailure = error != nil
        }?.value
        XCTAssertTrue(reportedFailure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryVideo.path))
    }

    func testQuiverAdvisorRequiresComparableSingleBoardEvidence() {
        let spot = TestFixture.spot()
        let other = TestFixture.spot(name: "Other")
        let fish = TestFixture.gear(name: "Fish")
        let stepup = TestFixture.gear(name: "Step Up")
        let sessions = (0..<3).map { _ in TestFixture.session(spot: spot, gear: [fish], rating: 5) }
            + (0..<3).map { _ in TestFixture.session(spot: other, gear: [stepup], rating: 1) }
        let report = QuiverAdvisor.compare(spot: spot, height: nil, period: nil, gear: [fish,stepup], sessions: sessions)
        XCTAssertEqual(report.comparisons.count, 1)
        XCTAssertNil(report.suggestedBoard)
        XCTAssertTrue(QuiverAdvisor.compare(spot: spot, height: .overhead, period: nil, gear: [fish], sessions: sessions).comparisons.isEmpty)
    }

    func testQuiverAdvisorAbstainsOnTieAndSuggestsSeparatedCohort() {
        let spot = TestFixture.spot()
        let a = TestFixture.gear(name: "A")
        let b = TestFixture.gear(name: "B")
        let first = (0..<3).map { _ in TestFixture.session(spot: spot, gear: [a], rating: 5) }
        let second = (0..<3).map { _ in TestFixture.session(spot: spot, gear: [b], rating: 2) }
        let report = QuiverAdvisor.compare(spot: spot, height: nil, period: nil, gear: [a,b], sessions: first+second)
        XCTAssertEqual(report.suggestedBoard?.key, a.key)
        second.forEach { $0.rating = 5 }
        XCTAssertNil(QuiverAdvisor.compare(spot: spot, height: nil, period: nil, gear: [a,b], sessions: first+second).suggestedBoard)
        b.isArchived = true
        XCTAssertEqual(QuiverAdvisor.compare(spot: spot, height: nil, period: nil, gear: [a,b], sessions: first+second).comparisons.count, 1)
    }

    func testLogbookAnswersExactMonthCountAndBoardTie() {
        let now = TestCalendar.makeDate(year: 2026, month: 3, day: 15)
        let a = TestFixture.gear(name: "Fish")
        let b = TestFixture.gear(name: "Shortboard")
        let sessions = [TestFixture.session(date: now, gear: [a]), TestFixture.session(date: now, gear: [b]),
                        TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), gear: [a])]
        let count = LogbookQuery.answer("How many sessions this month?", sessions: sessions, now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(count.sessions.count, 2)
        XCTAssertEqual(count.title, "2 logged sessions")
        let tie = LogbookQuery.answer("Which board did I use most this month?", sessions: sessions, now: now, calendar: TestCalendar.gmt)
        XCTAssertTrue(tie.explanation.contains("tied"))
        XCTAssertTrue(tie.title.contains("Fish"))
        XCTAssertTrue(tie.title.contains("Shortboard"))
    }

    func testLogbookUnknownScopeNeverBecomesWholeLibraryCount() {
        let sessions = [TestFixture.session()]
        XCTAssertTrue(LogbookQuery.answer("How many sessions at Unknown?", sessions: sessions).sessions.isEmpty)
        XCTAssertTrue(LogbookQuery.answer("How many waves?", sessions: sessions).sessions.isEmpty)
        XCTAssertFalse(LogbookQuery.answer("How many sessions last week?", sessions: sessions).needsFilters)
        XCTAssertTrue(LogbookQuery.answer("Find not clean sessions", sessions: sessions).sessions.isEmpty)
    }

    func testLogbookRejectsPartiallyUnderstoodCountsAndUsesWholeNames() {
        let spot = TestFixture.spot(name: "Mar")
        let fish = TestFixture.gear(name: "Fish")
        let sessions = [TestFixture.session(spot: spot, gear: [fish])]
        for question in ["How many sessions last summer?", "Count five star sessions", "How many sessions with a broken board?",
                         "How many sessions at Mars?", "Find clean sessions last summer", "Which board performed best?"] {
            XCTAssertTrue(LogbookQuery.answer(question, sessions: sessions).sessions.isEmpty, question)
        }
        XCTAssertEqual(LogbookQuery.answer("How many sessions at Mar with Fish?", sessions: sessions).sessions.count, 1)
    }

    func testSurfPlanExpiresAndNeverCopiesForecastIntoLog() throws {
        let now = TestCalendar.makeDate(year: 2026, month: 3, day: 15)
        let spot = TestFixture.spot()
        let gear = TestFixture.gear()
        let plan = SurfPlan(id: UUID(), spotKey: spot.key, spotName: spot.name, gearKeys: [gear.key],
                            start: now, end: now.addingTimeInterval(7200), fetchedAt: now, summary: "Forecast")
        let draft = try XCTUnwrap(SurfPlanStore.draft(for: plan, spots: [spot], gear: [gear], now: now))
        XCTAssertFalse(draft.hasSurfConditions)
        XCTAssertEqual(draft.rating, 0)
        XCTAssertEqual(draft.durationMinutes, 0)
        XCTAssertNil(SurfPlanStore.draft(for: plan, spots: [], gear: [gear], now: now))
        XCTAssertFalse(plan.isUsable(at: now.addingTimeInterval(7201)))
    }

    func testResumedVideoOwnsCopyAndPreservesDurableRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: source) }
        try Data("draft video".utf8).write(to: source)
        var draft = SessionDraft()
        let item = SessionMediaDraftItem.newVideo(temporaryURL: source, thumbnailData: nil)
        draft.mediaItems = [item]
        let store = SessionDraftStore(directory: directory)
        let snapshot = SavedSessionDraft(draft)
        try await store.save(snapshot, videos: [item.id: source])
        let copies = try await snapshot.prepareVideoCopies(in: directory)
        let resumed = try snapshot.restore(spots: [], gear: [], buddies: [], videoCopies: copies)
        let temp = try XCTUnwrap(resumed.mediaItems.first?.temporaryVideoURL)
        XCTAssertEqual(resumed.mediaItems.first?.id, item.id)
        XCTAssertEqual(try Data(contentsOf: temp), Data("draft video".utf8))
        SessionMediaStore.deleteTemporaryFiles([temp])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(item.id.uuidString + ".mov")), Data("draft video".utf8))
    }

    func testDraftRecoveryPreservesCorrectionsAndMediaAndClearWinsOverLateSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionDraftStore(directory: directory)
        let spot = TestFixture.spot()
        var draft = SessionDraft()
        draft.selectSpot(spot)
        draft.notes = "Keep this note"
        draft.waveCount = 9
        draft.waveStatsSource = .edited
        draft.conditionsSource = "Open-Meteo"
        draft.conditionsFetchedAt = Date()
        draft.mediaItems = [.newPhoto(photoData: Data([1,2,3]), thumbnailData: nil)]
        let snapshot = SavedSessionDraft(draft)
        try await store.save(snapshot, videos: [:])
        let loadedValue = try await store.load()
        let loaded = try XCTUnwrap(loadedValue)
        let restored = try loaded.restore(spots: [spot], gear: [], buddies: [])
        XCTAssertEqual(restored.notes, draft.notes)
        XCTAssertEqual(restored.waveCount, 9)
        XCTAssertEqual(restored.waveStatsSource, .edited)
        XCTAssertEqual(restored.mediaItems[0].photoData, Data([1,2,3]))
        XCTAssertEqual(restored.mediaItems[0].id, draft.mediaItems[0].id)
        XCTAssertEqual(restored.mediaItems[0].createdAt, draft.mediaItems[0].createdAt)
        try await store.clear(at: snapshot.savedAt.addingTimeInterval(1))
        try await store.save(snapshot, videos: [:])
        let afterClear = try await store.load()
        XCTAssertNil(afterClear)
    }
}

@MainActor
final class ExperienceBoundaryTests: XCTestCase {
    func testReplayNeverConnectsAcrossBadFixesOrTimeGaps() {
        let start = Date(timeIntervalSince1970: 0)
        func fix(_ seconds: Double, accuracy: Double = 4) -> RouteSample {
            RouteSample(timestamp: start.addingTimeInterval(seconds), latitude: 33, longitude: -117 + seconds / 100_000,
                        speedMetersPerSecond: 3, horizontalAccuracyMeters: accuracy)
        }
        let tracks = RouteReplay.tracks([fix(0), fix(1), fix(2, accuracy: 50), fix(3), fix(4), fix(20), fix(21)])
        XCTAssertEqual(tracks.count, 3)
        XCTAssertTrue(tracks.allSatisfy { $0.count == 2 })
        XCTAssertFalse(tracks.flatMap { $0 }.contains { $0.horizontalAccuracyMeters == 50 })
    }

    func testWidgetPlanExpiryMatchesAppPlanExpiry() {
        let now = Date()
        let end = now.addingTimeInterval(8 * 3600)
        let glance = PeakPlanGlance(spotKey: "spot", spotName: "Spot", gearKeys: [], start: now, end: end, fetchedAt: now, summary: "")
        let plan = SurfPlan(id: UUID(), spotKey: "spot", spotName: "Spot", gearKeys: [], start: now, end: end, fetchedAt: now, summary: "")
        for offset in [-100.0, 0, 3600, 21600, 30000] {
            let date = now.addingTimeInterval(offset)
            XCTAssertEqual(plan.isUsable(at: date), glance.isUsable(at: date))
        }
    }

    func testEndedSurfRetainsExplicitSetupButExcludesArchivedGear() {
        let spot = TestFixture.spot()
        let board = TestFixture.gear(name: "Board")
        let archived = TestFixture.gear(name: "Old", isArchived: true)
        let start = Date()
        let state = ActiveSessionState(spotKey: spot.key, spotName: spot.name, startDate: start, gearKeys: [board.key, archived.key])
        let record = EndedSessionRecord(state: state, endedAt: start.addingTimeInterval(3600))
        let draft = ActiveSessionCalculator.makeDraft(from: record, spots: [spot], gear: [board, archived])
        XCTAssertEqual(draft.selectedGear.map(\.key), [board.key])
        XCTAssertEqual(draft.durationMinutes, 60)
        XCTAssertEqual(draft.rating, 0)
        XCTAssertFalse(draft.hasSurfConditions)
    }
}
