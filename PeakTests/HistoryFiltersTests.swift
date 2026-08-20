import XCTest

@testable import Peak

final class HistoryFiltersTests: XCTestCase {
    private let now = TestCalendar.makeDate(year: 2026, month: 7, day: 15, hour: 6)
    private var calendar: Calendar { TestCalendar.gmt }

    // MARK: - Inactive filters

    func testMatchesReturnsTrueWhenFiltersInactive() {
        let session = TestFixture.session()
        let filters = HistoryFilters()

        XCTAssertFalse(filters.isActive)
        XCTAssertTrue(filters.matches(session: session))
    }

    func testApplyWithoutCriteriaReturnsAllSessionsInOrder() {
        let first = TestFixture.session(notes: "first")
        let second = TestFixture.session(notes: "second")
        let filters = HistoryFilters()

        let result = filters.apply(to: [first, second])

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0] === first)
        XCTAssertTrue(result[1] === second)
    }

    // MARK: - Multi-select spots

    func testMultiSpotSelectionMatchesAnySelectedSpot() {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")
        let mavericks = TestFixture.spot(name: "Mavericks")
        let atTrestles = TestFixture.session(spot: trestles)
        let atOceanBeach = TestFixture.session(spot: oceanBeach)
        let atMavericks = TestFixture.session(spot: mavericks)
        let noSpot = TestFixture.session(spot: nil)

        var filters = HistoryFilters()
        filters.spots = [trestles, oceanBeach]

        let result = filters.apply(to: [atTrestles, atOceanBeach, atMavericks, noSpot])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0 === atTrestles }))
        XCTAssertTrue(result.contains(where: { $0 === atOceanBeach }))
        XCTAssertFalse(filters.matches(session: atMavericks))
        XCTAssertFalse(filters.matches(session: noSpot))
    }

    // MARK: - Multi-select gear

    func testMultiGearSelectionMatchesSessionsContainingAnySelectedGear() {
        let fish = TestFixture.gear(name: "6'2\" Fish")
        let log = TestFixture.gear(name: "9'6\" Log")
        let gun = TestFixture.gear(name: "8'0\" Gun")
        let withFish = TestFixture.session(gear: [fish])
        let withLogAndGun = TestFixture.session(gear: [log, gun])
        let withoutGear = TestFixture.session()

        var filters = HistoryFilters()
        filters.gear = [fish, log]

        XCTAssertTrue(filters.matches(session: withFish))
        XCTAssertTrue(filters.matches(session: withLogAndGun))
        XCTAssertFalse(filters.matches(session: withoutGear))
    }

    // MARK: - Multi-select buddies

    func testMultiBuddySelectionMatchesSessionsContainingAnySelectedBuddy() {
        let kai = TestFixture.buddy(name: "Kai")
        let noa = TestFixture.buddy(name: "Noa")
        let moana = TestFixture.buddy(name: "Moana")
        let withKai = TestFixture.session(buddies: [kai])
        let withMoana = TestFixture.session(buddies: [moana])
        let solo = TestFixture.session()

        var filters = HistoryFilters()
        filters.buddies = [kai, noa]

        XCTAssertTrue(filters.matches(session: withKai))
        XCTAssertFalse(filters.matches(session: withMoana))
        XCTAssertFalse(filters.matches(session: solo))
    }

    // MARK: - Minimum rating

    func testMinimumRatingKeepsSessionsAtOrAboveThreshold() {
        let unrated = TestFixture.session(rating: 0)
        let two = TestFixture.session(rating: 2)
        let three = TestFixture.session(rating: 3)
        let five = TestFixture.session(rating: 5)

        var filters = HistoryFilters()
        filters.minimumRating = 3

        let result = filters.apply(to: [unrated, two, three, five])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0 === three }))
        XCTAssertTrue(result.contains(where: { $0 === five }))
    }

    func testMinimumRatingZeroMatchesUnratedSessions() {
        let unrated = TestFixture.session(rating: 0)
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: unrated))
    }

    // MARK: - Date ranges

    func testDateRangeThisMonth() {
        var filters = HistoryFilters()
        filters.dateRange = .thisMonth

        let inMonth = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 7, day: 1))
        let priorMonth = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 6, day: 30, hour: 23))

        XCTAssertTrue(filters.matches(session: inMonth, now: now, calendar: calendar))
        XCTAssertFalse(filters.matches(session: priorMonth, now: now, calendar: calendar))
    }

    func testDateRangeLastThreeMonthsUsesRollingCutoff() {
        var filters = HistoryFilters()
        filters.dateRange = .lastThreeMonths

        // now = 2026-07-15 06:00 GMT, so the cutoff is 2026-04-15 06:00 GMT.
        let insideWindow = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 4, day: 15, hour: 7))
        let onWindowEdge = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 4, day: 15, hour: 6))
        let outsideWindow = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 4, day: 15, hour: 5))

        XCTAssertTrue(filters.matches(session: insideWindow, now: now, calendar: calendar))
        XCTAssertTrue(filters.matches(session: onWindowEdge, now: now, calendar: calendar))
        XCTAssertFalse(filters.matches(session: outsideWindow, now: now, calendar: calendar))
    }

    func testDateRangeThisYear() {
        var filters = HistoryFilters()
        filters.dateRange = .thisYear

        let january = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 1, day: 1))
        let lastYear = TestFixture.session(date: TestCalendar.makeDate(year: 2025, month: 12, day: 31, hour: 23))

        XCTAssertTrue(filters.matches(session: january, now: now, calendar: calendar))
        XCTAssertFalse(filters.matches(session: lastYear, now: now, calendar: calendar))
    }

    func testDateRangeAllTimeMatchesEverything() {
        let ancient = TestFixture.session(date: TestCalendar.makeDate(year: 1999, month: 1, day: 1))
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: ancient, now: now, calendar: calendar))
    }

    // MARK: - Search

    func testSearchMatchesSpotNameCaseInsensitively() {
        let session = TestFixture.session(spot: TestFixture.spot(name: "Trestles"))
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "trest"))
        XCTAssertTrue(filters.matches(session: session, searchText: "TREST"))
        XCTAssertFalse(filters.matches(session: session, searchText: "mavericks"))
    }

    func testSearchMatchesSpotLocationName() {
        let spot = TestFixture.spot(name: "The Point", locationName: "San Clemente, California")
        let session = TestFixture.session(spot: spot)
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "san clemente"))
    }

    func testSearchMatchesNotes() {
        let session = TestFixture.session(notes: "Glassy dawn patrol, overhead sets")
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "dawn patrol"))
        XCTAssertFalse(filters.matches(session: session, searchText: "closeouts"))
    }

    func testSearchMatchesBuddyNames() {
        let session = TestFixture.session(buddies: [TestFixture.buddy(name: "Kai"), TestFixture.buddy(name: "Noa")])
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "noa"))
        XCTAssertFalse(filters.matches(session: session, searchText: "moana"))
    }

    func testSearchMatchesGearNames() {
        let session = TestFixture.session(gear: [TestFixture.gear(name: "9'6\" Log")])
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "log"))
        XCTAssertFalse(filters.matches(session: session, searchText: "fish"))
    }

    func testSearchIsDiacriticInsensitiveBothWays() {
        let session = TestFixture.session(spot: TestFixture.spot(name: "São Pedro"))
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "sao"))
        XCTAssertTrue(filters.matches(session: session, searchText: "SÃO"))

        let plain = TestFixture.session(spot: TestFixture.spot(name: "Sao Pedro"))
        XCTAssertTrue(filters.matches(session: plain, searchText: "sÃo"))
    }

    func testWhitespaceOnlySearchMatchesEverything() {
        let session = TestFixture.session()
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "   "))
        XCTAssertTrue(filters.matches(session: session, searchText: "\n"))
    }

    func testSearchWithoutSpotDoesNotCrashAndMatchesNotesOnly() {
        let session = TestFixture.session(spot: nil, notes: "boardless bodysurf")
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session, searchText: "bodysurf"))
        XCTAssertFalse(filters.matches(session: session, searchText: "trestles"))
    }

    // MARK: - Combined semantics (AND across search + filter categories)

    func testSearchAndFiltersUseANDSemantics() {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")
        let kai = TestFixture.buddy(name: "Kai")

        let match = TestFixture.session(spot: trestles, buddies: [kai], rating: 4, notes: "Firing rights")
        let wrongSpot = TestFixture.session(spot: oceanBeach, buddies: [kai], rating: 5, notes: "Firing rights")
        let lowRating = TestFixture.session(spot: trestles, buddies: [kai], rating: 2, notes: "Firing rights")
        let wrongNotes = TestFixture.session(spot: trestles, buddies: [kai], rating: 4, notes: "Mushy lefts")

        var filters = HistoryFilters()
        filters.spots = [trestles]
        filters.buddies = [kai]
        filters.minimumRating = 3

        let result = filters.apply(to: [match, wrongSpot, lowRating, wrongNotes], searchText: "firing")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0] === match)
    }

    // MARK: - isActive / clear / toggles

    func testIsActiveReflectsEachDimension() {
        var filters = HistoryFilters()
        XCTAssertFalse(filters.isActive)

        filters.spots = [TestFixture.spot()]
        XCTAssertTrue(filters.isActive)
        filters.clear()

        filters.gear = [TestFixture.gear()]
        XCTAssertTrue(filters.isActive)
        filters.clear()

        filters.buddies = [TestFixture.buddy()]
        XCTAssertTrue(filters.isActive)
        filters.clear()

        filters.minimumRating = 1
        XCTAssertTrue(filters.isActive)
        filters.clear()

        filters.dateRange = .thisYear
        XCTAssertTrue(filters.isActive)
        filters.clear()

        XCTAssertFalse(filters.isActive)
    }

    func testClearResetsAllCriteria() {
        var filters = HistoryFilters()
        filters.spots = [TestFixture.spot()]
        filters.gear = [TestFixture.gear()]
        filters.buddies = [TestFixture.buddy()]
        filters.minimumRating = 4
        filters.dateRange = .lastThreeMonths

        filters.clear()

        XCTAssertTrue(filters.spots.isEmpty)
        XCTAssertTrue(filters.gear.isEmpty)
        XCTAssertTrue(filters.buddies.isEmpty)
        XCTAssertEqual(filters.minimumRating, 0)
        XCTAssertEqual(filters.dateRange, .allTime)
        XCTAssertFalse(filters.isActive)
    }

    func testToggleHelpersInsertAndRemove() {
        let spot = TestFixture.spot()
        let item = TestFixture.gear()
        let buddy = TestFixture.buddy()
        var filters = HistoryFilters()

        filters.toggleSpot(spot)
        filters.toggleGear(item)
        filters.toggleBuddy(buddy)
        XCTAssertTrue(filters.spots.contains(spot))
        XCTAssertTrue(filters.gear.contains(item))
        XCTAssertTrue(filters.buddies.contains(buddy))

        filters.toggleSpot(spot)
        filters.toggleGear(item)
        filters.toggleBuddy(buddy)
        XCTAssertFalse(filters.isActive)
    }

    // MARK: - History / Search list mode

    func testDedicatedSearchWithoutQueryShowsPromptNotTheTimeline() {
        let mode = HistoryListMode.resolve(
            sessionCount: 4,
            isDedicatedSearchTab: true,
            hasActiveCriteria: false,
            matchCount: 4
        )
        XCTAssertEqual(mode, .searchPrompt)
    }

    func testHistoryWithoutQueryShowsTheTimeline() {
        let mode = HistoryListMode.resolve(
            sessionCount: 4,
            isDedicatedSearchTab: false,
            hasActiveCriteria: false,
            matchCount: 4
        )
        XCTAssertEqual(mode, .results)
    }

    func testDedicatedSearchWithNoMatches() {
        let mode = HistoryListMode.resolve(
            sessionCount: 4,
            isDedicatedSearchTab: true,
            hasActiveCriteria: true,
            matchCount: 0
        )
        XCTAssertEqual(mode, .noMatches)
    }

    func testLibrarySessionPreviewRemainderStartsAfterTheVisiblePrefix() {
        XCTAssertEqual(LibrarySessionPreview.remainderCount(total: 5), 0)
        XCTAssertEqual(LibrarySessionPreview.remainderCount(total: 6), 1)
        XCTAssertEqual(LibrarySessionPreview.remainderCount(total: 0), 0)
    }
}
