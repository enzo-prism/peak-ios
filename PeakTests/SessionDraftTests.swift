import CoreGraphics
import SwiftData
import XCTest

@testable import Peak

final class SessionDraftTests: XCTestCase {
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
