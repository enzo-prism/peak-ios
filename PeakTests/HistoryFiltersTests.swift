import XCTest

@testable import Peak

final class HistoryFiltersTests: XCTestCase {
    func testMatchesReturnsTrueWhenFiltersInactive() {
        let session = TestFixture.session()
        let filters = HistoryFilters()

        XCTAssertTrue(filters.matches(session: session))
    }

    func testMatchesRespectsSpotGearBuddy() {
        let spot = TestFixture.spot(name: "Trestles")
        let gear = TestFixture.gear(name: "6'2\" Fish")
        let buddy = TestFixture.buddy(name: "Kai")
        let session = TestFixture.session(spot: spot, gear: [gear], buddies: [buddy])

        var filters = HistoryFilters()
        filters.spot = spot
        XCTAssertTrue(filters.matches(session: session))

        filters.gear = gear
        XCTAssertTrue(filters.matches(session: session))

        filters.buddy = buddy
        XCTAssertTrue(filters.matches(session: session))

        let otherSpot = TestFixture.spot(name: "Ocean Beach")
        filters.spot = otherSpot
        XCTAssertFalse(filters.matches(session: session))
    }
}
